extends RigidBody2D

@export var lifetime: float = .7
@export var water_drag: float = 0.95
@export var damage: float = 10.0

var velocity: Vector2 = Vector2.ZERO
var hit_targets: Array = []  # Track what we've already hit
var first_physics_frame: bool = true  # Flag to check overlaps on first frame

func _ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 0.1
	lock_rotation = true
	mass = 0.01
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	
	# CRITICAL: Enable contact monitoring for body_entered signal
	contact_monitor = true
	max_contacts_reported = 4
	
	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 4 (bullets)
	# - Collision Mask: 1 + 3 (world + enemies)
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	
	# Apply initial velocity
	linear_velocity = velocity
	
	# Auto-destroy after lifetime
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel

func _physics_process(_delta):
	# Check for point-blank hits on first physics frame
	if first_physics_frame:
		first_physics_frame = false
		check_initial_overlaps()
	
	# Apply water drag
	linear_velocity *= water_drag
	
	# Rotate to face direction of travel
	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func check_initial_overlaps():
	"""Check if we spawned inside/very close to an enemy (point-blank shot)"""
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return
	
	# Use a CIRCLE shape that's bigger than our actual collision
	# This catches enemies within ~40 pixels
	var query = PhysicsShapeQueryParameters2D.new()
	var expanded_shape = CircleShape2D.new()
	expanded_shape.radius = 25.0  # Larger detection radius for point-blank
	
	query.shape = expanded_shape
	query.transform = global_transform
	query.collision_mask = 4  # Check layer 3 (enemies) - bit 2 = value 4
	query.exclude = [self]
	
	var results = space_state.intersect_shape(query, 10)
	
	for result in results:
		var body = result.collider
		if body and body.is_in_group("enemies"):
			# Verify it's actually close (within ~30 pixels)
			var distance = global_position.distance_to(body.global_position)
			if distance < 35.0:  # Point-blank range
				_hit_enemy(body)
				return

func _on_body_entered(body):
	# Ignore player
	if body.is_in_group("player"):
		return
	
	# Pop air bubbles (before enemies, so they take priority)
	if body.is_in_group("air_bubbles") and body.has_method("pop_from_bullet"):
		body.pop_from_bullet()
		queue_free()
		return
	
	# Damage enemies (including invincible ones - they'll show feedback!)
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return
	
	# Hit wall/flipper - destroy bullet
	queue_free()

func _hit_enemy(body):
	"""Deal damage to an enemy and destroy the bullet"""
	# Prevent hitting the same enemy twice
	if body in hit_targets:
		return
	
	hit_targets.append(body)
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()
