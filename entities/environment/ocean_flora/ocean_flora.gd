extends StaticBody2D
class_name OceanFlora

signal flora_destroyed(position: Vector2, reveals_piece: bool)

@export var max_health: float = 30.0
@export var reveals_tech_piece: bool = false
@export var tech_piece_scene: PackedScene = null
@export var flash_duration: float = 0.15
@export var death_rise: float = 40.0

var current_health: float = 0.0
var _is_dead: bool = false
var _sprite: AnimatedSprite2D = null
var _is_flashing: bool = false

func _ready():
	current_health = max_health
	add_to_group("ocean_flora")
	add_to_group("shootable")
	_sprite = get_node_or_null("AnimatedSprite2D")
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation("default"):
		_sprite.play("default")

func take_damage(amount: float):
	if _is_dead:
		return
	current_health -= amount
	if current_health <= 0.0:
		_die()
	else:
		_flash_damage()

func _flash_damage():
	if _is_flashing or not _sprite:
		return
	_is_flashing = true
	_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	await get_tree().create_timer(flash_duration).timeout
	if is_instance_valid(self) and _sprite:
		_sprite.modulate = Color.WHITE
	_is_flashing = false

func _die():
	if _is_dead:
		return
	_is_dead = true
	set_deferred("collision_layer", 0)
	flora_destroyed.emit(global_position, reveals_tech_piece)

	if reveals_tech_piece and tech_piece_scene:
		var piece = tech_piece_scene.instantiate()
		get_parent().add_child(piece)
		piece.global_position = global_position + Vector2(randf_range(-8, 8), -10)
		piece.apply_central_impulse(Vector2(randf_range(-50, 50), -120))

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position:y",
		global_position.y - death_rise, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.3, 0.0), 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
