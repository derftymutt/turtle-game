# plane_bullet.gd
extends CharacterBody2D
class_name PlaneBullet

## Straight-line bullet fired in a spread arc by the military plane.
## Uses CharacterBody2D — movement is fully scripted, no physics engine involved.

@export var damage: float = 10.0
@export var lifetime: float = 3.0
@export var speed: float = 300.0

func _ready() -> void:
	# NOTE: Set in Inspector:
	#   Collision Layer: 4  (projectiles)
	#   Collision Mask:  player layer only
	add_to_group("plane_projectiles")

	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func _physics_process(delta: float) -> void:
	# Rotate sprite to face direction of travel
	if velocity.length() > 5.0:
		rotation = velocity.angle()

	var collision := move_and_collide(velocity * delta)
	if collision:
		var body := collision.get_collider()
		if body and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
