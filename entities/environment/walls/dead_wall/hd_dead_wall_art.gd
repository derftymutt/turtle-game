extends Node2D
class_name HdDeadWallArt

## High-res stand-in for a DeadWall's sprite (see HdArt), drawn as vector line art
## so it works at every angle and length — including ones with no pixel art. Added
## at runtime by DeadWall; geometry mirrors the wall's collision rectangle.

const FILL := Color("#5b6ee1")
const HIGHLIGHT := Color("#8fa0f5")
const OUTLINE := Color("#99e550")
const CHARGE := Color("#fbf236")
const OUTLINE_WIDTH: float = 1.0
const CORNER_RADIUS: float = 3.0
## Charge shimmer: game units per second the yellow dashes travel along the edges.
const CHARGE_SPEED: float = 90.0
const CHARGE_DASH: float = 18.0

var _length: float = 64.0
var _thickness: float = 8.0
var _angle: float = 0.0
## Seconds into the fast-charge shimmer, or < 0 when the wall isn't charging.
var charge_time: float = -1.0:
	set(value):
		charge_time = value
		queue_redraw()

func setup(length: float, thickness: float, angle_degrees: float) -> void:
	_length = length
	_thickness = thickness
	_angle = deg_to_rad(angle_degrees)
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _angle)
	var hl: float = _length * 0.5
	var ht: float = _thickness * 0.5
	var outline: PackedVector2Array = _rounded_rect(hl, ht, CORNER_RADIUS)
	draw_colored_polygon(outline, FILL)
	var inset: float = ht - 1.7
	draw_line(Vector2(-hl + CORNER_RADIUS, -inset), Vector2(hl - CORNER_RADIUS, -inset), HIGHLIGHT, 1.0)
	outline.append(outline[0])
	draw_polyline(outline, OUTLINE, OUTLINE_WIDTH)
	if charge_time >= 0.0:
		_draw_charge_dash(hl, -ht, 1.0)
		_draw_charge_dash(hl, ht, -1.0)

## A yellow dash running along one long edge (dir +1 = toward +x).
func _draw_charge_dash(hl: float, y: float, dir: float) -> void:
	var run: float = _length + CHARGE_DASH
	var head: float = fmod(charge_time * CHARGE_SPEED, run) - CHARGE_DASH * 0.5
	var a: float = clampf(head - CHARGE_DASH * 0.5, 0.0, _length) - hl
	var b: float = clampf(head + CHARGE_DASH * 0.5, 0.0, _length) - hl
	if b - a < 0.5:
		return
	if dir < 0.0:
		var t: float = a
		a = -b
		b = -t
	var lo: float = -hl + CORNER_RADIUS
	var hi: float = hl - CORNER_RADIUS
	a = clampf(a, lo, hi)
	b = clampf(b, lo, hi)
	draw_line(Vector2(a, y), Vector2(b, y), Color(CHARGE, 0.35), 3.2)
	draw_line(Vector2(a, y), Vector2(b, y), CHARGE, 1.4)

func _rounded_rect(hl: float, ht: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners: Array[Vector2] = [Vector2(hl - r, -ht + r), Vector2(hl - r, ht - r),
			Vector2(-hl + r, ht - r), Vector2(-hl + r, -ht + r)]
	var steps: int = 6
	for i in corners.size():
		var start: float = -PI * 0.5 + i * PI * 0.5
		for s in steps + 1:
			var t: float = start + PI * 0.5 * s / steps
			pts.append(corners[i] + Vector2(cos(t), sin(t)) * r)
	return pts
