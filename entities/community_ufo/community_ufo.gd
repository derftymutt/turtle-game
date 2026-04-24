extends RigidBody2D
class_name CommunityUFO

# ============================================================
# SINKING PHASE — behavior before the turtle enters
# ============================================================
@export_group("Sinking")
@export var sink_gravity_scale: float = 0.12
@export var sink_linear_damp: float = 3.5
@export var bob_force: float = 80.0       # Oscillating force amplitude while sinking
@export var bob_speed: float = 1.8        # Bob cycles per second

# ============================================================
# AIMING PHASE — arrow controls
# ============================================================
@export_group("Aiming")
## Degrees per second the arrow rotates when holding left or right
@export var arrow_rotation_speed: float = 120.0
@export var arrow_length: float = 55.0
## Starting angle in degrees. -90 = straight up.
@export var initial_arrow_angle_deg: float = -90.0

# ============================================================
# LAUNCH — windup mechanics
# ============================================================
@export_group("Launch")
## Input action mapped to the windup button (A / Space by default via "ufo_windup")
@export var windup_button: String = "ufo_windup"
## Impulse applied even with zero windup (so a tap always does something)
@export var min_launch_force: float = 200.0
## Hard cap on launch impulse
@export var max_launch_force: float = 2500.0
## Force added per second while holding the windup button
@export var windup_rate: float = 5000.0
## Charge oscillates back down once it hits max (yoyo pattern) — more skill-based
@export var windup_yoyo: bool = true
## Seconds the player can hold the button before the UFO auto-launches
@export var max_windup_hold_time: float = 2.0

# ============================================================
# FLIGHT — behavior after launch
# ============================================================
@export_group("Flight")
## Seconds until the UFO auto-bursts after launch
@export var flight_duration: float = 1.0
## Set to 0 for horizontal flight; increase for arc trajectories
@export var flight_gravity_scale: float = 0.0
## Low damp = UFO travels far; high damp = decelerates quickly
@export var flight_linear_damp: float = 0.4
## Seconds after launch during which the UFO passes through everything.
## Set to 0 to disable.
@export var pass_through_duration: float = 0.25
## Pass-through only activates when charge is at or above this fraction of max_launch_force.
## 1.0 = only at full charge, 0.8 = top 20%, 0.0 = always. Pairs with the yoyo peak.
@export_range(0.0, 1.0, 0.05) var pass_through_min_charge_fraction: float = 0.85
## If true, hitting a wall immediately bursts the UFO
@export var burst_on_wall_contact: bool = false
## If true, hitting an enemy immediately bursts the UFO
@export var burst_on_enemy_contact: bool = false

# ============================================================
# COMBAT — enemy interaction during flight
# ============================================================
@export_group("Combat")
@export var enemy_damage: float = 60.0
@export var enemy_hit_cooldown: float = 0.5    # Prevent spam-hitting same enemy
@export var enemy_knockback: float = 250.0

# ============================================================
# VISUAL — all procedurally drawn
# ============================================================
@export_group("Visual")
@export var ufo_radius: float = 22.0
## Main disc color — values > 1 push into HDR/bloom range
@export var ufo_color: Color = Color(0.6, 1.0, 2.2)
@export var ufo_rim_color: Color = Color(0.3, 0.7, 1.0)
@export var dome_color: Color = Color(0.7, 1.0, 0.7, 0.55)
@export var arrow_idle_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var arrow_charging_color: Color = Color(1.0, 0.2, 0.0, 1.0)
@export var glow_color: Color = Color(0.4, 0.8, 2.0, 0.3)
## Burst particle colors (picked randomly)
@export var burst_colors: Array[Color] = [
	Color(0.5, 1.0, 2.2),
	Color(1.0, 1.0, 0.4),
	Color(1.0, 1.0, 1.0),
	Color(0.5, 2.0, 1.0),
]

# ============================================================
# INTERNAL STATE
# ============================================================

enum Phase { SINKING, AIMING, FLYING, BURSTING }

var phase: Phase = Phase.SINKING
var arrow_angle_deg: float = -90.0
var current_charge: float = 0.0
var flight_timer: float = 0.0
var bob_offset: float = 0.0
var turtle_player: Node2D = null
var ocean: Ocean = null
var _was_charging: bool = false
var _windup_direction: int = 1      # 1 = charging up, -1 = yoyo back down
var _windup_hold_timer: float = 0.0
var _pass_through_timer: float = 0.0
var _normal_collision_mask: int = 0
var _hit_enemies: Dictionary = {}
var _pickup_area: Area2D = null
var _damage_area: Area2D = null
var _stored_shield: bool = false

