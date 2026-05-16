extends BaseEnemy
class_name Crab

## Floor-dwelling enemy that throws projectiles at player
## Relocates to a new position when damaged (unless killed)

# Signals
signal ready_to_reproduce(crab: Crab)

# Projectile settings
@export var projectile_scene: PackedScene
@export var throw_cooldown: float = 1.0  # Time between throws
@export var throw_velocity: float = 280.0  # Base throw speed
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

# Reproduction
@export var reproduce_threshold: float = 40.0  # Seconds til reproduce when not hit

# Internal state
enum State { IDLE, WINDUP, THROWING, RELOCATING }
var current_state: State = State.IDLE
var throw_timer: float = 0.0
var starting_position: Vector2
var relocation_target: Vector2
var bob_offset: float = 0.0
var player: Node2D = null
var ocean: Ocean = null

# Windup telegraph
const WINDUP_DURATION: float = 0.6
var _windup_timer: float = 0.0
var _windup_node: Node2D = null

# Reproduction tracking (private - use signals to access)
var _reproduce_timer: float = 0.0
var _has_reproduced: bool = false

# Relocation timeout — prevents permanent RELOCATING invincibility if crab gets stuck
var _relocation_elapsed: float = 0.0
const RELOCATION_TIMEOUT: float = 3.0

func _enemy_ready():
	# Physics setup - stays put on floor
	gravity_scale = 0.0
	linear_damp = 15.0  # High damping to resist movement
	angular_damp = 5.0
	mass = 3.0  # Heavy
	lock_rotation = true
	
	# Set health
	max_health = 30.0
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
	
	# Initialize reproduction timer
	_reproduce_timer = reproduce_threshold
	
	# Add to crabs group for easy lookup
	add_to_group("crabs")
	
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
		State.WINDUP:
			_windup_behavior(delta)
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
			current_state = State.WINDUP
			_windup_timer = WINDUP_DURATION
			_start_windup_indicator()
			throw_timer = throw_cooldown
	
	# Reproduction timer (only in IDLE state, only if not already reproduced)
	if not _has_reproduced:
		_reproduce_timer -= delta
		
		if _reproduce_timer <= 0:
			_has_reproduced = true
			ready_to_reproduce.emit(self)
			print("🦀 Crab ready to reproduce!")

func _windup_behavior(delta: float):
	_windup_timer -= delta
	if _windup_timer <= 0:
		current_state = State.THROWING

func _throwing_behavior(_delta: float):
	_stop_windup_indicator()
	throw_projectile()
	current_state = State.IDLE

func _start_windup_indicator():
	_stop_windup_indicator()
	if not player or not is_instance_valid(player):
		return
	var indicator = Sprite2D.new()
	indicator.texture = preload("res://entities/enemies/crab/sprites/crab_projectile1.png")
	var to_player = (player.global_position - global_position).normalized()
	indicator.position = to_player * 14.0 + Vector2(0, -4)
	indicator.scale = Vector2.ONE
	_windup_node = indicator
	add_child(indicator)
	var tween = create_tween().set_loops()
	tween.tween_property(indicator, "scale", Vector2(2.5, 2.5), WINDUP_DURATION * 0.4)
	tween.tween_property(indicator, "scale", Vector2(1.0, 1.0), WINDUP_DURATION * 0.2)

func _stop_windup_indicator():
	if _windup_node and is_instance_valid(_windup_node):
		_windup_node.queue_free()
	_windup_node = null

func _relocating_behavior(delta: float):
	"""Scuttle to new location"""
	_relocation_elapsed += delta

	# If stuck (boxed by walls or other crabs), give up and return to idle
	if _relocation_elapsed >= RELOCATION_TIMEOUT:
		_finish_relocation()
		return

	var to_target = relocation_target - global_position
	var distance = to_target.length()

	if distance < 20.0:
		_finish_relocation()
		return

	# Don't interrupt a damage animation mid-play
	if not _is_playing_damage_animation:
		var animated_sprite = get_node_or_null("AnimatedSprite2D")
		if animated_sprite and animated_sprite.sprite_frames:
			if current_health <= 10.0 and animated_sprite.sprite_frames.has_animation("near_death"):
				animated_sprite.play('near_death')
			elif animated_sprite.sprite_frames.has_animation("move"):
				animated_sprite.play('move')

	var direction = to_target.normalized()
	apply_central_force(direction * relocation_speed * 10)

	if sprite:
		sprite.flip_h = direction.x < 0

