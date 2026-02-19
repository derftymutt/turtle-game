extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30.0
@export var max_velocity: float = 2500.0
@export var kick_animation_duration: float = 0.25
@export var kick_animation_duration_with_ufo_piece: float = 0.5

# Shooting properties
@export var shoot_cooldown: float = 0.2
@export var bullet_speed: float = 500.0
@export var bullet_scene: PackedScene

# Thrust strengths
@export var horizontal_thrust: float = 175.0
@export var upward_thrust: float = 75.0
@export var downward_thrust: float = 225.0

@export var horizontal_thrust_with_piece: float = 75.0
@export var upward_thrust_with_piece: float = 25.0
@export var downward_thrust_with_piece: float = 125.0

# Health
@export var max_health: float = 100.0
var current_health: float = 100.0

# Super Speed System
@export_group("Super Speed")
@export var super_speed_threshold: float = 300.0  # Velocity needed to activate
@export var super_speed_damage: float = 100.0     # Damage dealt to enemies
# Single source of truth for all super speed visuals (glow, trail, burst).
# Values above 1.0 are intentional — they push into HDR/bloom territory.
@export var super_speed_color: Color = Color(0.778, 1.504, 0.0)
@export var super_speed_cooldown_duration: float = 0.5
var is_super_speed: bool = false
var is_super_speed_cooldown: bool = false
var super_speed_cooldown_timer: float = 0.0
var super_speed_trail_timer: float = 0.0
var super_speed_trail_interval: float = 0.01

# Internal state
var can_thrust: bool = true
var can_shoot: bool = true
var thrust_timer: float = 0.0
var shoot_timer: float = 0.0
var current_kick_animation_duration: float = kick_animation_duration
# Guards against multiple simultaneous damage flashes fighting over modulate.
# Drowning calls take_damage() every frame; without this, hundreds of competing
# awaits all write Color.RED before any of them can write Color.WHITE back.
var _is_flashing: bool = false

# Ocean reference
var ocean: Ocean = null

# HUD reference
var hud: HUD = null

# Wall contact tracking for exhaustion bonus
var touching_walls: Array = []

# Super speed damage detection
var super_speed_area: Area2D = null

# Powerup states
var shield_active: bool = false
var shield_duration: float = 8.0
var shield_timer: float = 0.0

var air_reserve_bonus: float = 20.0

var stamina_freeze_active: bool = false
var stamina_freeze_duration: float = 20.0
var stamina_freeze_timer: float = 0.0

var is_player_controlling_rotation: bool = false

var control_suspended: bool = false
var control_suspend_timer: float = 0.0

# ---------------------------------------------------------------------------
# 8-DIRECTIONAL SPRITE SYSTEM
# ---------------------------------------------------------------------------
# Maps angle buckets to animation name suffixes.
# Godot's Vector2.angle() returns 0 at East, increasing clockwise.
# We offset by 22.5 degrees so each direction owns an equal +/-22.5 degree zone.
#
#   Index:  0    1     2    3     4    5     6    7
#   Dir:    e    se    s    sw    w    nw    n    ne
#   Angle:  0    45    90   135   180  225   270  315
#
const DIRECTION_SUFFIXES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

# The direction the turtle is currently facing. Persists between actions so
# idle always shows the correct facing direction after a kick or shoot.
var facing_direction: String = "s"  # Default: face downward into the water

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready():
	gravity_scale = 0.0
	linear_damp = 1.5
	angular_damp = 3.0
	mass = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	# CRITICAL: Enable contact monitoring for body_entered/exited signals.
	# Without this, collision signals won't fire even though physics works.
	contact_monitor = true
	max_contacts_reported = 4

	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 1 (player/world)
	# - Collision Mask: 1 + 3 (world + enemies)

	ocean = get_tree().get_first_node_in_group("ocean")
	if not ocean:
		push_warning("No Ocean found! Add Ocean scene to level and add it to 'ocean' group.")
		gravity_scale = 0.1

	hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		push_warning("No HUD found! Add HUD scene to level and add it to 'hud' group.")
	else:
		hud.update_health(current_health, max_health)

	add_to_group("player")

	_setup_super_speed_area()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Show the correct idle frame immediately on spawn
	_play_animation("idle")

