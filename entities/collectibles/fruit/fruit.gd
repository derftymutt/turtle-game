extends BaseCollectible
class_name Fruit

## Bonus rainbow level fruit — spawned by RainbowBonusLevel when the turtle
## bounces off a bumper, collected by touch. Hovers and bobs in place (no
## gravity). Worth BASE_POINTS × the colour band's level value (red 7 …
## violet 1); the points are tallied by the level and paid out on the summary
## screen rather than added to the score on pickup.
##
## The sheet holds 2 frames per fruit side by side (16×16 each); add a fruit
## by widening the sheet — the type is picked at random from what's there.

signal fruit_collected(fruit: Fruit)

const BASE_POINTS := 50
const _SHEET = preload("res://entities/collectibles/fruit/sprites/fruit.png")
const _FRAME_SIZE := 16
const _FRAMES_PER_FRUIT := 2

## Colour band it was spawned in (0 = red … 6 = violet)
var band: int = 0
## Which fruit on the sheet (random if left at -1)
var fruit_type: int = -1

static var _frames_cache: Dictionary = {}

## Call before adding to the tree.
func setup(band_index: int, level_value: int) -> void:
	band = band_index
	point_value = BASE_POINTS * level_value

static func fruit_type_count() -> int:
	return maxi(1, _SHEET.get_width() / (_FRAME_SIZE * _FRAMES_PER_FRUIT))

func _collectible_ready() -> void:
	# Hovers in place like a sky star
	gravity_scale = 0.0
	linear_damp = 100.0
	angular_damp = 100.0
	linear_velocity = Vector2.ZERO
	bob_amount = 2.0
	if fruit_type < 0:
		fruit_type = randi() % fruit_type_count()
	var sprite := $AnimatedSprite2D as AnimatedSprite2D
	sprite.sprite_frames = _frames_for(fruit_type)
	sprite.play("default")
	# Pop in
	sprite.scale = Vector2.ZERO
	create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _collectible_physics_process(_delta: float) -> void:
	if linear_velocity.length_squared() > 1.0:
		linear_velocity = Vector2.ZERO
	if angular_velocity != 0.0:
		angular_velocity = 0.0

func _on_collected(collector) -> void:
	GameManager.spawn_floating_score(global_position, point_value)
	fruit_collected.emit(self)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

static func _frames_for(type: int) -> SpriteFrames:
	if _frames_cache.has(type):
		return _frames_cache[type]
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 3.0)
	frames.set_animation_loop("default", true)
	for f in _FRAMES_PER_FRUIT:
		var atlas := AtlasTexture.new()
		atlas.atlas = _SHEET
		atlas.region = Rect2((type * _FRAMES_PER_FRUIT + f) * _FRAME_SIZE, 0, _FRAME_SIZE, _FRAME_SIZE)
		frames.add_frame("default", atlas)
	_frames_cache[type] = frames
	return frames
