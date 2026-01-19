extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30000.0
@export var max_velocity: float = 2500.0
@export var kick_animation_duration: float = 0.4

# Shooting properties
@export var shoot_cooldown: float = 0.3
@export var bullet_speed: float = 500.0
@export var bullet_scene: PackedScene

# Thrust strengths
@export var horizontal_thrust: float = 200.0
@export var upward_thrust: float = 75.0
@export var downward_thrust: float = 250.0

# Health
@export var max_health: float = 100.0
var current_health: float = 100.0

# Internal state
var can_thrust: bool = true
var can_shoot: bool = true
var thrust_timer: float = 0.0
var shoot_timer: float = 0.0

# Ocean reference
var ocean: Ocean = null

func _ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 2.0
	angular_damp = 3.0
	mass = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 1 (player/world)
	# - Collision Mask: 1 (only collide with world)
	
	# Find the ocean
	ocean = get_tree().get_first_node_in_group("ocean")
	if not ocean:
		push_warning("No Ocean found! Add Ocean scene to level and add it to 'ocean' group.")
		gravity_scale = 0.1
	
	add_to_group("player")

func _physics_process(delta):
	# Update cooldown timers
	if not can_thrust:
		thrust_timer -= delta
		if thrust_timer <= 0:
			can_thrust = true
	
	if not can_shoot:
		shoot_timer -= delta
		if shoot_timer <= 0:
			can_shoot = true
	
	# Apply ocean physics
	if ocean:
		apply_ocean_effects(delta)
	else:
		linear_velocity *= 0.98
	
	# Get input
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	
	var shoot_input = Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)
	
	# Handle movement
	if movement_input.length() > 0.1 and can_thrust:
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
		if animated_sprite and animated_sprite.animation != "idle":
			animated_sprite.play("idle")

func apply_ocean_effects(delta: float):
	"""Apply depth-based buoyancy and water drag"""
	var depth = ocean.get_depth(global_position)
	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
	apply_central_force(Vector2(0, -buoyancy_force))
	
	if depth > 0:
		# Underwater - apply water drag
		linear_velocity *= ocean.water_drag
	else:
		# In air - apply air drag
		linear_velocity *= ocean.air_drag

func return_to_idle_after_delay():
	await get_tree().create_timer(kick_animation_duration).timeout
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play("idle")

func apply_thrust(direction: Vector2):
	var kick_direction = -direction
	
	# Cancel upward thrust in air
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0:
		return
	
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.global_rotation = direction.angle() + deg_to_rad(-90)
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
	
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.global_rotation = direction.angle() + deg_to_rad(90)
		animated_sprite.play("shoot")
		return_to_idle_after_delay()
	
	# Spawn bullet
	var bullet = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = global_position + direction * 30
	
	# Set bullet velocity
	bullet.set_velocity(direction * bullet_speed)
	
	# Start cooldown
	can_shoot = false
	shoot_timer = shoot_cooldown

func apply_flipper_force(direction: Vector2, force_multiplier: float = 5.0):
	"""Apply strong pinball-like forces from flippers"""
	apply_central_impulse(direction * thrust_force * force_multiplier)

func take_damage(amount: float):
	current_health -= amount
	
	# Flash red
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.modulate = Color.RED
		await get_tree().create_timer(0.1).timeout
		sprite.modulate = Color.WHITE
	
	if current_health <= 0:
		die()

func die():
	print("Turtle died!")
	# TODO: Death animation, respawn, etc.
