extends RigidBody2D

@export var lifetime: float = .7
@export var water_drag: float = 0.95
@export var damage: float = 10.0

var velocity: Vector2 = Vector2.ZERO

func _ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 0.1
	lock_rotation = true
	mass = 0.01
	
	# Apply initial velocity
	linear_velocity = velocity
	
	# Auto-destroy after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel  # Apply immediately

func _physics_process(_delta):
	# Apply water drag
	linear_velocity *= water_drag
	
	# Rotate to face direction of travel
	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func _on_body_entered(body):
	# Ignore player
	if body.is_in_group("player"):
		return
	
	# Damage enemies
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return
	
	# Hit wall/flipper - destroy bullet
	queue_free()
