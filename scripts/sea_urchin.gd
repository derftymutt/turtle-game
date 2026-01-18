extends BaseEnemy
class_name SeaUrchin

## A stationary, invincible enemy that bobs in place
## Damages player on contact but cannot be destroyed

# Bobbing animation
@export var bob_amount: float = 5.0
@export var bob_speed: float = 1.2
@export var rotation_speed: float = 0.3  # Slow spin for visual interest

# Position locking
@export var lock_position: bool = true
@export var position_lock_strength: float = 100.0

# Internal state
var starting_position: Vector2
var bob_offset: float = 0.0
var rotation_offset: float = 0.0

func _enemy_ready():
	# Sea urchins are invincible and pass-through!
	is_invincible = true
	pass_through_player = true  # This is just a flag for documentation/future use
	
	# Physics setup - heavy and stationary
	gravity_scale = 0.0
	linear_damp = 10.0  # Very high damping to resist movement
	angular_damp = 5.0
	mass = 5.0  # Heavy so it doesn't get pushed around easily
	
	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 3 (enemies)
	# - Collision Mask: 4 (bullets only, for pass-through behavior)
	
	# Create collision shape if not present
	_setup_collision_shape()
	
	# Store starting position
	starting_position = global_position
	
	# Random starting offsets for variety
	bob_offset = randf() * TAU
	rotation_offset = randf() * TAU

func _setup_collision_shape():
	"""Ensure the RigidBody2D has a collision shape for bullet detection"""
	var existing_shape = get_node_or_null("CollisionShape2D")
	
	if not existing_shape:
		# Create a new collision shape
		var collision_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 8.0  # Adjust based on your sprite size
		collision_shape.shape = circle
		add_child(collision_shape)
		print("Sea Urchin: Created collision shape automatically")

func _physics_process(delta):
	# Lock to starting position if enabled
	if lock_position:
		apply_position_locking()
	
	# Bobbing animation
	bob_offset += bob_speed * delta
	if sprite:
		sprite.position.y = sin(bob_offset) * bob_amount
	
	# Slow rotation for visual interest
	rotation_offset += rotation_speed * delta
	rotation = sin(rotation_offset) * 0.2  # Subtle rock back and forth

func apply_position_locking():
	"""Keep urchin at its starting position using forces"""
	var position_error = starting_position - global_position
	
	# Apply force to return to starting position
	apply_central_force(position_error * position_lock_strength)
	
	# Dampen movement
	linear_velocity *= 0.8

## Override to provide special invincible feedback
func _play_invincible_feedback():
	if not sprite:
		return
	
	# Shake effect when hit
	var original_pos = sprite.position
	var shake_amount = 3.0
	
	# Quick shake sequence
	for i in range(4):
		if sprite and is_instance_valid(sprite):
			sprite.position = original_pos + Vector2(
				randf_range(-shake_amount, shake_amount),
				randf_range(-shake_amount, shake_amount)
			)
			await get_tree().create_timer(0.03).timeout
	
	# Return to normal (with bobbing offset)
	if sprite and is_instance_valid(sprite):
		sprite.position.x = original_pos.x
		# Keep the Y bobbing animation

## Sea urchins never die!
func die():
	pass  # Override to do nothing