signal player_entered(ufo: CommunityUFO)
signal ufo_burst

func _ready():
	gravity_scale = sink_gravity_scale
	linear_damp = sink_linear_damp
	angular_damp = 10.0
	mass = 1.8
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("community_ufo")

	# UFO body should only collide with walls (Layer 1 = World_Player).
	# Detecting the turtle is handled by the PickupArea2D below, NOT by
	# body-to-body physics — otherwise the turtle bumps the UFO instead of entering.
	# collision_mask = 1

	arrow_angle_deg = initial_arrow_angle_deg
	bob_offset = randf() * TAU

	_build_pickup_area()
	_build_damage_area()
	body_entered.connect(_on_body_entered)

# ──────────────────────────────────────────────────────────────────────────────
# AREA SETUP
# ──────────────────────────────────────────────────────────────────────────────

func _build_pickup_area():
	_pickup_area = Area2D.new()
	_pickup_area.name = "PickupArea"
	_pickup_area.collision_layer = 0
	_pickup_area.collision_mask = 32  # Layer 6 = Player (turtle's collision_layer)
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = ufo_radius + 10.0
	shape.shape = circle
	_pickup_area.add_child(shape)
	add_child(_pickup_area)
	_pickup_area.body_entered.connect(_on_pickup_area_entered)

func _build_damage_area():
	_damage_area = Area2D.new()
	_damage_area.name = "DamageArea"
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 4  # Layer 3 = enemies
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = ufo_radius + 4.0
	shape.shape = circle
	_damage_area.add_child(shape)
	add_child(_damage_area)
	_damage_area.body_entered.connect(_on_damage_area_entered)

# ──────────────────────────────────────────────────────────────────────────────
# PHYSICS PROCESS
# ──────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float):
	# Tick per-enemy hit cooldowns
	for enemy in _hit_enemies.keys():
		_hit_enemies[enemy] -= delta
		if _hit_enemies[enemy] <= 0.0:
			_hit_enemies.erase(enemy)

	match phase:
		Phase.SINKING:  _tick_sinking(delta)
		Phase.AIMING:   _tick_aiming(delta)
		Phase.FLYING:   _tick_flying(delta)
		Phase.BURSTING: pass

	queue_redraw()

func _tick_sinking(delta: float):
	bob_offset += bob_speed * delta
	apply_central_force(Vector2(0.0, -sin(bob_offset) * bob_force))

func _tick_aiming(delta: float):
	if not is_instance_valid(turtle_player):
		_exit_ufo_and_free()
		return

	# Park turtle at UFO center while aiming
	if turtle_player is RigidBody2D:
		turtle_player.global_position = global_position

	# Eject without launching (drop_piece button while in UFO)
	if Input.is_action_just_pressed("drop_piece"):
		_exit_ufo_and_free()
		return

	# Rotate arrow with L/R input
	var h = Input.get_axis("move_left", "move_right")
	arrow_angle_deg += h * arrow_rotation_speed * delta

	# Windup: accumulate (or yoyo) charge while button is held
	if Input.is_action_pressed(windup_button):
		_was_charging = true
		_windup_hold_timer += delta

		current_charge += windup_rate * _windup_direction * delta

		if windup_yoyo:
			if current_charge >= max_launch_force:
				current_charge = max_launch_force
				_windup_direction = -1
			elif current_charge <= min_launch_force:
				current_charge = min_launch_force
				_windup_direction = 1
		else:
			current_charge = clamp(current_charge, min_launch_force, max_launch_force)

		# Auto-launch if held too long
		if _windup_hold_timer >= max_windup_hold_time:
			_launch()
	elif _was_charging and not Input.is_action_pressed(windup_button):
		_launch()

func _tick_flying(delta: float):
	# Keep turtle glued inside the UFO
	if is_instance_valid(turtle_player) and turtle_player is RigidBody2D:
		turtle_player.global_position = global_position
	elif not is_instance_valid(turtle_player):
		_burst()
		return

	# Pass-through window countdown
	if _pass_through_timer > 0.0:
		_pass_through_timer -= delta
		if _pass_through_timer <= 0.0:
			collision_mask = _normal_collision_mask
			if _damage_area:
				_damage_area.monitoring = true

	flight_timer -= delta
	if flight_timer <= 0.0:
		_burst()

# ──────────────────────────────────────────────────────────────────────────────
# PHASE TRANSITIONS
# ──────────────────────────────────────────────────────────────────────────────

func _on_pickup_area_entered(body: Node2D):
	if phase != Phase.SINKING:
		return
	if body.is_in_group("player"):
		_enter_ufo(body)

