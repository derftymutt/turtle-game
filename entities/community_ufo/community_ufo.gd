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
## Seconds of peak charge to remember after the yoyo starts falling.
## Compensates for Bluetooth controller input latency (typically 20-100 ms).
## Set to 0 to disable.
@export var windup_peak_hold_window: float = 0.10

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
## Collision layers that pass-through can NEVER bypass (e.g. WorldSafetyBoundaries).
## During pass-through the UFO's collision_mask is reduced to only these bits.
## Default = 0 (pass-through ghosts everything). Set to your safety boundary layer(s).
@export_flags_2d_physics var safety_collision_mask: int;

# ============================================================
# COMBAT — enemy interaction during flight
# ============================================================
@export_group("Combat")
@export var enemy_damage: float = 60.0
@export var enemy_hit_cooldown: float = 0.5    # Prevent spam-hitting same enemy
@export var enemy_knockback: float = 250.0

# ============================================================
# VISUAL
# ============================================================
@export_group("Visual")
## Radius used to position the launch arrow relative to the UFO center
@export var ufo_radius: float = 22.0
@export var arrow_idle_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var arrow_charging_color: Color = Color(1.0, 0.2, 0.0, 1.0)
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
var _peak_charge: float = 0.0       # Highest charge seen in the current hold
var _peak_charge_timer: float = 0.0 # Countdown to forget the peak
var _pass_through_timer: float = 0.0
var _normal_collision_mask: int = 0
var _hit_enemies: Dictionary = {}
var _pickup_area: Area2D = null
var _damage_area: Area2D = null
var _stored_shield: bool = false
## Set to true by the dolphin BEFORE add_child (dolphin carry state tracking).
var being_carried: bool = false
## Reference back to the dolphin that is carrying this UFO (cleared on drop/entry).
var _carrying_dolphin: Node = null
## True for one physics frame after the turtle enters a dolphin-carried UFO.
## Changing freeze during a body_entered signal callback is unreliable — we defer
## the unfreeze + impulse to the next _physics_process() call where it is safe.
var _entering_from_carry: bool = false

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

	# Wire up the Area2D nodes that live in the scene tree (community_ufo.tscn).
	# Do NOT create duplicate nodes in code — Godot would rename them and
	# get_node("PickupArea") would then find the scene node (no signal) instead.
	_pickup_area = $PickupArea
	_pickup_area.monitoring = true   # Always active — turtle can enter even mid-carry
	_pickup_area.body_entered.connect(_on_pickup_area_entered)

	_damage_area = $DamageArea
	_damage_area.body_entered.connect(_on_damage_area_entered)

	body_entered.connect(_on_body_entered)

# ──────────────────────────────────────────────────────────────────────────────
# PUBLIC — called by the dolphin when it drops the UFO
# ──────────────────────────────────────────────────────────────────────────────

## Called by the dolphin when it reaches the drop point normally.
func release_from_carry():
	being_carried = false
	_carrying_dolphin = null

## Called by the dolphin so this UFO knows who is carrying it.
func set_carrying_dolphin(dolphin: Node) -> void:
	_carrying_dolphin = dolphin

# ──────────────────────────────────────────────────────────────────────────────
# PHYSICS PROCESS
# ──────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float):
	# Deferred unfreeze for mid-carry entry.
	# body_entered fires at the end of a physics step, so changing freeze there is
	# unreliable.  We set a flag and do it here at the START of the next tick,
	# where Godot can properly re-initialize the dynamic body and accept impulses.
	if _entering_from_carry:
		_entering_from_carry = false
		freeze = false
		gravity_scale = sink_gravity_scale
		linear_damp   = sink_linear_damp
		linear_velocity   = Vector2.ZERO
		angular_velocity  = 0.0
		apply_central_impulse(Vector2(0.0, 40.0))   # Match the dolphin's normal drop impulse

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

		# Track the charge peak; refresh the hold window whenever we hit a new high.
		if current_charge >= _peak_charge:
			_peak_charge = current_charge
			_peak_charge_timer = windup_peak_hold_window

		# Auto-launch if held too long
		if _windup_hold_timer >= max_windup_hold_time:
			_launch()

	# Decay peak window every tick (so it expires on the down-swing / after release).
	if _peak_charge_timer > 0.0:
		_peak_charge_timer -= delta
		if _peak_charge_timer < 0.0:
			_peak_charge_timer = 0.0

