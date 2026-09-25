extends Node
class_name EnemyShock

## Multi-Beam shock. Attached as a child of an invincible enemy (crocodile,
## sea urchin, …) for a fixed time, during which the enemy:
##   - is frozen in place, using the same conventions Time Freeze uses
##     (RigidBody2D.freeze + physics/process callbacks off), so it doesn't move
##     other than the shock jitter below;
##   - can't hurt the turtle (its DamageArea stops monitoring — both enemy base
##     classes only deal contact damage through that area);
##   - jitters, flickers yellow and crackles with arcs.
## Everything is restored when the time is up. Shocking an already-shocked
## enemy just resets its timer.
##
## Call EnemyShock.apply(enemy, duration) — BaseEnemy and BaseEnemyStatic wrap
## it as shock().

const NODE_NAME: String = "EnemyShock"
const JITTER: float = 2.5
const ARC_INTERVAL: float = 0.06
const SHOCK_COLOR: Color = Color(1.0, 0.95, 0.2)

var _enemy: Node2D = null
var _sprite: Node2D = null
var _sprite_home: Vector2 = Vector2.ZERO
var _sprite_modulate: Color = Color.WHITE
var _sprite_speed_scale: float = 1.0
var _was_frozen: bool = false
var _remaining: float = 0.0
var _arc_timer: float = 0.0
var _arc_radius: float = 12.0
var _arc: Line2D = null

static func apply(enemy: Node2D, duration: float) -> void:
	var existing := enemy.get_node_or_null(NODE_NAME) as EnemyShock
	if existing:
		existing._remaining = duration
		return
	var shock := EnemyShock.new()
	shock.name = NODE_NAME
	enemy.add_child(shock)
	shock._begin(enemy, duration)

func _begin(enemy: Node2D, duration: float) -> void:
	_enemy = enemy
	_remaining = duration

	if enemy is RigidBody2D:
		var rb := enemy as RigidBody2D
		_was_frozen = rb.freeze
		rb.linear_velocity = Vector2.ZERO
		rb.angular_velocity = 0.0
		rb.set_deferred("freeze", true)
	_hold_still()

	var area = enemy.get("damage_area")
	if area is Area2D:
		(area as Area2D).set_deferred("monitoring", false)

	var sprite = enemy.get("sprite")
	if sprite is Node2D:
		_sprite = sprite
		_sprite_home = _sprite.position
		_sprite_modulate = _sprite.modulate
		if _sprite is AnimatedSprite2D:
			var animated := _sprite as AnimatedSprite2D
			_sprite_speed_scale = animated.speed_scale
			animated.speed_scale = 0.0  # 0 pauses the animation on its current frame
		_arc_radius = _measure_radius()

	_arc = Line2D.new()
	_arc.width = 1.5
	_arc.default_color = SHOCK_COLOR
	_arc.z_as_relative = false
	_arc.z_index = 20
	enemy.add_child(_arc)

func _process(delta: float) -> void:
	if not is_instance_valid(_enemy):
		queue_free()
		return
	# Time Freeze's thaw calls set_physics_process(true) on everything it
	# froze, which would un-stun a crocodile mid-shock — re-assert every frame.
	_hold_still()
	# The shock timer stops with the rest of the world during Time Freeze.
	if not AlienTechManager.time_freeze_active:
		_remaining -= delta
		if _remaining <= 0.0:
			_finish()
			return
	_jitter(delta)

func _hold_still() -> void:
	_enemy.set_physics_process(false)
	_enemy.set_process(false)

func _jitter(delta: float) -> void:
	if _sprite and is_instance_valid(_sprite):
		_sprite.position = _sprite_home + Vector2(randf_range(-JITTER, JITTER), randf_range(-JITTER, JITTER))
		var flash := (sin(Time.get_ticks_msec() * 0.05) + 1.0) * 0.5
		_sprite.modulate = SHOCK_COLOR.lerp(Color.WHITE, flash)
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = ARC_INTERVAL
		_redraw_arc()

## A jagged bolt of random points inside the enemy's footprint, re-rolled
## every ARC_INTERVAL.
func _redraw_arc() -> void:
	var points := PackedVector2Array()
	for i in 5:
		points.append(Vector2.from_angle(randf() * TAU) * randf_range(_arc_radius * 0.2, _arc_radius))
	_arc.points = points

func _measure_radius() -> float:
	if _sprite is AnimatedSprite2D:
		var animated := _sprite as AnimatedSprite2D
		if animated.sprite_frames and animated.sprite_frames.has_animation(animated.animation):
			var texture := animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
			if texture:
				return clampf(maxf(texture.get_width(), texture.get_height()) * 0.5, 8.0, 40.0)
	return _arc_radius

func _finish() -> void:
	if is_instance_valid(_enemy):
		if _enemy is RigidBody2D:
			(_enemy as RigidBody2D).set_deferred("freeze", _was_frozen)
		_enemy.set_physics_process(true)
		_enemy.set_process(true)
		var area = _enemy.get("damage_area")
		if area is Area2D:
			(area as Area2D).set_deferred("monitoring", true)
		if _sprite and is_instance_valid(_sprite):
			_sprite.position = _sprite_home
			_sprite.modulate = _sprite_modulate
			if _sprite is AnimatedSprite2D:
				(_sprite as AnimatedSprite2D).speed_scale = _sprite_speed_scale
	if _arc and is_instance_valid(_arc):
		_arc.queue_free()
	queue_free()
