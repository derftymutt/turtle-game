extends Node2D
class_name RainbowArc

## The rainbow the freed rainbow fish paint across the sky: seven stacked
## half-ellipse stripes (red outermost) whose ends all rest on the ocean
## surface. Each stripe is painted progressively from whichever end its fish
## leapt out of. dissolve() breaks it up into nothing and frees it.
##
## Lives in level space with its origin at the level origin — `center` and
## stripe_point() are global positions.

const STRIPE_COUNT := 7
const STRIPE_WIDTH := 6.0
## Quads per stripe along the full arc
const SEGMENTS := 72
const DISSOLVE_TIME := 1.4

## Middle of the arc's base, on the ocean surface (global)
var center: Vector2 = Vector2.ZERO
## Outer edge half-width / height of the red stripe
var radius: Vector2 = Vector2(300.0, 150.0)
var colors: Array[Color] = []

var _progress: Array[float] = []
var _from_left: Array[bool] = []
var _dissolve: float = -1.0  # < 0 while intact
## Per-quad dissolve thresholds, so it breaks up in random patches
var _crumble: PackedFloat32Array = PackedFloat32Array()

func _init() -> void:
	for i in STRIPE_COUNT:
		_progress.append(0.0)
		_from_left.append(true)
	_crumble.resize(STRIPE_COUNT * SEGMENTS)
	for i in _crumble.size():
		_crumble[i] = randf()

func _ready() -> void:
	z_index = -1  # behind sky stars, debris and the airborne turtle
	top_level = true  # coordinates are global whatever the parent's transform
	global_position = Vector2.ZERO

## Global point on the centre line of `stripe`, `t` = 0 at the left end on
## the surface, 1 at the right end.
func stripe_point(stripe: int, t: float) -> Vector2:
	return _ellipse_point(_stripe_radius(stripe, 0.5), t)

## Stripe `stripe` painted up to `progress` (0–1) from its left or right end.
func paint(stripe: int, progress: float, from_left: bool) -> void:
	_progress[stripe] = clampf(progress, 0.0, 1.0)
	_from_left[stripe] = from_left
	queue_redraw()

func is_complete() -> bool:
	for p in _progress:
		if p < 1.0:
			return false
	return true

## Breaks the rainbow apart and frees it.
func dissolve() -> void:
	if _dissolve >= 0.0:
		return
	_dissolve = 0.0

func _process(delta: float) -> void:
	if _dissolve < 0.0:
		return
	_dissolve += delta / DISSOLVE_TIME
	modulate.a = clampf(1.5 - _dissolve * 1.5, 0.0, 1.0)
	queue_redraw()
	if _dissolve >= 1.0:
		queue_free()

## `edge` 0 = outer edge of the stripe, 1 = inner edge.
func _stripe_radius(stripe: int, edge: float) -> Vector2:
	return radius - Vector2.ONE * STRIPE_WIDTH * (stripe + edge)

func _ellipse_point(r: Vector2, t: float) -> Vector2:
	var ang := PI * (1.0 - t)
	return center + Vector2(cos(ang) * r.x, -sin(ang) * r.y)

func _draw() -> void:
	for stripe in STRIPE_COUNT:
		var progress := _progress[stripe]
		if progress <= 0.0:
			continue
		var t0 := 0.0 if _from_left[stripe] else 1.0 - progress
		var t1 := progress if _from_left[stripe] else 1.0
		var outer := _stripe_radius(stripe, 0.0)
		var inner := _stripe_radius(stripe, 1.0)
		var color := colors[stripe] if stripe < colors.size() else Color.WHITE
		for seg in SEGMENTS:
			var a := float(seg) / SEGMENTS
			var b := float(seg + 1) / SEGMENTS
			a = maxf(a, t0)
			b = minf(b, t1)
			if b - a < 0.0005:
				continue
			if _dissolve >= 0.0 and _crumble[stripe * SEGMENTS + seg] < _dissolve * 1.3:
				continue
			# Slight overlap with the next stripe so no gap shows between them
			var quad := PackedVector2Array([
				_ellipse_point(outer + Vector2.ONE * 0.5, a),
				_ellipse_point(outer + Vector2.ONE * 0.5, b),
				_ellipse_point(inner, b),
				_ellipse_point(inner, a),
			])
			draw_colored_polygon(quad, color)
