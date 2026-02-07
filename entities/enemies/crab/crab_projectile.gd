extends RigidBody2D
class_name CrabProjectile

## Projectile thrown by crabs - arcs through water
## Damages player on contact, destroyed on wall hit

@export var lifetime: float = 3.0
@export var damage: float = 15.0
@export var water_drag: float = 0.92  # Less drag than bullets (heavier)
@export var gravity_multiplier: float = 0.8  # Affected by gravity for arc

var ocean: Ocean = null

func _ready():
	# Physics setup
	gravity_scale = gravity_multiplier
	linear_damp = 0.5
	angular_damp = 2.0
	lock_rotation = false  # Allow tumbling
	mass = 0.5  # Heavier than bullets
	
	# CRITICAL: Enable contact monitoring for body_entered signal
	contact_monitor = true
	max_contacts_reported = 4
	
	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 4 (bullets/projectiles)
	# - Collision Mask: 1 + 2 (world + player)
	
	# Find ocean for depth-based effects
	ocean = get_tree().get_first_node_in_group("ocean")
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	
	# Auto-destroy after lifetime
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func set_velocity(vel: Vector2):
	"""Set initial throw velocity"""
	linear_velocity = vel

func _physics_process(delta):
	# Apply water drag if underwater
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0:
			linear_velocity *= water_drag
	
	# Tumble naturally as it falls
	angular_velocity = linear_velocity.x * 0.01

func _on_body_entered(body):
	# Damage player
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return
	
	# Ignore enemies (including other crabs)
	if body.is_in_group("enemies"):
		queue_free()
		return
	
	# Hit wall/floor - destroy with small bounce
	if body is StaticBody2D or body.is_in_group("walls"):
		# Small bounce effect before destruction
		linear_velocity *= -0.3
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			queue_free()
			return
			
	queue_free()
