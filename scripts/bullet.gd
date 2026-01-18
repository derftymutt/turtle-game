extends RigidBody2D

@export var lifetime: float = 3.0
@export var water_drag: float = 0.95
@export var damage: float = 10.0

var velocity: Vector2 = Vector2.ZERO

func _ready():
	# Set up physics for underwater projectile
	gravity_scale = 0.2
	linear_damp = 0.1  # Changed from 1.5 - MUCH less drag

	# Apply the initial velocity directly
	linear_velocity = velocity
	
	# Auto-destroy after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel  # Apply it immediately

func _physics_process(_delta):
	# Apply water drag
	linear_velocity *= water_drag
	
	# Optional: Rotate to face direction of travel
	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func _on_body_entered(body):
	# Handle collision with enemies, obstacles, etc.
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	# Create splash effect or impact particles here
	
	queue_free()