func _input(event: InputEvent):
	# Catch button release at the exact OS event moment rather than waiting
	# for the next physics tick — eliminates up to ~16 ms of charge drift.
	if phase == Phase.AIMING and _was_charging:
		if event.is_action_released(windup_button):
			_launch()
			get_viewport().set_input_as_handled()

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

	# Ghost flicker modulate during pass-through window
	if _pass_through_timer > 0.0:
		var flicker = sin(Time.get_ticks_msec() * 0.025) * 0.5 + 0.5
		modulate = Color(1.0, 1.0, 1.0, 0.35 + flicker * 0.35)
	else:
		modulate = Color.WHITE

	flight_timer -= delta
	if flight_timer <= 0.0:
		_burst()

# ──────────────────────────────────────────────────────────────────────────────
# PHASE TRANSITIONS
# ──────────────────────────────────────────────────────────────────────────────

func _on_pickup_area_entered(body: Node2D):
	if phase != Phase.SINKING:
		return
	if not body.is_in_group("player"):
		return
	_enter_ufo(body)

func _enter_ufo(player: Node2D):
	phase = Phase.AIMING
	turtle_player = player

	# If the dolphin is still carrying us, cleanly detach so it stops
	# dragging the UFO by CarryPoint and accelerates away.
	var was_carried := being_carried
	if being_carried and is_instance_valid(_carrying_dolphin) \
			and _carrying_dolphin.has_method("on_ufo_entered_by_player"):
		_carrying_dolphin.on_ufo_entered_by_player()
	_carrying_dolphin = null
	being_carried = false

	if was_carried:
		# The UFO is currently frozen (freeze=true from dolphin carry code).
		# Changing freeze during a body_entered signal callback is unreliable in Godot 4
		# (the body isn't re-initialized as dynamic until the next physics step).
		# Set a flag — _physics_process will do the real unfreeze + impulse next tick.
		_entering_from_carry = true
	else:
		# Already dynamic (dropped normally by dolphin); just normalise physics state.
		freeze = false
		gravity_scale = sink_gravity_scale
		linear_damp   = sink_linear_damp
		linear_velocity  = Vector2.ZERO
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
	_peak_charge = min_launch_force
	_peak_charge_timer = 0.0
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

	# Clear the sinking velocity accumulated during AIMING so it doesn't bias the shot.
	linear_velocity = Vector2.ZERO

	# Use the best charge seen recently so Bluetooth input lag doesn't penalise the player.
	var effective_charge = max(current_charge, _peak_charge)
	var force = max(min_launch_force, effective_charge)
	# arrow_angle_deg is in LOCAL space (so the drawn arrow rotates with the UFO body).
	# apply_central_impulse() needs a WORLD space direction, so rotate by the node's
	# current world rotation to convert local → world before applying the force.
	var angle_rad = deg_to_rad(arrow_angle_deg)
	var local_dir = Vector2(cos(angle_rad), sin(angle_rad))
	apply_central_impulse(local_dir.rotated(rotation) * force)

	flight_timer = flight_duration

	# Pass-through window: only activates when charge meets the threshold.
	# safety_collision_mask layers are ALWAYS kept — the UFO can never clip through them.
	var charge_fraction = effective_charge / max_launch_force
	if pass_through_duration > 0.0 and charge_fraction >= pass_through_min_charge_fraction:
		_normal_collision_mask = collision_mask
		collision_mask = safety_collision_mask  # Keep safety walls; ghost through everything else
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
	if burst_on_wall_contact:
		# Match dead walls ("walls" group), level tile walls ("levelwalls" group),
		# generic StaticBody2D, and TileMapLayer nodes (Godot 4 tile physics).
		var is_wall = body.is_in_group("walls") \
			or body.is_in_group("levelwalls") \
			or body is StaticBody2D \
			or body is TileMapLayer
		if is_wall:
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
# DRAWING — arrow only (UFO body is the AnimatedSprite2D)
# ──────────────────────────────────────────────────────────────────────────────

func _draw():
	if phase == Phase.AIMING:
		_draw_aiming_arrow(Vector2.ZERO)

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

# ──────────────────────────────────────────────────────────────────────────────
# BURST VISUAL EFFECT
# ──────────────────────────────────────────────────────────────────────────────

func _spawn_burst_effect():
	var parent = get_parent()
	if not parent:
		return

	var origin = global_position

	# Expanding shockwave ring
	var ring = _make_ring_node(origin, burst_colors[0])
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
