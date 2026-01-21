extends BaseEnemy
class_name Piranha

## Fast-swimming predator that actively chases the player
## Uses force-based movement for fluid underwater motion

# Movement settings
@export var swim_force: float = 150.0
@export var max_speed: float = 120.0
@export var patrol_radius: float = 80.0
@export var patrol_speed_multiplier: float = 0.6  # Slower when patrolling

# Behavior settings
@export var detection_range: float = 150.0
@export var attack_distance: float = 20.0  # How close before "biting"
@export var lose_interest_range: float = 200.0

# Ocean depth preferences
@export var preferred_depth_min: float = 40.0  # Stays below this depth
@export var preferred_depth_max: float = 140.0  # Stays above this depth
@export var depth_correction_force: float = 50.0

# Visual
@export var wiggle_speed: float = 8.0
@export var wiggle_amount: float = 0.15  # Rotation wiggle in radians

# Internal state
enum State { PATROL, CHASE, ATTACK }
var current_state: State = State.PATROL
var player: Node2D = null
var ocean: Ocean = null

# Patrol variables
var patrol_center: Vector2
var patrol_target: Vector2
var patrol_timer: float = 0.0
var patrol_change_interval: float = 2.0

# Animation
var wiggle_offset: float = 0.0

func _enemy_ready():
	# Physics setup - nimble swimmer
	gravity_scale = 0.0
	linear_damp = 3.0  # More drag than turtle for tighter control
	angular_damp = 5.0
	mass = 0.8
	
	# Set health (piranhas are fragile but fast)
	max_health = 10.0
	current_health = max_health
	contact_damage = 15.0
	
	# Find references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Set up patrol center
	patrol_center = global_position
	_choose_new_patrol_target()
	
	# Random starting wiggle offset
	wiggle_offset = randf() * TAU

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
	# Update state based on distance to player
	var distance_to_player = global_position.distance_to(player.global_position)
	_update_state(distance_to_player)
	
	# Execute state behavior
	match current_state:
		State.PATROL:
			_patrol_behavior(delta)
		State.CHASE:
			_chase_behavior(delta)
		State.ATTACK:
			_attack_behavior(delta)
	
	# Keep within preferred depth range
	_maintain_depth()
	
	# Apply speed limit
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	# Visual wiggle animation
	_animate_swimming(delta)

func _update_state(distance: float):
	"""Determine which state we should be in"""
	match current_state:
		State.PATROL:
			if distance < detection_range:
				current_state = State.CHASE
		
		State.CHASE:
			if distance > lose_interest_range:
				current_state = State.PATROL
				_choose_new_patrol_target()
			elif distance < attack_distance:
				current_state = State.ATTACK
		
		State.ATTACK:
			if distance > attack_distance * 1.5:
				current_state = State.CHASE

func _patrol_behavior(delta: float):
	"""Swim in a lazy pattern around patrol center"""
	patrol_timer += delta
	
	# Choose new target periodically
	if patrol_timer >= patrol_change_interval:
		_choose_new_patrol_target()
		patrol_timer = 0.0
	
	# Swim toward patrol target
	var to_target = patrol_target - global_position
	if to_target.length() > 10:
		var direction = to_target.normalized()
		var force = direction * swim_force * patrol_speed_multiplier
		apply_central_force(force)
		
		# Face movement direction
		_face_direction(direction)

func _chase_behavior(_delta: float):
	"""Aggressively pursue the player"""
	var to_player = player.global_position - global_position
	var direction = to_player.normalized()
	
	# Apply strong chase force
	var force = direction * swim_force
	apply_central_force(force)
	
	# Face the player
	_face_direction(direction)

func _attack_behavior(_delta: float):
	"""Close-range aggressive movement (biting behavior)"""
	# Similar to chase but even more aggressive
	var to_player = player.global_position - global_position
	var direction = to_player.normalized()
	
	# Extra force for attack lunge
	var force = direction * swim_force * 1.5
	apply_central_force(force)
	
	# Face the player
	_face_direction(direction)

func _maintain_depth():
	"""Apply vertical forces to stay within preferred depth range"""
	if not ocean:
		return
	
	var depth = ocean.get_depth(global_position)
	var correction = 0.0
	
	if depth < preferred_depth_min:
		# Too shallow - push down
		correction = depth_correction_force
	elif depth > preferred_depth_max:
		# Too deep - push up
		correction = -depth_correction_force
	
	if correction != 0:
		apply_central_force(Vector2(0, correction))

func _choose_new_patrol_target():
	"""Pick a random point within patrol radius"""
	var random_angle = randf() * TAU
	var random_distance = randf_range(patrol_radius * 0.5, patrol_radius)
	var offset = Vector2(cos(random_angle), sin(random_angle)) * random_distance
	patrol_target = patrol_center + offset

func _face_direction(direction: Vector2):
	"""Make the piranha face its movement direction"""
	if sprite:
		# Flip sprite based on horizontal direction
		sprite.flip_h = direction.x < 0

func _animate_swimming(delta: float):
	"""Create a swimming wiggle effect"""
	wiggle_offset += wiggle_speed * delta
	
	# Wiggle faster when moving faster
	var speed_factor = linear_velocity.length() / max_speed
	var current_wiggle = sin(wiggle_offset) * wiggle_amount * speed_factor
	
	rotation = current_wiggle

## Override die() for piranha death animation
func die():
	# Spin and float up death animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	
	# Spin while dying
	tween.tween_property(self, "rotation", rotation + TAU, 0.8)
	
	# Float upward (dead fish float!)
	tween.tween_property(self, "global_position:y", global_position.y - 80, 0.8)
	
	tween.finished.connect(queue_free)
	
	# Disable collision while dying
	collision_layer = 0
	collision_mask = 0
