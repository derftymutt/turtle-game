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

# Urchin Transmogrify: which CircularBumper.SizePreset this urchin becomes.
# Only small and medium have bumper art.
@export_enum("Small:0", "Medium:1") var bumper_size: int = 0

# Internal state
var starting_position: Vector2
var bob_offset: float = 0.0
var rotation_offset: float = 0.0

# Stand-down state. Either one takes the urchin out of play (see
# _apply_stand_down()); they're tracked separately so ending one never
# revives an urchin the other still has down.
var _transmogrified: bool = false
var _benched: bool = false
var _benched_groups: Array[StringName] = []

func _enemy_ready():
	add_to_group("sea_urchins")

	# Sea urchins are invincible and pass-through!
	is_invincible = true
	pass_through_player = true  # This is just a flag for documentation/future use
	contact_damage= 15
	death_label = "a sea urchin"
	
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

## Urchin Transmogrify: stand this urchin down while a bumper takes its place.
## _contact_players is cleared because a turtle overlapping at the moment of
## the swap would otherwise stay in it.
func set_transmogrified(on: bool) -> void:
	_transmogrified = on
	if on:
		_contact_players.clear()
	_apply_stand_down()

## SeaUrchinGroup: take this urchin out of the level's active set (or put it
## back). Unlike transmogrify it also leaves every group ("enemies",
## "sea_urchins", ...) so nothing that looks urchins up finds it; the groups
## are remembered and rejoined when it comes back.
## Always reapplies visibility, so it also snaps back a benched urchin that
## SeaUrchinGroup made visible for a fade.
func set_benched(on: bool) -> void:
	if on != _benched:
		_benched = on
		if on:
			_benched_groups.clear()
			for group in get_groups():
				if not String(group).begins_with("_"):
					_benched_groups.append(group)
					remove_from_group(group)
			_contact_players.clear()
		else:
			for group in _benched_groups:
				add_to_group(group)
			_benched_groups.clear()
	_apply_stand_down()

func is_benched() -> bool:
	return _benched

## DISABLED process mode (which cascades to DamageArea) takes the body and its
## damage area out of the physics space and stops _process(), so nothing can
## hurt the turtle or be hit.
func _apply_stand_down() -> void:
	var down := _transmogrified or _benched
	visible = not down
	process_mode = Node.PROCESS_MODE_DISABLED if down else Node.PROCESS_MODE_INHERIT