func _enter_ufo(player: Node2D):
	phase = Phase.AIMING
	turtle_player = player

	# Freeze UFO in place so the player has a stable platform to aim from
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	# Suspend player input and hide sprite
	player.control_suspended = true
	player.control_suspend_timer = 999999.0
	var sprite = player.get_node_or_null("AnimatedSprite2D")
	if sprite:
		sprite.visible = false
		sprite.scale = Vector2.ONE  # Reset any leftover scale from super speed
	if player is RigidBody2D:
		player.freeze = true
		player.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		player.linear_velocity = Vector2.ZERO

	current_charge = min_launch_force
	_was_charging = false
	_windup_direction = 1
	_windup_hold_timer = 0.0
	arrow_angle_deg = initial_arrow_angle_deg

	emit_signal("player_entered", self)

func _launch():
	if phase != Phase.AIMING:
		return

	phase = Phase.FLYING
	_was_charging = false

	# Restore UFO physics for flight
	freeze = false
	gravity_scale = flight_gravity_scale
	linear_damp = flight_linear_damp

	var force = max(min_launch_force, current_charge)
	var angle_rad = deg_to_rad(arrow_angle_deg)
	apply_central_impulse(Vector2(cos(angle_rad), sin(angle_rad)) * force)

	flight_timer = flight_duration

	# Pass-through window: only activates when charge meets the threshold
	var charge_fraction = current_charge / max_launch_force
	if pass_through_duration > 0.0 and charge_fraction >= pass_through_min_charge_fraction:
		_normal_collision_mask = collision_mask
		collision_mask = 0
		if _damage_area:
			_damage_area.monitoring = false
		_pass_through_timer = pass_through_duration

func _burst():
	if phase == Phase.BURSTING:
		return
	phase = Phase.BURSTING

	_spawn_burst_effect()
	_exit_ufo_and_free()
	emit_signal("ufo_burst")

func _exit_ufo_and_free():
	if is_instance_valid(turtle_player):
		var restore_pos = global_position

		var sprite = turtle_player.get_node_or_null("AnimatedSprite2D")
		if sprite:
			sprite.visible = true
			sprite.scale = Vector2.ONE

		turtle_player.control_suspended = false
		turtle_player.control_suspend_timer = 0.0

		if turtle_player is RigidBody2D:
			turtle_player.freeze = false
			turtle_player.global_position = restore_pos

		turtle_player = null

	queue_free()

func _on_body_entered(body: Node):
	if phase != Phase.FLYING:
		return
	if burst_on_wall_contact and (body.is_in_group("walls") or body is StaticBody2D):
		_burst()

func _on_damage_area_entered(body: Node2D):
	if phase != Phase.FLYING:
		return
	if not body.is_in_group("enemies"):
		return
	if body in _hit_enemies:
		return  # Still on hit cooldown

	if body.has_method("take_damage"):
		body.take_damage(enemy_damage)
	if body is RigidBody2D:
		var dir = (body.global_position - global_position).normalized()
		body.apply_central_impulse(dir * enemy_knockback)

	_hit_enemies[body] = enemy_hit_cooldown

	if burst_on_enemy_contact:
		_burst()

# ──────────────────────────────────────────────────────────────────────────────
# PROCEDURAL DRAWING
# ──────────────────────────────────────────────────────────────────────────────

func _draw():
	var bob_y = sin(bob_offset) * 3.0 if phase == Phase.SINKING else 0.0
	var center = Vector2(0.0, bob_y)

	_draw_ufo_body(center)

	match phase:
		Phase.AIMING:  _draw_aiming_arrow(center)
		Phase.FLYING:  _draw_flight_glow(center)

func _draw_ufo_body(center: Vector2):
	var r = ufo_radius

	# Outer soft glow ring
	_draw_ellipse(center, Vector2(r + 9.0, (r + 9.0) * 0.38),
		Color(glow_color.r, glow_color.g, glow_color.b, 0.18))

	# Main disc body
	_draw_ellipse(center, Vector2(r, r * 0.36), ufo_color)

	# Darker rim band
	_draw_ellipse(center, Vector2(r * 0.88, r * 0.28), ufo_rim_color)

	# Translucent dome (upper half)
	var dome_pts: PackedVector2Array = []
	var dome_rx = r * 0.56
	var dome_ry = r * 0.52
	for i in range(14):
		var a = PI + (i / 13.0) * PI
		dome_pts.append(center + Vector2(cos(a) * dome_rx, sin(a) * dome_ry))
	if dome_pts.size() >= 3:
		draw_colored_polygon(dome_pts, dome_color)

	# Rim running lights (6 colored dots)
	var light_colors: Array[Color] = [
		Color.RED, Color(1, 0.8, 0), Color.GREEN,
		Color.CYAN, Color.RED, Color(1, 0.8, 0)
	]
	for i in range(6):
		var a = (i / 6.0) * TAU
		var lp = center + Vector2(cos(a) * r * 0.74, sin(a) * r * 0.31)
		draw_circle(lp, 2.5, light_colors[i])

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segs: int = 24):
	var pts: PackedVector2Array = []
	for i in range(segs):
		var a = (i / float(segs)) * TAU
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)

