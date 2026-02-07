extends BaseEnemy
class_name Crab

## Floor-dwelling enemy that throws projectiles at player
## Relocates to a new position when damaged (unless killed)

# Projectile settings
@export var projectile_scene: PackedScene
@export var throw_cooldown: float = 1.0  # Time between throws
@export var throw_velocity: float = 800.0  # Base throw speed
@export var throw_arc_height: float = 0.2  # How much upward angle (0-1)
@export var detection_range: float = 150.0  # How far can detect player

# Floor positioning
@export var floor_y: float = 165.0  # Y position of floor (matches FloorSeeder)
@export var floor_min_x: float = -280.0
@export var floor_max_x: float = 280.0
@export var position_lock_strength: float = 80.0

# Relocation on damage
@export var relocation_distance_min: float = 10.0  # Min distance to move when hit
@export var relocation_distance_max: float = 50.0  # Max distance to move when hit
@export var relocation_speed: float = 500.0  # How fast to scuttle to new spot

# Visual
@export var idle_bob_amount: float = 1.0
@export var idle_bob_speed: float = 0.8

@export var reproduceThreshold: int = 40 # seconds til reproduce when not hit

# Internal state
enum State { IDLE, THROWING, RELOCATING }
var current_state: State = State.IDLE
var throw_timer: float = 0.0
var starting_position: Vector2
var relocation_target: Vector2
var bob_offset: float = 0.0
var player: Node2D = null
var ocean: Ocean = null

var reproduceTimer = reproduceThreshold
var markForReproduction = false
var hasReproduced: bool = false

func _enemy_ready():
	# Physics setup - stays put on floor
	gravity_scale = 0.0
	linear_damp = 15.0  # High damping to resist movement
	angular_damp = 5.0
	mass = 3.0  # Heavy
	lock_rotation = true
	
	# Set health
	max_health = 50.0
	current_health = max_health
	contact_damage = 10.0
	
	# Find references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Store starting position
	starting_position = global_position
	
	# Random starting offsets for variety
	bob_offset = randf() * TAU
	throw_timer = randf() * throw_cooldown  # Stagger initial throws
	
	# Create collision shape if not present
	_setup_collision_shape()

func _setup_collision_shape():
	"""Ensure the RigidBody2D has a collision shape"""
	var existing_shape = get_node_or_null("CollisionShape2D")
	
	if not existing_shape:
		var collision_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 10.0  # Adjust based on your sprite size
		collision_shape.shape = circle
		add_child(collision_shape)
		print("Crab: Created collision shape automatically")

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
	# Update state machine
	match current_state:
		State.IDLE:
			_idle_behavior(delta)
		State.THROWING:
			_throwing_behavior(delta)
		State.RELOCATING:
			_relocating_behavior(delta)
	
	# Visual bobbing animation (unless relocating)
	if current_state != State.RELOCATING:
		bob_offset += idle_bob_speed * delta
		if sprite:
			sprite.position.y = sin(bob_offset) * idle_bob_amount
	
	# Lock to floor position
	_lock_to_floor()

func _idle_behavior(delta: float):
	"""Wait and prepare to throw"""
	throw_timer -= delta
	
	if throw_timer <= 0:
		# Check if player is in range
		var distance = global_position.distance_to(player.global_position)
		if distance <= detection_range:
			current_state = State.THROWING
			throw_timer = throw_cooldown
			
	"""Reproduce after time threshold"""
	reproduceTimer -= delta
	
	if reproduceTimer <= 0:
		markForReproduction = true

func _throwing_behavior(_delta: float):
	"""Execute throw animation and spawn projectile"""
	throw_projectile()
	current_state = State.IDLE

