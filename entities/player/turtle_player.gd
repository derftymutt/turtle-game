extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30.0
@export var max_velocity: float = 2500.0
@export var kick_animation_duration: float = 0.25

# Shooting properties
@export var shoot_cooldown: float = 0.3
@export var bullet_speed: float = 500.0
@export var bullet_scene: PackedScene

# Thrust strengths
@export var horizontal_thrust: float = 175.0
@export var upward_thrust: float = 75.0
@export var downward_thrust: float = 200.0

# Health
@export var max_health: float = 100.0
var current_health: float = 100.0

# Super Speed System
@export_group("Super Speed")
@export var super_speed_threshold: float = 300.0  # Velocity needed to activate
@export var super_speed_damage: float = 100.0  # Damage dealt to enemies
@export var super_speed_color: Color = Color(1.0, 0.8, 0.0, 1.0)  # Yellow/gold tint
@export var super_speed_cooldown_duration: float = 0.5  # Invincibility extends this long after speed drops
var is_super_speed: bool = false
var is_super_speed_cooldown: bool = false  # True during cooldown period
var super_speed_cooldown_timer: float = 0.0
var super_speed_trail_timer: float = 0.0
var super_speed_trail_interval: float = 0.01  # Spawn trail every 0.01 seconds

# Internal state
var can_thrust: bool = true
var can_shoot: bool = true
var thrust_timer: float = 0.0
var shoot_timer: float = 0.0

# Ocean reference
var ocean: Ocean = null

# HUD reference
var hud: HUD = null

# Wall contact tracking for exhaustion bonus
var touching_walls: Array = []

# Super speed damage detection
var super_speed_area: Area2D = null

# Rotation control
var is_player_controlling_rotation: bool = false

func _ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 1.5
	angular_damp = 3.0
	mass = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# CRITICAL: Enable contact monitoring for body_entered/exited signals!
	# Without this, collision signals won't fire even though physics collisions work
	contact_monitor = true
	max_contacts_reported = 4  # Track up to 4 simultaneous contacts
	
	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 1 (player/world)
	# - Collision Mask: 1 + 3 (world + enemies)
	
	# Find the ocean
	ocean = get_tree().get_first_node_in_group("ocean")
	if not ocean:
		push_warning("No Ocean found! Add Ocean scene to level and add it to 'ocean' group.")
		gravity_scale = 0.1
	
	# Find the HUD
	hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		push_warning("No HUD found! Add HUD scene to level and add it to 'hud' group.")
	else:
		# Initialize HUD with current health
		hud.update_health(current_health, max_health)
	
	add_to_group("player")
	
	# Create Area2D for super speed enemy detection (doesn't cause physics collision)
	_setup_super_speed_area()
	
	# Connect collision signals for wall contact detection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

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
	
	# Check super speed state
	var current_speed = linear_velocity.length()
	var was_super_speed = is_super_speed
	var was_in_cooldown = is_super_speed_cooldown
	
	# Active super speed requires high velocity
	is_super_speed = current_speed >= super_speed_threshold
	
	# Handle cooldown timer
	if is_super_speed_cooldown:
		super_speed_cooldown_timer -= delta
		if super_speed_cooldown_timer <= 0:
			is_super_speed_cooldown = false
	
	# Super speed visual feedback
	if is_super_speed:
		_apply_super_speed_visuals(delta)
		
		# State change - just entered super speed
		if not was_super_speed:
			_create_super_speed_burst()  # Big visual pop!
	elif is_super_speed_cooldown:
		# During cooldown - keep visuals but with pulsing effect to show it's ending
		_apply_cooldown_visuals(delta)
	else:
		_remove_super_speed_visuals()
	
	# Transition from active super speed to cooldown
	if was_super_speed and not is_super_speed and not is_super_speed_cooldown:
		# Just dropped below threshold - start cooldown
		is_super_speed_cooldown = true
		super_speed_cooldown_timer = super_speed_cooldown_duration
	
	# Apply ocean physics
	if ocean:
		apply_ocean_effects(delta)
	else:
		linear_velocity *= 0.98
	
	# Only snap sprite when player is NOT actively controlling it
	if not is_player_controlling_rotation:
		_snap_sprite_to_cardinal()
	
	# Update HUD systems
	if hud:
		var depth = ocean.get_depth(global_position) if ocean else 0.0
		var is_underwater = depth > 0
		
		# Breath system
		if is_underwater:
			var out_of_breath = hud.drain_breath(delta)
			if out_of_breath:
				# Take drowning damage
				take_damage(10.0 * delta)
		else:
			hud.refill_breath(delta)
		
		# Exhaustion recovery (bonus if touching wall)
		hud.recover_exhaustion(delta, touching_walls.size() > 0)
	
	# Get input
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	
	var shoot_input = Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)
	
	# Handle movement (check exhaustion)
	var can_actually_thrust = can_thrust
	if hud and movement_input.length() > 0.1:
		can_actually_thrust = can_actually_thrust and hud.can_thrust()
	
	if movement_input.length() > 0.1 and can_actually_thrust:
		apply_thrust(movement_input.normalized())
	
	# Handle shooting
	if shoot_input.length() > 0.1 and can_shoot:
		shoot(shoot_input.normalized())
	
	# Clamp velocity
	if linear_velocity.length() > max_velocity:
		linear_velocity = linear_velocity.normalized() * max_velocity
	
	# Return to idle when slow
	if can_thrust and linear_velocity.length() < 50:
		var animated_sprite = $AnimatedSprite2D
		if animated_sprite and animated_sprite.animation != "idle" and animated_sprite.animation != "shoot":
			animated_sprite.play("idle")

