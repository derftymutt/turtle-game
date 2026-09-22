extends CanvasLayer
class_name MouseCrosshair

## Mouse-mode aiming reticle. Created at runtime by TurtlePlayer, which owns
## it for its lifetime. Swaps the OS cursor for a pixel crosshair during live
## gameplay, and hands the OS cursor back whenever the tree is paused (every
## menu/popup/tutorial prompt pauses), mouse mode is off, or the gamepad is
## the active device. Dims while auto-fire is toggled off so the fire state is
## always readable at the aim point.

const _ARM_INNER := 2
const _ARM_OUTER := 5
const _COLOR := Color(1, 1, 1)
const _OUTLINE := Color(0, 0, 0, 0.8)
const _FIRE_OFF_ALPHA := 0.35

## Set by TurtlePlayer each frame.
var firing: bool = true:
	set(value):
		if firing != value:
			firing = value
			if _mark:
				_mark.modulate.a = 1.0 if firing else _FIRE_OFF_ALPHA

var _mark: Node2D


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mark = Node2D.new()
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	_mark.queue_redraw()


func _process(_delta: float) -> void:
	var active := GameSettings.mouse_aim_active() and not get_tree().paused
	_mark.visible = active
	var wanted := Input.MOUSE_MODE_HIDDEN if active else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	if active:
		_mark.position = get_viewport().get_mouse_position().floor()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _draw_mark() -> void:
	# Outline pass then fill pass, as 1px rects so it stays crisp at integer scale.
	for pass_color: Color in [_OUTLINE, _COLOR]:
		var grow := 1 if pass_color == _OUTLINE else 0
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			for i in range(_ARM_INNER, _ARM_OUTER + 1):
				var p := dir * i
				_mark.draw_rect(Rect2(p.x - grow, p.y - grow, 1 + grow * 2, 1 + grow * 2), pass_color)
		_mark.draw_rect(Rect2(-grow, -grow, 1 + grow * 2, 1 + grow * 2), pass_color)
