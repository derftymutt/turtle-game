extends RigidBody2D

@export var lifetime: float = 0.7
@export var water_drag: float = 0.95

var velocity: Vector2 = Vector2.ZERO

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.1
	lock_rotation = true
	mass = 0.01
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	contact_monitor = true
	max_contacts_reported = 4

	add_to_group("bullets")
	modulate = Color(0.3, 0.9, 1.0)

	# NOTE: Collision layers MUST be set in Inspector (same as bullet.tscn):
	# - Collision Layer: 4 (bullets)
	# - Collision Mask: 1 + 3 (world + enemies)

	body_entered.connect(_on_body_entered)

	linear_velocity = velocity

	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel

func _physics_process(_delta):
	linear_velocity *= water_drag
	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func _on_body_entered(body):
	if body.is_in_group("player"):
		return

	# Phase enemies — including invincible ones
	if body.is_in_group("enemies"):
		if body.has_method("phase_shift"):
			body.phase_shift(5.0)
		queue_free()
		return

	# Phase 2: phase walls, bumpers, and flippers
	if body.is_in_group("dead_walls") or body.is_in_group("circular_bumpers") or body.is_in_group("flippers"):
		if body.has_method("phase_shift"):
			body.phase_shift(5.0)
		queue_free()
		return

	# Don't destroy ocean flora
	if body.is_in_group("ocean_flora"):
		queue_free()
		return

	# Everything else (other walls, flippers, etc.)
	queue_free()