# ---------------------------------------------------------------------------
# PHYSICS PROCESS
# ---------------------------------------------------------------------------

func _physics_process(delta):
	# Update cooldown timers
	if not can_thrust:
		thrust_timer -= delta
		if thrust_timer <= 0:
			can_thrust = true
			is_player_controlling_rotation = false

	if not can_shoot:
		shoot_timer -= delta
		if shoot_timer <= 0:
			can_shoot = true
			is_player_controlling_rotation = false

	# Super speed state
	var current_speed = linear_velocity.length()
	var was_super_speed = is_super_speed
	is_super_speed = current_speed >= super_speed_threshold

	if is_super_speed_cooldown:
		super_speed_cooldown_timer -= delta
		if super_speed_cooldown_timer <= 0:
			is_super_speed_cooldown = false

	if is_super_speed:
		_apply_super_speed_visuals(delta)
		if not was_super_speed:
			_create_super_speed_burst()
	elif is_super_speed_cooldown:
		_apply_cooldown_visuals(delta)
	else:
		_remove_super_speed_visuals()

	if was_super_speed and not is_super_speed and not is_super_speed_cooldown:
		is_super_speed_cooldown = true
		super_speed_cooldown_timer = super_speed_cooldown_duration

	# Powerup timers
	if shield_active:
		shield_timer -= delta
		if shield_timer <= 0:
			deactivate_shield()

	if stamina_freeze_active:
		stamina_freeze_timer -= delta
		if stamina_freeze_timer <= 0:
			deactivate_stamina_freeze()

	# Ocean physics
	if ocean:
		apply_ocean_effects(delta)
	else:
		linear_velocity *= 0.98

	# Counter-rotate the sprite to cancel the physics body's rotation every frame.
	# The body can spin freely (correct flipper/bumper physics) but the sprite
	# always appears axis-aligned and pixel-perfect.
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.rotation = -rotation

	# HUD systems
	if hud:
		var depth = ocean.get_depth(global_position) if ocean else 0.0
		var is_underwater = depth > 3

		if is_underwater:
			var out_of_breath = hud.drain_breath(delta)
			if out_of_breath:
				take_damage(10.0 * delta)
		else:
			hud.refill_breath(delta)

		hud.recover_exhaustion(delta, touching_walls.size() > 0)

	# Control suspension timer — runs even while suspended so it keeps counting down
	control_suspend_timer -= delta
	if control_suspend_timer <= 0 and control_suspended:
		control_suspended = false
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.modulate = Color.WHITE
			animated_sprite.scale = Vector2.ONE

	if control_suspended:
		return

	# Input
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	var shoot_input = Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)

	# Movement — check exhaustion unless stamina freeze is active
	var can_actually_thrust = can_thrust
	if hud and movement_input.length() > 0.1 and not stamina_freeze_active:
		can_actually_thrust = can_actually_thrust and hud.can_thrust()

	if movement_input.length() > 0.1 and can_actually_thrust:
		apply_thrust(movement_input.normalized())

	if shoot_input.length() > 0.1 and can_shoot:
		shoot(shoot_input.normalized())

	# Clamp velocity
	if linear_velocity.length() > max_velocity:
		linear_velocity = linear_velocity.normalized() * max_velocity

	# Return to directional idle when nearly stopped and no action is running
	if can_thrust and linear_velocity.length() < 50:
		var target_idle = "idle_" + facing_direction
		if animated_sprite and animated_sprite.animation != target_idle:
			animated_sprite.play(target_idle)

# ---------------------------------------------------------------------------
# OCEAN
# ---------------------------------------------------------------------------

func apply_ocean_effects(delta: float):
	"""Apply depth-based buoyancy and water drag"""
	var depth = ocean.get_depth(global_position)
	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
	apply_central_force(Vector2(0, -buoyancy_force))

	if depth > 0:
		linear_velocity *= ocean.water_drag
		var depth_factor = clamp(depth / 100.0, 0.0, 1.0)
		linear_damp = lerp(1.0, 2.0, depth_factor)
	else:
		linear_velocity *= ocean.air_drag
		linear_damp = 1.2

