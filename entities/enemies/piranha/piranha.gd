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

# Wall avoidance settings
@export_group("Wall Navigation")
@export var wall_check_distance: float = 30.0  # How far ahead to check for walls
@export var wall_follow_distance: float = 20.0  # Preferred distance from wall
@export var wall_avoidance_force: float = 200.0  # Force to avoid walls
@export var stuck_detection_time: float = 1.0  # Time moving slowly = stuck
@export var stuck_velocity_threshold: float = 20.0  # Velocity below this = stuck

# Visual
@export var wiggle_speed: float = 8.0
@export var wiggle_amount: float = 0.15  # Rotation wiggle in radians

# Internal state
enum State { PATROL, CHASE, ATTACK, WALL_FOLLOW }
var current_state: State = State.PATROL
var player: Node2D = null
var ocean: Ocean = null

# Patrol variables
var patrol_center: Vector2
var patrol_target: Vector2
var patrol_timer: float = 0.0
var patrol_change_interval: float = 2.0

# Wall following variables
var wall_follow_direction: int = 1  # 1 for clockwise, -1 for counter-clockwise
var stuck_timer: float = 0.0
var last_position: Vector2

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
	last_position = global_position
	_choose_new_patrol_target()
	
	# Random starting wiggle offset
	wiggle_offset = randf() * TAU

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
	# Detect if stuck against wall
	_detect_stuck(delta)
	
	# Update state based on distance to player and stuck status
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
		State.WALL_FOLLOW:
			_wall_follow_behavior(delta)
	
	# Keep within preferred depth range
	_maintain_depth()
	
	# Apply speed limit
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed
	
	# Visual wiggle animation
	_animate_swimming(delta)
	
	# Update last position for stuck detection
	last_position = global_position

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
		
		State.WALL_FOLLOW:
			# Exit wall follow if we've cleared the obstacle
			if not _is_wall_ahead():
				stuck_timer = 0.0
				# Return to appropriate state based on player distance
				if distance < detection_range:
					current_state = State.CHASE if distance > attack_distance else State.ATTACK
				else:
					current_state = State.PATROL
					_choose_new_patrol_target()

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

func _wall_follow_behavior(_delta: float):
	"""Follow the wall until we can move past it"""
	var wall_normal = _get_wall_normal()
	
	if wall_normal == Vector2.ZERO:
		# No wall detected, exit wall follow
		current_state = State.PATROL
		_choose_new_patrol_target()
		return
	
	# Calculate tangent direction (perpendicular to wall normal)
	# Rotate normal 90 degrees based on follow direction
	var tangent = Vector2(-wall_normal.y, wall_normal.x) * wall_follow_direction
	
	# Apply force along the wall
	var follow_force = tangent * swim_force * 0.8
	apply_central_force(follow_force)
	
	# Also apply slight force away from wall to maintain distance
	var away_force = wall_normal * swim_force * 0.3
	apply_central_force(away_force)
	
	# Face movement direction
	_face_direction(tangent)
	
	# Periodically check if we should switch direction
	if randf() < 0.01:  # 1% chance per frame
		wall_follow_direction *= -1

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

func _detect_stuck(delta: float):
	"""Detect if piranha is stuck against a wall"""
	var moved_distance = global_position.distance_to(last_position)
	var is_moving_slowly = moved_distance < (stuck_velocity_threshold * delta)
	var is_trying_to_move = linear_velocity.length() > 10  # Has velocity but not moving much
	
	if is_moving_slowly and is_trying_to_move and _is_wall_ahead():
		stuck_timer += delta
		
		if stuck_timer >= stuck_detection_time and current_state != State.WALL_FOLLOW:
			# We're stuck! Enter wall follow mode
			current_state = State.WALL_FOLLOW
			# Randomly choose follow direction
			wall_follow_direction = 1 if randf() > 0.5 else -1
			stuck_timer = 0.0
	else:
		# Not stuck, reset timer
		if current_state != State.WALL_FOLLOW:
			stuck_timer = 0.0

func _is_wall_ahead() -> bool:
	"""Check if there's a wall in front of us using raycasts"""
	var space_state = get_world_2d().direct_space_state
	var check_direction = linear_velocity.normalized() if linear_velocity.length() > 1 else Vector2.RIGHT.rotated(rotation)
	
	# Cast ray ahead in movement direction
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + check_direction * wall_check_distance
	)
	query.collision_mask = 1  # Check layer 1 (walls/world)
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	return not result.is_empty()

func _get_wall_normal() -> Vector2:
	"""Get the normal vector of the wall we're touching"""
	var space_state = get_world_2d().direct_space_state
	var check_direction = linear_velocity.normalized() if linear_velocity.length() > 1 else Vector2.RIGHT.rotated(rotation)
	
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + check_direction * wall_check_distance
	)
	query.collision_mask = 1
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		return result.normal
	return Vector2.ZERO

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
