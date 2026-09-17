extends Control

## Subtle twinkling starfield drawn behind the alien tech card's content —
## a handful of small dots that fade in and out at randomized, slow,
## staggered paces so it reads as cosmic ambience rather than a distracting
## light show. Purely decorative: sits as the first child of the outer
## PanelContainer (see alien_tech_selection_screen.tscn) so it draws behind
## the MarginContainer holding the actual text/slots.

const _STAR_COUNT: int = 30
const _STAR_RADIUS_RANGE := Vector2(0.6, 1.6)
const _STAR_ALPHA_RANGE := Vector2(0.12, 0.7)
const _STAR_PERIOD_RANGE := Vector2(1.5, 4.0)
const _STAR_COLOR := Color(1.0, 1.0, 1.0)

var _stars: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in _STAR_COUNT:
		_stars.append({
			"pos": Vector2(randf(), randf()), # normalized 0..1 of this control's size
			"radius": randf_range(_STAR_RADIUS_RANGE.x, _STAR_RADIUS_RANGE.y),
			"period": randf_range(_STAR_PERIOD_RANGE.x, _STAR_PERIOD_RANGE.y),
			"phase": randf() * TAU,
		})


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for star: Dictionary in _stars:
		var twinkle := (sin(t * TAU / star.period + star.phase) + 1.0) * 0.5
		var alpha := lerpf(_STAR_ALPHA_RANGE.x, _STAR_ALPHA_RANGE.y, twinkle)
		var pos := Vector2(star.pos.x * size.x, star.pos.y * size.y)
		draw_circle(pos, star.radius, Color(_STAR_COLOR.r, _STAR_COLOR.g, _STAR_COLOR.b, alpha))