func apply_ocean_effects(delta: float):
	"""Apply depth-based buoyancy and water drag"""
	var depth = ocean.get_depth(global_position)
	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
	apply_central_force(Vector2(0, -buoyancy_force))
	
	if depth > 0:
		# Underwater - apply water drag
		linear_velocity *= ocean.water_drag
		
		# DEPTH-BASED LINEAR DAMP: Less drag near surface = faster rise
		# Deep water (100+): full drag (2.0) - maintains flipper momentum
		# Shallow water (0-50): reduced drag (1.0) - snappy surface movement
		var depth_factor = clamp(depth / 100.0, 0.0, 1.0)
		var dynamic_damp = lerp(1.0, 2.0, depth_factor)
		linear_damp = dynamic_damp
	else:
		# In air - apply air drag
		linear_velocity *= ocean.air_drag
		linear_damp = 1.2  # Light drag in air

func return_to_idle_after_delay():
	await get_tree().create_timer(kick_animation_duration).timeout
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play("idle")

func apply_thrust(direction: Vector2):
	var kick_direction = -direction if GameSettings.thrust_inverted else direction
	
	# Cancel upward thrust in air
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0:
		return
	
	# Consume exhaustion if HUD system is active
	if hud and not hud.try_thrust():
		# Too exhausted! Don't thrust
		return
	
	# Set flag to prevent cardinal snapping from overwriting
	is_player_controlling_rotation = true
	
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		var angle = direction.angle() + deg_to_rad(-90 if GameSettings.thrust_inverted else 90)
		# Snap to nearest 45° increment for pixel-perfect rotation
		var angle_deg = rad_to_deg(angle)
		var snapped_deg = round(angle_deg / 45.0) * 45.0
		
		animated_sprite.global_rotation = deg_to_rad(snapped_deg)
		animated_sprite.play("kick")
	
	# Determine thrust strength based on direction
	var thrust_strength = horizontal_thrust
	if kick_direction.y < 0:
		thrust_strength = upward_thrust
	elif kick_direction.y > 0:
		thrust_strength = downward_thrust
	
	# Apply thrust
	linear_velocity += kick_direction * thrust_strength
	
	# Start cooldown
	can_thrust = false
	thrust_timer = kick_animation_duration