func _draw_aiming_arrow(center: Vector2):
	var charge_t = current_charge / max_launch_force
	var arrow_col = arrow_idle_color.lerp(arrow_charging_color, charge_t)
	var angle_rad = deg_to_rad(arrow_angle_deg)
	var dir = Vector2(cos(angle_rad), sin(angle_rad))

	# Shaft length grows slightly with charge
	var shaft_len = arrow_length + charge_t * 22.0
	var shaft_start = center + dir * (ufo_radius + 5.0)
	var tip = center + dir * shaft_len

	draw_line(shaft_start, tip, arrow_col, 3.0, true)

	# Arrowhead triangle
	var perp = Vector2(-dir.y, dir.x)
	var head = 8.0 + charge_t * 5.0
	var arrowhead = PackedVector2Array([
		tip,
		tip - dir * head + perp * (head * 0.5),
		tip - dir * head - perp * (head * 0.5),
	])
	draw_colored_polygon(arrowhead, arrow_col)

	# Charge arc drawn around the UFO rim
	if charge_t > 0.01:
		var arc_col = Color(arrow_col.r, arrow_col.g, arrow_col.b, 0.75)
		draw_arc(center, ufo_radius + 3.0,
			angle_rad - charge_t * PI, angle_rad + charge_t * PI,
			24, arc_col, 3.5, true)

	# "HOLD A" hint label while uncharged and not yet charging
	if current_charge < 10.0 and not _was_charging:
		draw_string(ThemeDB.fallback_font, center + Vector2(-22, -ufo_radius - 18),
			"Hold A", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))

func _draw_flight_glow(center: Vector2):
	var t = fmod(Time.get_ticks_msec() * 0.003, TAU)
	var pulse = sin(t) * 0.5 + 0.5

	if _pass_through_timer > 0.0:
		# Ghost flicker during pass-through window
		var flicker = sin(Time.get_ticks_msec() * 0.025) * 0.5 + 0.5
		modulate = Color(1.0, 1.0, 1.0, 0.35 + flicker * 0.35)
	else:
		modulate = Color.WHITE

	var glow_r = ufo_radius + 12.0 + pulse * 7.0
	draw_circle(center, glow_r,
		Color(ufo_color.r, ufo_color.g, ufo_color.b, 0.18 + pulse * 0.12))

# ──────────────────────────────────────────────────────────────────────────────
# BURST VISUAL EFFECT
# ──────────────────────────────────────────────────────────────────────────────

func _spawn_burst_effect():
	var parent = get_parent()
	if not parent:
		return

	var origin = global_position

	# Expanding shockwave ring
	var ring = _make_ring_node(origin, ufo_color)
	parent.add_child(ring)

	# Spark particles
	for i in range(18):
		var spark = ColorRect.new()
		spark.size = Vector2(randf_range(3, 6), randf_range(3, 6))
		spark.color = burst_colors[randi() % burst_colors.size()]
		spark.z_index = 25
		parent.add_child(spark)
		spark.global_position = origin + Vector2(randf_range(-5, 5), randf_range(-5, 5))

		var dir = Vector2.from_angle((i / 18.0) * TAU + randf_range(-0.2, 0.2))
		var dist = randf_range(45, 130)
		var dur = randf_range(0.4, 0.7)

		var tw = spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "global_position", origin + dir * dist, dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spark, "modulate:a", 0.0, dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(spark.queue_free).set_delay(dur)

func _make_ring_node(origin: Vector2, color: Color) -> Node2D:
	var ring = _RingNode.new()
	ring.ring_color = color
	ring.global_position = origin
	ring.z_index = 24
	return ring

# Inline helper class — self-animating expanding ring
class _RingNode extends Node2D:
	var radius: float = 5.0
	var ring_color: Color = Color.CYAN

	func _ready():
		z_as_relative = false
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "radius", 90.0, 0.55)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 0.0, 0.55)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free).set_delay(0.56)

	func _process(_d):
		queue_redraw()

	func _draw():
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ring_color, 4.0, true)
