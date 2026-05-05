extends RigidBody2D
class_name TrashCluster

## Dense ocean debris cluster concealing an alien tech piece.
## Shoot it several times and it breaks into 4 smaller pieces.
## Destroy all 4 pieces to reveal the tech.

const _SMALL_PIECE_SCENE = preload("res://entities/collectibles/trash_cluster/trash_cluster_piece.tscn")
const _TECH_PIECE_SCENE  = preload("res://entities/collectibles/alien_tech_piece/alien_tech_piece.tscn")

@export var max_hits: int = 3
@export var drift_speed: float = -38.0   # Negative = left, positive = right
@export var rotation_speed: float = 0.25
@export var max_lifetime: float = 30.0
@export var max_y: float = 10000.0       # World-space y ceiling; set by spawner

var current_hits: int = 0
var is_destroyed: bool = false
var visual_node: AnimatedSprite2D = null
var _age: float = 0.0
var _wave_timer: float = 0.0
var _wave_phase: float = 0.0   # Randomised per-instance so each cluster moves differently
var _flash_timer: float = 0.0
var _flash_duration: float = 0.12
var _is_flashing: bool = false

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.4
	angular_damp = 0.3
	mass = 3.0
	z_index = 50
	add_to_group("trash_clusters")

	_wave_phase = randf() * TAU

	visual_node = get_node_or_null("AnimatedSprite2D")

	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("TrashCluster: No Area2D found!")

	linear_velocity = Vector2(drift_speed, 0)

func _physics_process(delta: float):
	if is_destroyed:
		return

	_age += delta
	if _age >= max_lifetime:
		_despawn_quietly()
		return

	_wave_timer += delta
	var t = _wave_timer + _wave_phase

	# Organic path: three overlapping sine waves at different frequencies.
	# The sum feels like gentle ocean-current turbulence rather than a regular oscillation.
	var wave_y = (
		sin(t * 0.35) * 18.0 +   # slow broad drift
		sin(t * 1.05) * 9.0  +   # medium ripple
		sin(t * 2.6)  * 4.0      # small surface chop
	)
	# Subtle horizontal variation so it doesn't track a perfectly straight line
	var wave_x = sin(t * 0.55 + 1.2) * 4.0 + sin(t * 1.7) * 2.0

	linear_velocity = Vector2(drift_speed + wave_x, wave_y)
	angular_velocity = rotation_speed

	if global_position.y > max_y:
		global_position.y = max_y
		if linear_velocity.y > 0.0:
			linear_velocity.y = 0.0

	if _is_flashing:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_is_flashing = false
			if visual_node:
				visual_node.modulate = Color.WHITE

func _on_area_body_entered(body: Node2D):
	if is_destroyed:
		return
	if body.is_in_group("bullets"):
		_take_hit()
		return
	if body.has_method("set_velocity") and body.collision_layer == 8:
		_take_hit()

func _take_hit():
	if is_destroyed:
		return
	current_hits += 1
	_flash_damage()
	if current_hits >= max_hits:
		_break_apart()

func _flash_damage():
	if visual_node:
		visual_node.modulate = Color(4.0, 4.0, 4.0, 1.0)
	_is_flashing = true
	_flash_timer = _flash_duration

func _break_apart():
	if is_destroyed:
		return
	is_destroyed = true
	freeze = true

	var break_pos  = global_position
	var parent_node = get_parent()
	var tech_scene  = _TECH_PIECE_SCENE

	# Shared destruction counter shared by all 4 pieces via closure capture
	var remaining = {"count": 4}

	for i in range(4):
		var piece = _SMALL_PIECE_SCENE.instantiate()
		parent_node.add_child(piece)
		piece.global_position = break_pos

		# Scatter in evenly-spaced directions with a bit of random jitter
		var angle = (float(i) / 4.0) * TAU + randf_range(-0.35, 0.35)
		piece.apply_central_impulse(Vector2.from_angle(angle) * randf_range(90, 200))

		# When this piece is shot, decrement the counter.
		# If it reaches zero, all 4 were cleared — spawn the tech piece.
		piece.all_destroyed_callback = func(pos: Vector2):
			remaining.count -= 1
			if remaining.count <= 0 and is_instance_valid(parent_node):
				var tech = tech_scene.instantiate()
				parent_node.add_child(tech)
				tech.global_position = pos
				tech.apply_central_impulse(Vector2(randf_range(-60, 60), -120))

	_play_break_effect()

func _play_break_effect():
	var tween = create_tween()
	tween.set_parallel(true)
	if visual_node:
		tween.tween_property(visual_node, "modulate", Color(4.0, 4.0, 4.0, 1.0), 0.05)
	tween.tween_property(self, "scale", Vector2(2.2, 2.2), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.22).set_delay(0.08)
	tween.finished.connect(queue_free)

func _despawn_quietly():
	if is_destroyed:
		return
	is_destroyed = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.finished.connect(queue_free)
