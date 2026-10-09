extends CanvasLayer
class_name WorkshopPointer

## Arrow at the screen edge pointing to the UFO Workshop while it is off-screen
## (UFOWorkshop.offscreen_pointer). Added as a child of the workshop, so it goes
## when the workshop does. Gold and pulsing while a piece is being carried,
## dimmer otherwise.

## Distance kept from the screen edges; the top is larger to clear the HUD bar.
const _MARGIN: float = 14.0
const _TOP_MARGIN: float = 40.0
const _SIZE: float = 7.0
const _CARRY_COLOR := Color(1.0, 0.8, 0.0, 1.0)
const _IDLE_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const _OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)

var _arrow: Node2D
var _direction: Vector2 = Vector2.RIGHT
var _pulse: float = 0.0

func _ready() -> void:
	layer = 5
	_arrow = Node2D.new()
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)

func _process(delta: float) -> void:
	var workshop := get_parent() as Node2D
	if workshop == null:
		return
	var screen: Rect2 = get_viewport().get_visible_rect()
	var target: Vector2 = get_viewport().get_canvas_transform() * workshop.global_position
	if screen.has_point(target):
		_arrow.visible = false
		return

	var inner := Rect2(screen.position + Vector2(_MARGIN, _TOP_MARGIN),
			screen.size - Vector2(_MARGIN * 2.0, _TOP_MARGIN + _MARGIN))
	var at := Vector2(clampf(target.x, inner.position.x, inner.end.x),
			clampf(target.y, inner.position.y, inner.end.y))
	_direction = (target - at).normalized()
	_pulse += delta * 6.0
	_arrow.visible = true
	_arrow.position = at
	# Fades with the workshop while it hops between spots
	_arrow.modulate.a = workshop.modulate.a
	_arrow.queue_redraw()

func _draw_arrow() -> void:
	var carrying: bool = GameManager.is_carrying_piece
	var size: float = _SIZE * (1.0 + 0.25 * sin(_pulse)) if carrying else _SIZE
	var side: Vector2 = _direction.orthogonal()
	var points := PackedVector2Array([
		_direction * size,
		-_direction * size * 0.6 + side * size * 0.8,
		-_direction * size * 0.6 - side * size * 0.8,
	])
	_arrow.draw_colored_polygon(points, _CARRY_COLOR if carrying else _IDLE_COLOR)
	points.append(points[0])
	_arrow.draw_polyline(points, _OUTLINE_COLOR, 1.0)
