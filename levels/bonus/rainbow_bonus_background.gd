@tool
extends Node2D
class_name RainbowBonusBackground

## The inside of the rainbow: one screen-tall band per colour, red at the top
## down to violet, in lightened rainbow-fish colours with twinkling sparkles
## and slow drifting shimmer streaks. Draws in the editor too, so the bands
## show while laying out the level.
##
## Origin = top-centre of the red band; bands run downward, each
## `screen_size.y` tall and `screen_size.x` wide.

@export var screen_size: Vector2 = Vector2(640, 360)
## How far each colour is lifted toward white (0 = the fish colours as-is)
@export_range(0.0, 1.0) var lighten: float = 0.45
## Extra lift at the top of each band, fading to none at its bottom
@export_range(0.0, 1.0) var band_gradient: float = 0.12
@export var sparkles_per_screen: int = 70
@export var shimmer_streaks_per_screen: int = 3
## Changes the sparkle layout
@export var sparkle_seed: int = 7

## Pixel sparkles: {pos, phase, rate, big}
var _sparkles: Array[Dictionary] = []
## Diagonal light streaks: {x, y, speed, length}
var _streaks: Array[Dictionary] = []

func _ready() -> void:
	z_index = -10
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sparkle_seed
	var count := RainbowFish.COLORS.size()
	var half_w := screen_size.x * 0.5
	_sparkles.clear()
	for i in sparkles_per_screen * count:
		_sparkles.append({
			"pos": Vector2(rng.randf_range(-half_w, half_w), rng.randf_range(0.0, screen_size.y * count)).floor(),
			"phase": rng.randf() * TAU,
			"rate": rng.randf_range(0.6, 2.2),
			"big": rng.randf() < 0.2,
		})
	_streaks.clear()
	for i in shimmer_streaks_per_screen * count:
		_streaks.append({
			"x": rng.randf_range(-half_w, half_w),
			"y": rng.randf_range(0.0, screen_size.y * count),
			"speed": rng.randf_range(10.0, 25.0),
			"length": rng.randf_range(60.0, 140.0),
		})

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var count := RainbowFish.COLORS.size()
	var half_w := screen_size.x * 0.5
	var t := Time.get_ticks_msec() * 0.001

	for i in count:
		var base: Color = RainbowFish.COLORS[i].lerp(Color.WHITE, lighten)
		var top_color := base.lerp(Color.WHITE, band_gradient)
		var y0 := screen_size.y * i
		var y1 := y0 + screen_size.y
		draw_polygon(
			PackedVector2Array([Vector2(-half_w, y0), Vector2(half_w, y0), Vector2(half_w, y1), Vector2(-half_w, y1)]),
			PackedColorArray([top_color, top_color, base, base]))

	# Shimmer: faint diagonal streaks drifting up and to the right
	var height := screen_size.y * count
	for streak in _streaks:
		var drift: float = fmod(streak.y - t * streak.speed, height)
		if drift < 0.0:
			drift += height
		var x: float = fposmod(streak.x + t * streak.speed * 0.5 + half_w, screen_size.x) - half_w
		var len: float = streak.length
		var a := Vector2(x, drift)
		var b := a + Vector2(len, -len) * 0.5
		draw_line(a, b, Color(1, 1, 1, 0.18), 6.0)
		draw_line(a + Vector2(8, 0), b + Vector2(8, 0), Color(1, 1, 1, 0.1), 3.0)

	# Sparkles: sharp twinkle (sine raised to a power), big ones get a cross
	for s in _sparkles:
		var wave: float = (sin(t * TAU * s.rate * 0.5 + s.phase) + 1.0) * 0.5
		var alpha := pow(wave, 4.0)
		if alpha < 0.05:
			continue
		var c := Color(1, 1, 1, alpha)
		var p: Vector2 = s.pos
		draw_rect(Rect2(p, Vector2.ONE), c)
		if s.big:
			c.a *= 0.7
			draw_rect(Rect2(p + Vector2(-2, 0), Vector2(5, 1)), c)
			draw_rect(Rect2(p + Vector2(0, -2), Vector2(1, 5)), c)
