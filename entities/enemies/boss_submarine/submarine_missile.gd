extends RigidBody2D
class_name SubmarineMissile

## ============================================================
## SUBMARINE MISSILE
## A projectile fired by the submarine boss in various patterns.
## Damages the turtle on contact. Destroyed by the sea floor,
## walls, or after its max lifetime expires.
##
## Collision layers (set in Inspector):
##   Layer: 8  (enemy projectiles)
##   Mask:  1  (world/walls) + 2 (player)
## ============================================================

@export var contact_damage: float = 18.0
@export var max_lifetime: float = 6.0

## Optional gentle homing — the missile slowly steers toward the player.
## Set to 0 to disable entirely. Keep very low (0–0.5) for subtle drift.
@export var homing_strength: float = 0.0

# Internal
var _age: float = 0.0
var _initial_velocity: Vector2 = Vector2.ZERO
var _player: Node2D = null

func _ready() -> void:
	add_to_group("enemy_projectiles")
	gravity_scale = 0.0
	linear_damp = 0.0
	lock_rotation = false
	contact_monitor = true
	max_contacts_reported = 4

	if homing_strength > 0.0:
		_player = get_tree().get_first_node_in_group("player")

	body_entered.connect(_on_body_entered)

## Set initial velocity — called immediately after spawn by the boss.
func set_velocity(vel: Vector2) -> void:
	_initial_velocity = vel
	linear_velocity = vel
	# Rotate sprite to face travel direction
	rotation = vel.angle()

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		queue_free()
		return

	# Subtle homing: nudge velocity toward player each frame
	if homing_strength > 0.0 and _player and is_instance_valid(_player):
		var to_player := (_player.global_position - global_position).normalized()
		var current_speed := linear_velocity.length()
		# Slerp-style blend: keep speed constant, rotate direction slightly
		linear_velocity = linear_velocity.lerp(
			to_player * current_speed,
			homing_strength * delta
		)
		rotation = linear_velocity.angle()

func _on_body_entered(body: Node) -> void:
	# Ignore other enemy projectiles or the sub itself
	if body.is_in_group("enemy_projectiles") or body.is_in_group("submarine_boss"):
		return
	if body.is_in_group("enemies"):
		return

	# Damage the player
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(contact_damage)
			# Knock player back from missile
			var knockback := linear_velocity.normalized() * 250.0
			body.apply_central_impulse(knockback)

	# Destroy on anything solid (player, walls, floor)
	queue_free()
