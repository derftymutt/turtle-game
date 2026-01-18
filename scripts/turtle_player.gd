extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30000.0
@export var max_velocity: float = 2500.0     # Was 50000
@export var kick_animation_duration: float = 0.4

# Shooting properties
@export var shoot_cooldown: float = 0.3
@export var bullet_speed: float = 500.0       # Was 1000
@export var bullet_scene: PackedScene

# Thrust strengths (keeping your current working values)
@export var horizontal_thrust: float = 100.0  # Was 300
@export var upward_thrust: float = 75.0      # Was 250
@export var downward_thrust: float = 150.0    # Was 400


# Internal state
var can_thrust: bool = true
var can_shoot: bool = true
var thrust_timer: float = 0.0
var shoot_timer: float = 0.0

# Ocean reference
var ocean: Ocean = null

func _ready():
	#print("=== TURTLE DEBUG ===")
	#print("Turtle Position: ", global_position)
	#print("Collision Layer: ", collision_layer)
	#print("Collision Mask: ", collision_mask)
	#
	## Make sure turtle is in player group
	#add_to_group("player")
	#print("Turtle groups: ", get_groups())
	#print("===================")
	
	# Set up physics properties
	gravity_scale = 0.0  # We handle buoyancy manually via Ocean
	linear_damp = 2.0  # Increased to help settling
	angular_damp = 3.0
	mass = 1.0 
	# NOTE: We allow rotation for realistic physics, but use global_rotation on sprite
	
	# CRITICAL: Enable Continuous Collision Detection to prevent tunneling
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# Find the ocean in the scene
	ocean = get_tree().get_first_node_in_group("ocean")
	if not ocean:
		push_warning("No Ocean found! Add Ocean scene to level and add it to 'ocean' group.")
		# Fallback to old behavior
		gravity_scale = 0.1
	
	# Set up water disturbance
	#var disturbance = $WaterDisturbance
	#if disturbance:
		#disturbance.track_object(self)
		

	if ocean:
		print("Ocean position: ", ocean.global_position)
		print("Ocean surface_y: ", ocean.surface_y)
		print("Actual world surface: ", ocean.global_position.y + ocean.surface_y)

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
	
	# Apply ocean physics if we have an ocean
	if ocean:
		apply_ocean_effects(delta)
	else:
		# Fallback: apply simple water drag if no ocean
		linear_velocity *= 0.98
	
	# Get input from sticks
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	
	var shoot_input = Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)
	
	# Handle movement (thrust kick)
	if movement_input.length() > 0.1 and can_thrust:
		apply_thrust(movement_input.normalized())
	
	# Handle shooting
	if shoot_input.length() > 0.1 and can_shoot:
		shoot(shoot_input.normalized())
	
	# Clamp velocity to max
	if linear_velocity.length() > max_velocity:
		linear_velocity = linear_velocity.normalized() * max_velocity
	
	# Return to idle when moving slowly and not kicking
	if can_thrust and linear_velocity.length() < 50:
		var animated_sprite = $AnimatedSprite2D
		if animated_sprite and animated_sprite.animation != "idle":
			animated_sprite.play("idle")

func apply_ocean_effects(delta: float):
	"""Apply depth-based buoyancy and water drag from the Ocean"""
	var depth = ocean.get_depth(global_position)
	
	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
	apply_central_force(Vector2(0, -buoyancy_force))
	
	if depth > 0:
		# We're underwater - apply buoyancy
		#var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
		#apply_central_force(Vector2(0, -buoyancy_force))
		
		# Apply water drag from ocean
		linear_velocity *= ocean.water_drag
		
		#print("Depth: ", depth, " Buoyancy: ", buoyancy_force, " Turtle Y: ", global_position.y)
		
		# Optional: Visual feedback based on depth
		#modulate = ocean.get_pressure_tint(depth)
	else:
		# We're in air above surface - apply normal gravity
		#print("Above water! Velocity Y: ", linear_velocity.y)  # Check thisdsssdsdsa/wws
		#apply_central_force(Vector2(0, 980 * mass))
		linear_velocity *= ocean.air_drag
		
		#print("ABOVE WATER - Depth: ", depth, " Turtle Y: ", global_position.y)

func return_to_idle_after_delay():
	await get_tree().create_timer(kick_animation_duration).timeout
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play("idle")

func apply_thrust(direction: Vector2):
	var kick_direction = -direction
	
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0:
		return  # Cancel upward thrust in air
	
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		# Use global_rotation so sprite faces correct direction in world space
		# even if the body has rotated from physics
		animated_sprite.global_rotation = direction.angle() + deg_to_rad(-90) 
		
		# Play a single kick animation (or just use idle with rotation)
		animated_sprite.play("kick")  # Or "idle" if you want no animation
	
	# Determine thrust strength based on direction
	var thrust_strength = horizontal_thrust
	
	if kick_direction.y < 0:
		# Kicking upward (moving turtle up, against natural buoyancy rise)
		# This should be weaker since you're fighting the upward pull
		thrust_strength = upward_thrust
	elif kick_direction.y > 0:
		# Kicking downward (moving turtle down, with gravity helping)
		# This should be stronger since you're working with forces
		thrust_strength = downward_thrust
	else:
		# Pure horizontal thrust
		thrust_strength = horizontal_thrust
	
	# Apply the thrust
	linear_velocity += kick_direction * thrust_strength
	
	# Start cooldown
	can_thrust = false
	thrust_timer = kick_animation_duration

func shoot(direction: Vector2):
	if bullet_scene == null:
		push_warning("No bullet scene assigned!")
		return
		
	# Rotate sprite to face shooting direction
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		# Use global_rotation for consistent world-space orientation
		animated_sprite.global_rotation = direction.angle() + deg_to_rad(90) 
		animated_sprite.play("shoot")  # Or just "idle"
		
		return_to_idle_after_delay()
	
	# Spawn bullet
	var bullet = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	
	# Position bullet at turtle's mouth
	bullet.global_position = global_position + direction * 30
	
	# Set bullet velocity
	if bullet is RigidBody2D:
		bullet.linear_velocity = direction * bullet_speed
	
	# Start cooldown
	can_shoot = false
	shoot_timer = shoot_cooldown
	
	bullet.global_position = global_position + direction * 30
	print("Bullet spawned at: ", bullet.global_position, " with velocity: ", bullet.linear_velocity)

func apply_flipper_force(direction: Vector2, force_multiplier: float = 5.0):
	"""Call this from flipper objects to apply strong pinball-like forces"""
	apply_central_impulse(direction * thrust_force * force_multiplier)

# Debug helper - call this to see what depth zone you're in
func print_current_depth_info():
	if ocean:
		ocean.print_depth_info(global_position)