func _finish_relocation():
	"""Shared exit path for relocation — reached target or timed out"""
	_relocation_elapsed = 0.0
	starting_position = global_position
	current_state = State.IDLE
	throw_timer = throw_cooldown * 0.5
	var animated_sprite = get_node_or_null("AnimatedSprite2D")
	if animated_sprite and animated_sprite.sprite_frames:
		if current_health <= 10.0 and animated_sprite.sprite_frames.has_animation("near_death"):
			animated_sprite.play('near_death')
		elif animated_sprite.sprite_frames.has_animation("default"):
			animated_sprite.play('default')

func _lock_to_floor():
	"""Keep crab locked to floor position"""
	var target_y = floor_y
	var y_error = target_y - global_position.y

	# Hard ceiling at ocean surface — should never trigger normally, but guards
	# against physics edge cases that could launch the crab out of the water
	if ocean and global_position.y < ocean.surface_y:
		global_position.y = ocean.surface_y
		linear_velocity.y = maxf(linear_velocity.y, 0.0)

	# Apply vertical force to maintain floor position
	apply_central_force(Vector2(0, y_error * position_lock_strength))

	# Dampen vertical movement
	linear_velocity.y *= 0.8

	# Horizontal separation: push apart from nearby crabs to prevent stacking
	const SEPARATION_RADIUS: float = 30.0
	const SEPARATION_FORCE: float = 1200.0
	for crab in get_tree().get_nodes_in_group("crabs"):
		if crab == self or not is_instance_valid(crab):
			continue
		var delta_x = global_position.x - crab.global_position.x
		var dist = abs(delta_x)
		if dist < SEPARATION_RADIUS and dist > 0.1:
			apply_central_force(Vector2(sign(delta_x) * SEPARATION_FORCE * (1.0 - dist / SEPARATION_RADIUS), 0))

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

func choose_relocation_target():
	"""Pick a new floor position away from current spot and other crabs"""
	const MIN_CRAB_SEPARATION: float = 35.0
	var other_crabs = get_tree().get_nodes_in_group("crabs")
	var best_target = Vector2(global_position.x, floor_y)
	var best_score = -INF

	for _i in range(15):
		var candidate = Vector2(
			randf_range(floor_min_x, floor_max_x),
			floor_y
		)
		var dist_from_self = candidate.distance_to(global_position)
		if dist_from_self < relocation_distance_min:
			continue

		# Reject positions too close to any other crab
		var too_close = false
		for crab in other_crabs:
			if crab == self or not is_instance_valid(crab):
				continue
			if candidate.distance_to(crab.global_position) < MIN_CRAB_SEPARATION:
				too_close = true
				break
		if too_close:
			continue

		# Score: prefer farther from self, capped at relocation_distance_max
		var score = min(dist_from_self, relocation_distance_max)
		if score > best_score:
			best_score = score
			best_target = candidate

	return best_target

## PUBLIC METHOD: Called by CrabSpawner to make baby crab relocate
func relocate_from_parent():
	relocation_target = choose_relocation_target()
	current_state = State.RELOCATING
	_relocation_elapsed = 0.0

## Override take_damage to trigger relocation and reset reproduction timer
func take_damage(amount: float):
	if is_invincible or current_state == State.RELOCATING:
		_play_invincible_feedback()
		return
	
	var was_alive = current_health > 0
	current_health -= amount
	_play_damage_feedback()
	
	# Reset reproduction timer on damage
	_reproduce_timer = reproduce_threshold
	
	if current_health <= 0:
		die()
	elif was_alive and current_state != State.RELOCATING:
		_stop_windup_indicator()
		relocation_target = choose_relocation_target()
		current_state = State.RELOCATING
		_relocation_elapsed = 0.0

## Override die() for crab death animation
func die():
	_play_die_sound()
	_stop_windup_indicator()
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
