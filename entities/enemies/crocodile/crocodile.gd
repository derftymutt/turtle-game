extends BaseEnemyStatic
class_name Crocodile

## Surface-dwelling patrol enemy that chases the player
## Uses AnimatableBody2D (via BaseEnemyStatic) for immovable, damage-dealing behavior
## Features vertical attack animation when player is directly below

# Patrol settings
@export var patrol_speed: float = 80.0
@export var chase_speed: float = 150.0
@export var patrol_min_x: float = -250.0
@export var patrol_max_x: float = 250.0

# Surface positioning
@export var target_surface_depth: float = 5.0  # Pixels below ocean surface

# Behavior settings
@export var vertical_attack_h_range: float = 40.0  # Horizontal range for vertical attack
@export var vertical_attack_v_threshold: float = 30.0  # Vertical distance to trigger
@export var flip_deadzone: float = 20.0  # Prevents rapid sprite flipping
@export var chase_slowdown_range: float = 50.0  # Distance to start slowing down

# Knockback settings
@export var bounce_speed: float = 300.0  # Horizontal bounce velocity
@export var upward_boost: float = 200.0  # Extra upward velocity when hit from below

# Visual
@export var bob_amount: float = 2.0
@export var bob_speed: float = 1.5

# Internal state
enum State { PATROL_LEFT, PATROL_RIGHT, CHASE }
var current_state: State = State.PATROL_RIGHT
var player: Node2D = null
var ocean: Ocean = null
var bob_offset: float = 0.0
var is_in_vertical_attack: bool = false
var current_flip_h: bool = false

@onready var patrol_area = $PatrolArea

func _enemy_ready():
	# AnimatableBody2D setup - manual position control
	sync_to_physics = false
	
	# Health configuration
	max_health = 40.0
	current_health = max_health
	
	# Find scene references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Visual setup
	bob_offset = randf() * TAU
	
	# Set up player detection area
	if patrol_area:
		patrol_area.body_entered.connect(_on_player_detected)
		patrol_area.body_exited.connect(_on_player_lost)
		patrol_area.collision_layer = 0
		patrol_area.collision_mask = 1
	
	# Random starting direction
	if randf() > 0.5:
		current_state = State.PATROL_LEFT

func _physics_process(delta):
	# Lock to surface depth
	_apply_surface_locking()
	
	# Visual bobbing animation
	_update_bobbing(delta)
	
	# Calculate and apply movement
	var movement_x = _calculate_movement(delta)
	global_position.x += movement_x
	
	# Update sprite animation and orientation
	_update_sprite_state(movement_x)
	
	# Prevent excessive rotation
	rotation = clamp(rotation, deg_to_rad(-15), deg_to_rad(15))

func _calculate_movement(delta: float) -> float:
	"""Calculate horizontal movement based on current state"""
	var movement = 0.0
	
	match current_state:
		State.PATROL_LEFT:
			movement = -patrol_speed * delta
			if global_position.x <= patrol_min_x:
				current_state = State.PATROL_RIGHT
		
		State.PATROL_RIGHT:
			movement = patrol_speed * delta
			if global_position.x >= patrol_max_x:
				current_state = State.PATROL_LEFT
		
		State.CHASE:
			if player and is_instance_valid(player):
				var to_player_x = player.global_position.x - global_position.x
				var distance = abs(to_player_x)
				var direction = sign(to_player_x)
				
				# Slow down when approaching to prevent jittering
				var speed_multiplier = 1.0
				if distance < chase_slowdown_range:
					speed_multiplier = max(distance / chase_slowdown_range, 0.2)
				
				movement = direction * chase_speed * speed_multiplier * delta
			else:
				current_state = State.PATROL_RIGHT
	
	return movement

func _update_sprite_state(movement_x: float):
	"""Update animation and sprite orientation based on state"""
	if not sprite or not sprite is AnimatedSprite2D:
		return
	
	# Check for vertical attack conditions
	_update_vertical_attack_state()
	
	# Apply appropriate animation
	if is_in_vertical_attack:
		if sprite.animation != "vertical_attack":
			sprite.play("vertical_attack")
		sprite.flip_h = false
	else:
		if sprite.animation != "swim":
			sprite.play("swim")
		
		# Handle sprite flipping with deadzone to prevent rapid switching
		if current_state == State.CHASE:
			sprite.flip_h = current_flip_h
		else:
			sprite.flip_h = movement_x < 0

func _update_vertical_attack_state():
	"""Check if conditions are met for vertical attack animation"""
	if not player or not is_instance_valid(player) or current_state != State.CHASE:
		is_in_vertical_attack = false
		return
	
	var to_player = player.global_position - global_position
	var horizontal_distance = abs(to_player.x)
	var vertical_distance = to_player.y
	
	# Use hysteresis to prevent animation flickering
	if is_in_vertical_attack:
		# Wider threshold to exit - harder to cancel
		if vertical_distance < 10 or horizontal_distance > 60:
			is_in_vertical_attack = false
	else:
		# Tighter threshold to enter
		if vertical_distance > vertical_attack_v_threshold and horizontal_distance < vertical_attack_h_range:
			is_in_vertical_attack = true
	
	# Update facing direction with deadzone (only when not in vertical attack)
	if not is_in_vertical_attack:
		if to_player.x < -flip_deadzone:
			current_flip_h = true
		elif to_player.x > flip_deadzone:
			current_flip_h = false

func _update_bobbing(delta: float):
	"""Apply subtle vertical bobbing animation"""
	bob_offset += bob_speed * delta
	if sprite:
		sprite.position.y = sin(bob_offset) * bob_amount

func _apply_surface_locking():
	"""Lock crocodile to fixed surface depth"""
	var ocean_surface_y = -126.0  # Match camera's ocean_surface_y
	var target_y = ocean_surface_y + target_surface_depth
	global_position.y = target_y

func _on_player_detected(body: Node2D):
	"""Player entered detection range - begin chase"""
	if body.is_in_group("player"):
		player = body
		current_state = State.CHASE

func _on_player_lost(body: Node2D):
	"""Player left detection range - return to patrol"""
	if body.is_in_group("player"):
		# Resume patrol toward center
		if global_position.x < (patrol_min_x + patrol_max_x) / 2:
			current_state = State.PATROL_RIGHT
		else:
			current_state = State.PATROL_LEFT

func _deal_damage_to_player(player_node: Node2D):
	"""Override BaseEnemyStatic to add bounce effect on contact"""
	player_node.take_damage(contact_damage)
	
	if not player_node is RigidBody2D:
		return
	
	# Calculate bounce direction away from crocodile
	var knockback_dir = (player_node.global_position - global_position).normalized()
	
	# Apply bounce velocity directly (not absorbed by damping)
	player_node.linear_velocity += knockback_dir * bounce_speed
	
	# Extra upward boost if player hit from below
	if knockback_dir.y > 0:
		player_node.linear_velocity.y -= upward_boost

func die():
	"""Custom death animation - spin and sink"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	
	# Spin while dying
	tween.tween_property(self, "rotation", rotation + TAU * 2, 1.0)
	
	# Sink down
	tween.tween_property(self, "global_position:y", global_position.y + 100, 1.0)
	
	tween.finished.connect(queue_free)
	
	# Disable collision
	collision_layer = 0
	collision_mask = 0