func shoot(direction: Vector2):
	if bullet_scene == null:
		push_warning("No bullet scene assigned!")
		return
	
	# Set flag to prevent cardinal snapping from overwriting
	is_player_controlling_rotation = true
	
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		var angle = direction.angle() + deg_to_rad(90)
		
		# Snap to nearest 45° increment for pixel-perfect rotation
		var angle_deg = rad_to_deg(angle)
		var snapped_deg = round(angle_deg / 45.0) * 45.0
		
		animated_sprite.global_rotation = deg_to_rad(snapped_deg)
		animated_sprite.play("shoot")
		return_to_idle_after_delay()
	
	# Spawn bullet
	var bullet = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	# Spawn MUCH closer - just outside turtle's collision radius (12 pixels + bullet radius ~5 = 17)
	bullet.global_position = global_position + direction * 15
	
	# Set bullet velocity
	bullet.set_velocity(direction * bullet_speed)
	
	# Start cooldown
	can_shoot = false
	shoot_timer = shoot_cooldown

func apply_flipper_force(direction: Vector2, force_multiplier: float = 5.0):
	"""Apply strong pinball-like forces from flippers"""
	apply_central_impulse(direction * thrust_force * force_multiplier)

func take_damage(amount: float):
	# Invincible during super speed AND during cooldown!
	if is_super_speed or is_super_speed_cooldown:
		return
	
	current_health -= amount
	
	# Update HUD
	if hud:
		hud.update_health(current_health, max_health)
	
	# Flash red
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = Color.RED
		await get_tree().create_timer(0.1).timeout
		if sprite and is_instance_valid(sprite):
			sprite.modulate = Color.WHITE
	
	if current_health <= 0:
		die()

func die():
	# Get the HUD's current score
	var final_score = 0
	if hud:
		final_score = hud.current_score
	
	# Update GameManager score
	GameManager.current_score = final_score
	
	# Find level base (parent scene) and notify it
	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("on_player_died"):
		level.on_player_died(final_score)
	else:
		# Fallback: show game over screen directly
		var game_over_screen = get_tree().get_first_node_in_group("game_over_screen")
		if game_over_screen and game_over_screen.has_method("show_game_over"):
			game_over_screen.show_game_over(final_score, GameManager.current_level)
		else:
			push_warning("No GameOverScreen found!")
			await get_tree().create_timer(2.0).timeout
			get_tree().reload_current_scene()

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

func _setup_super_speed_area():
	"""Create an Area2D for detecting enemies during super speed without physics collision"""
	super_speed_area = Area2D.new()
	super_speed_area.name = "SuperSpeedArea"
	
	# Collision setup - detect enemies on layer 3
	super_speed_area.collision_layer = 0  # Not on any layer
	super_speed_area.collision_mask = 4  # Detect layer 3 (enemies)
	
	# Create collision shape matching turtle size
	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 12.0  # Slightly bigger than turtle for better detection
	collision_shape.shape = circle
	
	super_speed_area.add_child(collision_shape)
	add_child(super_speed_area)
	
	# Connect signal
	super_speed_area.body_entered.connect(_on_super_speed_area_entered)

func _on_super_speed_area_entered(body: Node2D):
	"""Detect enemies entering super speed range"""
	# Damage enemies during active super speed (not cooldown)
	if not is_super_speed:
		return
	
	# Check if it's an enemy
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(super_speed_damage)
		
		# Bounce effect
		var bounce_direction = (global_position - body.global_position).normalized()
		apply_central_impulse(bounce_direction * 100)

func _apply_super_speed_visuals(delta: float):
	"""Apply glowing effect and spawn motion trail"""
	var sprite = $AnimatedSprite2D
	if sprite:
		# BRIGHT golden glow effect - much more saturated
		sprite.modulate = Color(2.0, 1.5, 0.0, 1.0)  # Overbright yellow!
		
		# BIGGER pulse effect
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.4  # Bigger range
		sprite.scale = Vector2.ONE * pulse
	
	# Spawn motion trail MORE FREQUENTLY
	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		_spawn_motion_trail(1.0)  # Full intensity during active super speed