# ---------------------------------------------------------------------------
# MOVEMENT & SHOOTING
# ---------------------------------------------------------------------------

func return_to_idle_after_delay():
	await get_tree().create_timer(current_kick_animation_duration).timeout
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play("idle_" + facing_direction)

func apply_thrust(direction: Vector2):
	var kick_direction = -direction if GameSettings.thrust_inverted else direction

	# No upward thrust in air
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0:
		return

	if hud and not stamina_freeze_active and not hud.try_thrust():
		return

	is_player_controlling_rotation = true

	# Update facing direction using kick_direction so thrust_inverted is accounted for
	facing_direction = _vector_to_direction_suffix(kick_direction)

	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play("kick_" + facing_direction)

	# Thrust strength
	var thrust_strength: float
	if GameManager.is_carrying_piece and GameManager.carried_piece:
		thrust_strength = horizontal_thrust_with_piece
		if kick_direction.y < 0:
			thrust_strength = upward_thrust_with_piece
		elif kick_direction.y > 0:
			thrust_strength = downward_thrust_with_piece
	else:
		thrust_strength = horizontal_thrust
		if kick_direction.y < 0:
			thrust_strength = upward_thrust
		elif kick_direction.y > 0:
			thrust_strength = downward_thrust

	linear_velocity += kick_direction * thrust_strength

	can_thrust = false
	thrust_timer = current_kick_animation_duration

func shoot(direction: Vector2):
	if bullet_scene == null:
		push_warning("No bullet scene assigned!")
		return

	is_player_controlling_rotation = true

	# Update facing so idle returns to the correct pose afterward
	facing_direction = _vector_to_direction_suffix(direction)

	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play("shoot_" + facing_direction)
		return_to_idle_after_delay()

	var bullet = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = global_position + direction * 15
	bullet.set_velocity(direction * bullet_speed)

	can_shoot = false
	shoot_timer = shoot_cooldown

func apply_flipper_force(direction: Vector2, force_multiplier: float = 5.0):
	"""Apply strong pinball-like forces from flippers"""
	apply_central_impulse(direction * thrust_force * force_multiplier)

# ---------------------------------------------------------------------------
# HEALTH
# ---------------------------------------------------------------------------

func take_damage(amount: float):
	if is_super_speed or is_super_speed_cooldown or shield_active:
		return

	current_health -= amount

	if hud:
		hud.update_health(current_health, max_health)

	# Drop piece and check death BEFORE any await — these must fire immediately
	# and must not be triggered multiple times from repeated per-frame damage.
	if GameManager.is_carrying_piece and GameManager.carried_piece:
		GameManager.carried_piece.drop_piece()

	if current_health <= 0:
		die()
		return  # die() handles everything from here

	# Flash red — guarded so drowning damage (called every frame via delta)
	# doesn't spawn hundreds of competing awaits that fight over modulate.
	#if not _is_flashing:
		#_is_flashing = true
		#var sprite = $AnimatedSprite2D
		#if sprite:
			#sprite.modulate = Color.RED
			#await get_tree().create_timer(0.15).timeout
			#if sprite and is_instance_valid(sprite):
				#sprite.modulate = Color.WHITE
		#_is_flashing = false
		
		# take_damage — replace the entire if not _is_flashing block with:
	_flash(Color.RED, 0.3)

func restore_health(amount: float):
	"""Restore health (e.g., from health plants)"""
	current_health = min(max_health, current_health + amount)

	if hud:
		hud.update_health(current_health, max_health)

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = Color.GREEN
		await get_tree().create_timer(0.2).timeout
		if sprite and is_instance_valid(sprite):
			sprite.modulate = Color.WHITE

	print("Health restored! Current: ", current_health, "/", max_health)

