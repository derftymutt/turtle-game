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
## The secret-level entrance glowing at the apex (open_portal())
var _portal_open: bool = false
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

## Global point on the centre line of the whole seven-stripe band — the line
## the secret-entrance currents ride. `t` as in stripe_point().
func band_point(t: float) -> Vector2:
	return _ellipse_point(radius - Vector2.ONE * STRIPE_WIDTH * STRIPE_COUNT * 0.5, t)

## Top of the band — where the secret entrance opens.
func apex() -> Vector2:
	return band_point(0.5)

## Full width of the painted band.
func band_width() -> float:
	return STRIPE_WIDTH * STRIPE_COUNT

## Lights the pulsing secret-level entrance at the apex.
func open_portal() -> void:
	_portal_open = true

## Stripe `stripe` painted up to `progress` (0–1) from its left or right end.
func paint(stripe: int, progress: float, from_left: bool) -> void:
	_progress[stripe] = clampf(progress, 0.0, 1.0)
	_from_left[stripe] = from_left
	queue_redraw()

## Breaks the rainbow apart and frees it.
func dissolve() -> void:
	if _dissolve >= 0.0:
		return
	_dissolve = 0.0

func _process(delta: float) -> void:
	if _portal_open:
		queue_redraw()  # portal pulse
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
	if _portal_open:
		_draw_portal()

## Pulsing white glow at the apex: rings breathing out over a solid core, no
## rest beat, so it reads at any instant.
func _draw_portal() -> void:
	var p := apex()
	var wave := (sin(Time.get_ticks_msec() * 0.001 * TAU * 1.5) + 1.0) * 0.5
	var r := band_width() * 0.5
	draw_circle(p, r * (0.9 + 0.3 * wave), Color(1.0, 1.0, 1.0, 0.25 + 0.2 * wave))
	draw_circle(p, r * 0.6, Color(1.0, 1.0, 1.0, 0.6))
	draw_circle(p, r * (0.25 + 0.1 * wave), Color.WHITE)
