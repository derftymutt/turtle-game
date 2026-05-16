extends RigidBody2D
class_name TrashClusterPiece

## Small debris piece that breaks off a TrashCluster.

const _SFX_SHOOT_TRASH = preload("res://assets/sounds/sfx/shoot trash_1.wav")
## Sinks to the bottom with sway. Destroying all 4 from a cluster reveals
## an alien tech piece via the all_destroyed_callback.

var all_destroyed_callback: Callable = Callable()

@export var sink_force: float = 22.0
@export var sway_amplitude: float = 20.0
@export var max_lifetime: float = 45.0

var is_destroyed: bool = false
var visual_node: AnimatedSprite2D = null
var _age: float = 0.0
var _sway_timer: float = 0.0
var _sway_freq: float = 1.0
var _flash_timer: float = 0.0
var _flash_duration: float = 0.10
var _is_flashing: bool = false
var _hud = null

func _ready():
	gravity_scale = 0.0
	linear_damp = 1.5
	angular_damp = 0.8
	mass = 0.6
	z_index = 50
	add_to_group("trash_cluster_pieces")

	# Each piece has its own sway rhythm
	_sway_timer = randf() * TAU
	_sway_freq = randf_range(0.5, 1.6)

	visual_node = get_node_or_null("AnimatedSprite2D")
	if visual_node:
		# Start at a random animation frame so pieces look varied
		visual_node.frame = randi() % 4

	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)

	_hud = get_tree().get_first_node_in_group("hud")

func _physics_process(delta: float):
	if is_destroyed:
		return

	_age += delta
	if _age >= max_lifetime:
		_despawn_quietly()
		return

	_sway_timer += delta

	# Sink downward + ocean-current sway
	apply_central_force(Vector2(
		sin(_sway_timer * _sway_freq) * sway_amplitude,
		sink_force
	))

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
		_destroy()
		return
	if body.has_method("set_velocity") and body.collision_layer == 8:
		_destroy()

func _destroy():
	if is_destroyed:
		return
	is_destroyed = true
	freeze = true
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _SFX_SHOOT_TRASH
	sfx.volume_db = -10.0
	get_parent().add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

	if _hud:
		_hud.add_score(20)
	GameManager.spawn_floating_score(global_position, 20)

	# Notify the shared tracker — tech piece may spawn from here
	if all_destroyed_callback.is_valid():
		all_destroyed_callback.call(global_position)

	_play_destruction_effect()

func _play_destruction_effect():
	var tween = create_tween()
	tween.set_parallel(true)
	if visual_node:
		tween.tween_property(visual_node, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.05)
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.05)
	tween.finished.connect(queue_free)

func _despawn_quietly():
	if is_destroyed:
		return
	is_destroyed = true
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.finished.connect(queue_free)
