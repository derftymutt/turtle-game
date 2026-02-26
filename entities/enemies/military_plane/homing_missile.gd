# homing_missile.gd
extends CharacterBody2D
class_name HomingMissile

## Homing missile fired by the military plane.
## Launches slow and dumb, then accelerates and steers toward the turtle.
## Uses CharacterBody2D — we own the movement entirely.
##
## Tuning guide:
##   initial_speed    — how sluggish it feels on launch
##   max_speed        — terminal velocity after acceleration
##   acceleration     — how quickly it ramps up (px/s²)
##   turn_speed       — steering tightness (rad/s); lower = wider, dodgeable arcs
##   tracking_delay   — seconds before homing activates (player warning window)

@export_group("Movement")
@export var initial_speed: float = 40.0
@export var max_speed: float = 260.0
@export var acceleration: float = 150.0
@export var turn_speed: float = 2.2
@export var tracking_delay: float = 0.6

@export_group("Damage & Lifetime")
@export var damage: float = 20.0
@export var lifetime: float = 2.0

var target: Node2D = null
var current_speed: float = 0.0
var age: float = 0.0


func _ready() -> void:
	# NOTE: Set in Inspector:
	#   Collision Layer: 4  (projectiles)
	#   Collision Mask:  player layer only
	add_to_group("plane_projectiles")

	target = get_tree().get_first_node_in_group("player")
	current_speed = initial_speed
	velocity = Vector2.DOWN * current_speed

	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()


func _physics_process(delta: float) -> void:
	age += delta

	# ── Acceleration ──────────────────────────────────────────────────────
	current_speed = move_toward(current_speed, max_speed, acceleration * delta)

	# ── Steering ──────────────────────────────────────────────────────────
	if age >= tracking_delay and target and is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		var current_dir := velocity.normalized()
		# Rotate current direction toward target, clamped by turn_speed
		var angle_diff: float = clamp(current_dir.angle_to(to_target), -1.0, 1.0)
		var new_dir := current_dir.rotated(angle_diff * turn_speed * delta)
		velocity = new_dir * current_speed
	else:
		# Pre-tracking: maintain launch direction at current speed
		velocity = velocity.normalized() * current_speed

	# Rotate sprite to face direction of travel
	if velocity.length() > 5.0:
		rotation = velocity.angle()

	var collision := move_and_collide(velocity * delta)
	if collision:
		var body := collision.get_collider()
		if body and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage)
		_explode(body != null and body.is_in_group("player"))


func _explode(hit_player: bool) -> void:
	set_physics_process(false)
	velocity = Vector2.ZERO

	var tween := create_tween()
	tween.set_parallel(true)
	if hit_player:
		tween.tween_property(self, "scale", Vector2.ONE * 2.0, 0.08)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.finished.connect(queue_free)