func die():
	var final_score = 0
	if hud:
		final_score = hud.current_score

	GameManager.current_score = final_score

	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("on_player_died"):
		level.on_player_died(final_score)
	else:
		var game_over_screen = get_tree().get_first_node_in_group("game_over_screen")
		if game_over_screen and game_over_screen.has_method("show_game_over"):
			game_over_screen.show_game_over(final_score, GameManager.current_level)
		else:
			push_warning("No GameOverScreen found!")
			await get_tree().create_timer(2.0).timeout
			get_tree().reload_current_scene()

# ---------------------------------------------------------------------------
# COLLISION TRACKING
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node):
	"""Track walls for exhaustion recovery bonus"""
	if body.is_in_group("walls") or body is StaticBody2D:
		if not body in touching_walls:
			touching_walls.append(body)

func _on_body_exited(body: Node):
	"""Stop tracking walls when we leave them"""
	if body in touching_walls:
		touching_walls.erase(body)

func add_score(points: int):
	"""Called by collectibles when picked up"""
	if hud:
		hud.add_score(points)

# ---------------------------------------------------------------------------
# DIRECTION HELPERS
# ---------------------------------------------------------------------------

func _vector_to_direction_suffix(direction: Vector2) -> String:
	# Vector2.angle() returns radians: 0 = East, increasing clockwise.
	# Convert to 0-360 degrees then offset by 22.5 so each 45-degree bucket
	# is perfectly centred on its cardinal or diagonal direction.
	var angle_deg = rad_to_deg(direction.angle())
	angle_deg = fmod(angle_deg + 360.0 + 22.5, 360.0)
	var index = int(angle_deg / 45.0) % 8
	return DIRECTION_SUFFIXES[index]

func _play_animation(anim_type: String):
	"""Play a directional animation using the current facing_direction.
	   anim_type should be 'idle', 'kick', or 'shoot'."""
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play(anim_type + "_" + facing_direction)

# ---------------------------------------------------------------------------
# SUPER SPEED AREA
# ---------------------------------------------------------------------------

func _setup_super_speed_area():
	"""Create an Area2D for detecting enemies during super speed without physics collision"""
	super_speed_area = Area2D.new()
	super_speed_area.name = "SuperSpeedArea"

	# NOTE: Set programmatically only because this node is created at runtime.
	# All other collision layers are set in the Inspector per project rules.
	super_speed_area.collision_layer = 0
	super_speed_area.collision_mask = 4  # Layer 3 = enemies

	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 12.0
	collision_shape.shape = circle

	super_speed_area.add_child(collision_shape)
	add_child(super_speed_area)

	super_speed_area.body_entered.connect(_on_super_speed_area_entered)

func _on_super_speed_area_entered(body: Node2D):
	if not is_super_speed and not shield_active:
		return

	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(super_speed_damage)
		var bounce_direction = (global_position - body.global_position).normalized()
		apply_central_impulse(bounce_direction * 100)

# ---------------------------------------------------------------------------
# SUPER SPEED VISUALS
# ---------------------------------------------------------------------------

func _apply_super_speed_visuals(delta: float):
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = super_speed_color
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.4
		sprite.scale = Vector2.ONE * pulse

	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		_spawn_motion_trail(1.0)

func _apply_cooldown_visuals(delta: float):
	var sprite = $AnimatedSprite2D
	if sprite:
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		sprite.modulate = super_speed_color.lerp(Color.WHITE, 1.0 - fade_factor)
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.02) * (0.2 * fade_factor)
		sprite.scale = Vector2.ONE * pulse

	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		_spawn_motion_trail(fade_factor)

func _remove_super_speed_visuals():
	var sprite = $AnimatedSprite2D
	if sprite and is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE

func _spawn_motion_trail(intensity: float = 1.0):
	var sprite = $AnimatedSprite2D
	if not sprite:
		return

	var trail = Sprite2D.new()
	trail.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	# Use the sprite's global_position, NOT the body's global_position.
	# The AnimatedSprite2D may have a local offset from the body origin;
	# using the body origin causes trails to appear shifted.
	trail.global_position = sprite.global_position
	trail.global_rotation = sprite.global_rotation
	trail.scale = sprite.scale * 1.2
	var trail_color = super_speed_color
	trail_color.a = 0.8 * intensity
	trail.modulate = trail_color
	trail.z_index = 10

	get_parent().add_child(trail)

	var fade_duration = max(0.2, 0.5 * intensity)
	var tween = create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(trail.queue_free)

