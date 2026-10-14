extends Node2D
class_name HdFlipperArt

## High-res stand-in for a flipper's AnimatedSprite2D (see HdArt), drawn as vector
## line art. It traces the flipper's collision capsule every frame, so instead of
## the pixel art's two frames (rest / extend) it swings smoothly — and what you see
## is exactly what the turtle hits. Added at runtime by FlipperBase.

const TOP := Color("#7fd04e")
const BOTTOM := Color("#5b6ee1")
const OUTLINE := Color("#15131f")
const SHINE := Color(1, 1, 1, 0.45)
const OUTLINE_WIDTH: float = 0.9
const TUFT_COUNT: int = 5

var shape_node: CollisionShape2D
var accent: Color = Color.WHITE
var _last_transform: Transform2D

func _process(_delta: float) -> void:
	if shape_node and shape_node.transform != _last_transform:
		_last_transform = shape_node.transform
		queue_redraw()

func _draw() -> void:
	if not shape_node or not shape_node.shape is CapsuleShape2D:
		return
	var capsule := shape_node.shape as CapsuleShape2D
	var r: float = capsule.radius
	var half: float = maxf(capsule.height * 0.5 - r, 0.0)  ## half-length of the straight part
	draw_set_transform_matrix(shape_node.transform)

	## The capsule's long axis is local y. Shade from the side facing world-up.
	var up: Vector2 = Vector2.UP.rotated(-shape_node.global_rotation)
	var pts := PackedVector2Array()
	var steps: int = 10
	for i in steps + 1:  ## bottom cap (+y)
		var t: float = PI * i / steps
		pts.append(Vector2(r * cos(t), half + r * sin(t)))
	for i in steps + 1:  ## top cap (-y)
		var t: float = PI + PI * i / steps
		pts.append(Vector2(r * cos(t), -half + r * sin(t)))
	var colors := PackedColorArray()
	for p in pts:
		var k: float = clampf(0.5 + p.dot(up) / (2.0 * r), 0.0, 1.0)
		colors.append(BOTTOM.lerp(TOP, k))
	draw_polygon(pts, colors)

	## Grass tufts in the input's accent colour along the upper edge (which button
	## flips it), drawn before the outline so it covers their roots.
	var side: float = signf(up.x) if absf(up.x) > 0.01 else 1.0
	for i in TUFT_COUNT:
		var y: float = lerpf(-half - r * 0.3, half + r * 0.3, (i + 0.5) / TUFT_COUNT)
		var lean: float = -0.9 if i % 2 == 0 else 0.9
		var blade := PackedVector2Array([Vector2(side * (r - 1.5), y - 1.4),
				Vector2(side * (r + 2.4), y + lean), Vector2(side * (r - 1.5), y + 1.4)])
		draw_colored_polygon(blade, accent)

	## Shine along the upper side, then the outline on top of everything.
	draw_line(Vector2(side * r * 0.45, -half), Vector2(side * r * 0.45, half), SHINE, 0.9)
	pts.append(pts[0])
	draw_polyline(pts, OUTLINE, OUTLINE_WIDTH)