func _apply_cooldown_visuals(delta: float):
	"""Apply fading glow effect during cooldown period"""
	var sprite = $AnimatedSprite2D
	if sprite:
		# Calculate fade factor (1.0 at start of cooldown, 0.0 at end)
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		
		# Smoothly transition from bright gold to normal white
		var cooldown_color = Color(2.0, 1.5, 0.0, 1.0).lerp(Color.WHITE, 1.0 - fade_factor)
		sprite.modulate = cooldown_color
		
		# Smooth pulse that gradually reduces in intensity
		var pulse_intensity = 0.2 * fade_factor  # Starts at 0.2, fades to 0
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.02) * pulse_intensity
		sprite.scale = Vector2.ONE * pulse
	
	# Keep spawning trails at same rate for smooth visual continuity
	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		_spawn_motion_trail(fade_factor)  # Pass fade_factor for dimmer trails

func _remove_super_speed_visuals():
	"""Remove super speed visual effects"""
	var sprite = $AnimatedSprite2D
	if sprite and is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE

func _spawn_motion_trail(intensity: float = 1.0):
	"""Create a fading afterimage trail effect"""
	var sprite = $AnimatedSprite2D
	if not sprite:
		return
	
	# Create a Sprite2D that matches our current appearance
	var trail = Sprite2D.new()
	trail.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	trail.global_position = global_position
	trail.global_rotation = sprite.global_rotation
	trail.scale = sprite.scale * 1.2  # Slightly bigger!
	
	# Color intensity fades during cooldown
	var trail_color = Color(2.0, 1.5, 0.0, 0.8 * intensity)
	trail.modulate = trail_color
	trail.z_index = 10  # High z_index to appear above ocean layer!
	
	# Add to scene
	get_parent().add_child(trail)
	
	# Fade out - duration scales with intensity for smooth transition
	var fade_duration = 0.5 * intensity
	if fade_duration < 0.2:
		fade_duration = 0.2  # Minimum fade duration
	
	var tween = create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(trail.queue_free)

func _create_super_speed_burst():
	"""Create a big visual burst when entering super speed"""
	# Create expanding ring effect
	for i in range(8):
		var burst_sprite = Sprite2D.new()
		var sprite = $AnimatedSprite2D
		if sprite:
			burst_sprite.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		
		burst_sprite.global_position = global_position
		burst_sprite.rotation = randf() * TAU
		burst_sprite.modulate = Color(2.0, 1.5, 0.0, 0.9)
		burst_sprite.z_index = 10  # High z_index to appear above ocean!
		
		get_parent().add_child(burst_sprite)
		
		# Animate outward and fade
		var tween = create_tween()
		tween.set_parallel(true)
		
		var direction = Vector2(cos(i * TAU / 8), sin(i * TAU / 8))
		tween.tween_property(burst_sprite, "global_position", global_position + direction * 50, 0.4)
		tween.tween_property(burst_sprite, "scale", Vector2.ONE * 2.0, 0.4)
		tween.tween_property(burst_sprite, "modulate:a", 0.0, 0.4)
		tween.tween_callback(burst_sprite.queue_free)

func _snap_sprite_to_cardinal():
	"""Snap sprite rotation to nearest 45° while body rotates freely"""
	var animated_sprite = $AnimatedSprite2D
	if not animated_sprite:
		return
	
	# Get the body's current physics rotation
	var body_rotation_deg = rad_to_deg(rotation)
	
	# Snap to nearest 45°
	var snapped_deg = round(body_rotation_deg / 45.0) * 45.0
	var snapped_rotation_rad = deg_to_rad(snapped_deg)
	
	# Set sprite's LOCAL rotation to compensate for body's rotation
	animated_sprite.rotation = snapped_rotation_rad - rotation
