extends BaseEnemy
class_name Crocodile

## Surface-dwelling patrol enemy that chases the player
## Extends BaseEnemy for health/damage handling

# Patrol settings
@export var patrol_speed: float = 80.0
@export var chase_speed: float = 150.0
@export var patrol_min_x: float = -250.0
@export var patrol_max_x: float = 250.0

# Surface positioning
@export var target_surface_depth: float = 5.0  # How deep below surface (pixels)
@export var surface_lock_strength: float = 50.0

# Behavior settings
@export var detection_range: float = 120.0

# Visual
@export var bob_amount: float = 2.0
@export var bob_speed: float = 1.5

# Internal state
enum State { PATROL_LEFT, PATROL_RIGHT, CHASE }
var current_state: State = State.PATROL_RIGHT
var player: Node2D = null
var ocean: Ocean = null
var bob_offset: float = 0.0

@onready var patrol_area = $PatrolArea

func _enemy_ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 2.5
	angular_damp = 5.0
	mass = 2.0
	
	# Set health
	max_health = 40.0
	current_health = max_health
	
	# Find ocean and player
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Random starting offset for bob
	bob_offset = randf() * TAU
	
	# Set up detection area
	if patrol_area:
		patrol_area.body_entered.connect(_on_player_detected)
		patrol_area.body_exited.connect(_on_player_lost)
		patrol_area.collision_layer = 0
		patrol_area.collision_mask = 1
	
	# Start with random direction
	if randf() > 0.5:
		current_state = State.PATROL_LEFT

func _physics_process(delta):
	# Lock to surface depth
	apply_surface_locking()
	
	# Visual bobbing
	bob_offset += bob_speed * delta
	if sprite:
		sprite.position.y = sin(bob_offset) * bob_amount
	
	# State-based movement
	match current_state:
		State.PATROL_LEFT:
			patrol_movement(-1.0, patrol_speed)
			if global_position.x <= patrol_min_x:
				current_state = State.PATROL_RIGHT
		
		State.PATROL_RIGHT:
			patrol_movement(1.0, patrol_speed)
			if global_position.x >= patrol_max_x:
				current_state = State.PATROL_LEFT
		
		State.CHASE:
			if player and is_instance_valid(player):
				chase_player()
			else:
				current_state = State.PATROL_RIGHT
	
	# Clamp rotation (keep mostly horizontal)
	rotation = clamp(rotation, deg_to_rad(-15), deg_to_rad(15))

func apply_surface_locking():
	"""Keep croc at the surface using forces"""
	if not ocean:
		return
	
	var depth = ocean.get_depth(global_position)
	var desired_depth = target_surface_depth
	var depth_error = depth - desired_depth
	
	# Apply vertical force to maintain position
	var vertical_force = -depth_error * surface_lock_strength
	apply_central_force(Vector2(0, vertical_force))
	
	# Damping for stability
	linear_velocity.y *= 0.9

func patrol_movement(direction: float, speed: float):
	"""Simple horizontal patrol movement"""
	var target_velocity = Vector2(direction * speed, linear_velocity.y)
	linear_velocity.x = lerp(linear_velocity.x, target_velocity.x, 0.1)
	
	# Flip sprite based on direction
	if sprite:
		sprite.flip_h = direction < 0

func chase_player():
	"""Move toward player when detected"""
	if not player or not is_instance_valid(player):
		return
	
	var to_player = player.global_position.x - global_position.x
	var direction = sign(to_player)
	
	patrol_movement(direction, chase_speed)

func _on_player_detected(body: Node2D):
	if body.is_in_group("player"):
		player = body
		current_state = State.CHASE

func _on_player_lost(body: Node2D):
	if body.is_in_group("player"):
		if global_position.x < (patrol_min_x + patrol_max_x) / 2:
			current_state = State.PATROL_RIGHT
		else:
			current_state = State.PATROL_LEFT

## Override die() for custom death animation
func die():
	# Spin and sink death animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	
	# Spin while dying
	tween.tween_property(self, "rotation", rotation + TAU * 2, 1.0)
	
	# Sink down
	tween.tween_property(self, "global_position:y", global_position.y + 100, 1.0)
	
	tween.finished.connect(queue_free)
	
	# Disable collision while dying
	collision_layer = 0
	collision_mask = 0