func _relocating_behavior(delta: float):
	var sprite = $AnimatedSprite2D
	"""Scuttle to new location"""
	var to_target = relocation_target - global_position
	var distance = to_target.length()
	
	print('ID:', get_instance_id())
	print('distance', distance)
	if distance < 20.0:
		# Reached target
		if sprite:
			sprite.play('default')
		starting_position = global_position
		current_state = State.IDLE
		throw_timer = throw_cooldown * 0.5  # Shorter cooldown after relocation
		return
	
	# Move toward target
	if sprite:
		sprite.play('move')
	var direction = to_target.normalized()
	apply_central_force(direction * relocation_speed * 10)
	
	# Face movement direction
	if sprite:
		sprite.flip_h = direction.x < 0

func _lock_to_floor():
	"""Keep crab locked to floor position"""
	var target_y = floor_y
	var y_error = target_y - global_position.y
	
	# Apply vertical force to maintain floor position
	apply_central_force(Vector2(0, y_error * position_lock_strength))
	
	# Dampen vertical movement
	linear_velocity.y *= 0.8

func throw_projectile():
	"""Throw a projectile at the player"""
	if not projectile_scene:
		push_warning("Crab: No projectile scene assigned!")
		return
	
	if not player or not is_instance_valid(player):
		return
	
	# Calculate throw direction with arc
	var to_player = player.global_position - global_position
	var distance = to_player.length()
	var horizontal_direction = to_player.normalized()
	
	# Add upward arc component
	var arc_angle = lerp(0.0, PI / 4, throw_arc_height)  # 0 to 45 degrees
	var throw_direction = horizontal_direction.rotated(-arc_angle)
	
	# Adjust velocity based on distance (throw harder for farther targets)
	var distance_multiplier = clamp(distance / 150.0, 0.8, 1.5)
	var throw_vel = throw_direction * throw_velocity * distance_multiplier
	
	# Spawn projectile
	var projectile = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	
	# Position slightly in front of crab
	var spawn_offset = horizontal_direction * 15
	projectile.global_position = global_position + spawn_offset
	
	# Set velocity
	if projectile.has_method("set_velocity"):
		projectile.set_velocity(throw_vel)
	else:
		projectile.linear_velocity = throw_vel
	
	# Face throw direction
	if sprite:
		sprite.flip_h = horizontal_direction.x < 0
	
	print("Crab threw projectile at player!")

func choose_relocation_target():
	"""Pick a new floor position away from current spot"""
	var attempts = 10
	var best_target = starting_position
	var best_distance = 0.0
	
	for i in attempts:
		# Generate random position on floor
		var candidate = Vector2(
			randf_range(floor_min_x, floor_max_x),
			floor_y
		)
		
		# Prefer positions farther from current location
		var distance_from_current = candidate.distance_to(global_position)
		
		if distance_from_current > best_distance:
			if distance_from_current >= relocation_distance_min:
				best_target = candidate
				best_distance = distance_from_current
				
				# If we found a good spot, use it
				if distance_from_current >= relocation_distance_max:
					break
	
	return best_target

## Override take_damage to trigger relocation
func take_damage(amount: float):
	if is_invincible or current_state == State.RELOCATING:
		_play_invincible_feedback()
		return
	
	var was_alive = current_health > 0
	current_health -= amount
	_play_damage_feedback()
	reproduceTimer = reproduceThreshold
	
	if current_health <= 0:
		die()
	elif was_alive and current_state != State.RELOCATING:
		# Still alive and not already relocating - scuttle away!
		relocation_target = choose_relocation_target()
		current_state = State.RELOCATING
		print("Crab relocating to: ", relocation_target)

## Override die() for crab death animation
func die():
	# Flip upside down and fade death animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	
	# Flip upside down
	if sprite:
		tween.tween_property(sprite, "rotation", PI, 0.8)
	
	# Float up slightly (dead crab)
	tween.tween_property(self, "global_position:y", global_position.y - 20, 0.8)
	
	tween.finished.connect(queue_free)
	
	# Disable collision while dying
	collision_layer = 0
	collision_mask = 0
