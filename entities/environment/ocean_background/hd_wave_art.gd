extends Node2D
class_name HdWaveArt

## High-res stand-in for OceanBackground's WaveSurface (see HdArt): the water
## surface drawn as a smooth vector wave that rolls continuously instead of
## stepping through four frames. The crest height comes from world x, so side-by-
## side backgrounds (Level 6 has three) join seamlessly where they overlap.
##
## Geometry matches the pixel strip: WaveSurface is a centred 700x16 frame
## offset by (0, -5), i.e. local y -13..3; its fill meets OceanGradient below.

const WATER := Color("#0effff")
const CREST := Color("#639bff")
const FOAM := Color(1, 1, 1, 0.55)
const HALF_WIDTH: float = 350.0
const BOTTOM: float = 3.5
const BASE_Y: float = -6.5
const STEP: float = 2.0
## The pixel strip bobs through a 2 s cycle (8 frames at 4 fps).
const BOB_PERIOD: float = 2.0
const BOB_AMOUNT: float = 1.2

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _crest_y(world_x: float) -> float:
	var t: float = _time
	return (BASE_Y
		+ sin(t * TAU / BOB_PERIOD) * BOB_AMOUNT
		- 1.1 * sin(world_x * 0.045 + t * 0.7)
		- 0.6 * sin(world_x * 0.11 - t * 1.3)
		- 0.3 * sin(world_x * 0.23 + t * 2.1))

func _draw() -> void:
	var gx: float = global_position.x
	var crest := PackedVector2Array()
	var x: float = -HALF_WIDTH
	while x <= HALF_WIDTH:
		crest.append(Vector2(x, _crest_y(gx + x)))
		x += STEP
	var fill := crest.duplicate()
	fill.append(Vector2(HALF_WIDTH, BOTTOM))
	fill.append(Vector2(-HALF_WIDTH, BOTTOM))
	draw_colored_polygon(fill, WATER)
	var foam := PackedVector2Array()
	for p in crest:
		foam.append(p + Vector2(0.0, 1.3))
	draw_polyline(foam, FOAM, 0.5)
	draw_polyline(crest, CREST, 1.0)
