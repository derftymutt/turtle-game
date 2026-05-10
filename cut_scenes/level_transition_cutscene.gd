# level_transition_cutscene.gd
# Between-levels cut scene (loaded as a full-screen scene via change_scene_to_file).
# Sequence: UFO assembled flies across black screen → splits into halves → turtle
# ejects upward → all elements plunge off the bottom → next level loads.
extends Node

const VP_W: float = 640.0
const VP_H: float = 360.0
const UFO_TRAVEL_X: float = VP_W * 0.55   # x where the UFO stops and splits
const UFO_Y: float = VP_H * 0.50           # vertical position of the UFO

var _bg: ColorRect
var _ufo: Sprite2D
var _ufo_left: Sprite2D
var _ufo_right: Sprite2D
var _turtle: Sprite2D
var _canvas: CanvasLayer

func _ready() -> void:
	_build_scene()
	_run.call_deferred()

func _build_scene() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.size = Vector2(VP_W, VP_H)
	_bg.position = Vector2.ZERO
	_canvas.add_child(_bg)

	_ufo = Sprite2D.new()
	_ufo.texture = load("res://cut_scenes/sprites/ufo_assembled.png")
	_ufo.position = Vector2(-80.0, VP_H + 30.0)  # lower-left, off-screen
	_canvas.add_child(_ufo)

	_ufo_left = Sprite2D.new()
	_ufo_left.texture = load("res://cut_scenes/sprites/ufo_split_left.png")
	_ufo_left.visible = false
	_canvas.add_child(_ufo_left)

	_ufo_right = Sprite2D.new()
	_ufo_right.texture = load("res://cut_scenes/sprites/ufo_split_right.png")
	_ufo_right.visible = false
	_canvas.add_child(_ufo_right)

	_turtle = Sprite2D.new()
	_turtle.texture = load("res://cut_scenes/sprites/turtle_all_limbs.png")
	_turtle.visible = false
	_canvas.add_child(_turtle)

func _run() -> void:
	await _fly_in()
	await _split()
	await get_tree().create_timer(0.6).timeout
	await _plunge()
	LevelManager.load_next_level()

func _fly_in() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_ufo, "position:x", UFO_TRAVEL_X, 0.85)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_ufo, "position:y", UFO_Y, 0.85)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _split() -> void:
	var cx: float = _ufo.position.x
	var cy: float = _ufo.position.y
	_ufo_left.position = Vector2(cx - 8.0, cy)
	_ufo_right.position = Vector2(cx + 8.0, cy)
	_turtle.position = Vector2(cx, cy - 30.0)

	_ufo.visible = false
	_ufo_left.visible = true
	_ufo_right.visible = true
	_turtle.visible = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_ufo_left, "position:x", cx - 44.0, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_ufo_right, "position:x", cx + 44.0, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_turtle, "position:y", cy - 50.0, 0.28)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

func _plunge() -> void:
	var target_y: float = VP_H + 140.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_ufo_left, "position:y", target_y, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_ufo_right, "position:y", target_y, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_turtle, "position:y", target_y, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