func _create_super_speed_burst():
	var sprite = $AnimatedSprite2D
	for i in range(8):
		var burst_sprite = Sprite2D.new()
		if sprite:
			burst_sprite.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)

		burst_sprite.global_position = global_position
		burst_sprite.rotation = randf() * TAU
		var burst_color = super_speed_color
		burst_color.a = 0.9
		burst_sprite.modulate = burst_color
		burst_sprite.z_index = 10

		get_parent().add_child(burst_sprite)

		var tween = create_tween()
		tween.set_parallel(true)
		var burst_dir = Vector2(cos(i * TAU / 8), sin(i * TAU / 8))
		tween.tween_property(burst_sprite, "global_position", global_position + burst_dir * 50, 0.4)
		tween.tween_property(burst_sprite, "scale", Vector2.ONE * 2.0, 0.4)
		tween.tween_property(burst_sprite, "modulate:a", 0.0, 0.4)
		tween.tween_callback(burst_sprite.queue_free)

# ---------------------------------------------------------------------------
# POWERUPS
# ---------------------------------------------------------------------------

func apply_powerup(powerup_type: int):
	print("APPLYING POWERUP TYPE: ", powerup_type)
	match powerup_type:
		0:  activate_shield()
		1:  activate_air_reserve()
		2:  activate_stamina_freeze()
		_:  push_error("Unknown powerup type: ", powerup_type)

func activate_shield():
	shield_active = true
	shield_timer = shield_duration
	print("SHIELD ACTIVATED! Invincible for ", shield_duration, " seconds!")

	var sprite = $AnimatedSprite2D
	if sprite:
		var tween = create_tween().set_loops()
		tween.tween_property(sprite, "modulate", Color(0.3, 0.6, 1.0, 1.0), 0.3)
		tween.tween_property(sprite, "modulate", Color(0.6, 0.9, 1.0, 1.0), 0.3)

func deactivate_shield():
	shield_active = false
	print("Shield expired")
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = Color.WHITE

func activate_air_reserve():
	if hud:
		hud.max_breath += air_reserve_bonus
		hud.current_breath = hud.max_breath
		hud.update_breath(hud.current_breath, hud.max_breath)
		print("AIR RESERVE! +", air_reserve_bonus, " max breath! (new max: ", hud.max_breath, ")")
	else:
		push_error("No HUD found! Can't apply air reserve.")

func activate_stamina_freeze():
	stamina_freeze_active = true
	stamina_freeze_timer = stamina_freeze_duration
	print("STAMINA FREEZE! No exhaustion for ", stamina_freeze_duration, " seconds!")

	if not is_super_speed:
		var sprite = $AnimatedSprite2D
		if sprite:
			var tween = create_tween().set_loops()
			tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 0.4, 1.0), 0.25)
			tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 0.7, 1.0), 0.25)

func deactivate_stamina_freeze():
	stamina_freeze_active = false
	print("Stamina freeze expired")

	if not shield_active and not is_super_speed:
		var sprite = $AnimatedSprite2D
		if sprite:
			sprite.modulate = Color.WHITE
			
func _flash(color: Color, duration: float):
	if _is_flashing:
		return
	_is_flashing = true
	var overlay = $FlashOverlay
	if overlay:
		overlay.modulate.a = 0.9  # Semi-transparent so original sprite shows through
		var tween = create_tween()
		tween.tween_property(overlay, "modulate:a", 0.0, duration)
		await get_tree().create_timer(duration).timeout
	_is_flashing = false

# ---------------------------------------------------------------------------
# CONTROL SUSPENSION
# ---------------------------------------------------------------------------

func suspend_control(duration: float):
	"""Temporarily disable player input (called by electric shock)"""
	control_suspended = true
	control_suspend_timer = duration
	print("Player: Control suspended for ", duration, "s!")
