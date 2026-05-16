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
var _level_label: Label

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

	var next_level: int = LevelManager.current_level_number + 1
	_level_label = Label.new()
	_level_label.text = "Level %d" % next_level
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.size = Vector2(VP_W, 80.0)
	_level_label.position = Vector2(0.0, VP_H * 0.5 - 40.0)
	_level_label.pivot_offset = Vector2(VP_W * 0.5, 40.0)
	_level_label.scale = Vector2(0.8, 0.8)
	_level_label.modulate.a = 0.0
	_level_label.add_theme_font_override("font", load("res://assets/fonts/BoldPixels.ttf"))
	_level_label.add_theme_font_size_override("font_size", 52)
	_level_label.add_theme_color_override("font_color", Color.WHITE)
	_canvas.add_child(_level_label)

func _run() -> void:
	await _fly_in()
	await _split()
	await get_tree().create_timer(0.6).timeout
	await _plunge()
	await get_tree().create_timer(0.3).timeout
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

	# Pre-split: UFO shakes under stress before breaking.
	var shake := create_tween()
	for i in 8:
		shake.tween_property(_ufo, "position",
			Vector2(cx + randf_range(-6.0, 6.0), cy + randf_range(-4.0, 4.0)), 0.05)
	shake.tween_property(_ufo, "position", Vector2(cx, cy), 0.03)
	await shake.finished

	# Burst of breaking particles at the split point.
	_spawn_break_particles(Vector2(cx, cy))

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

func _spawn_break_particles(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 36
	p.lifetime = 0.75
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.gravity = Vector2(0.0, 200.0)
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 210.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.3, 1.0))   # bright yellow-white
	grad.set_color(1, Color(1.0, 0.15, 0.0, 0.0))   # red-orange → transparent
	p.color_ramp = grad

	p.position = at
	_canvas.add_child(p)
	p.emitting = true

func _show_level_title() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_level_label, "modulate:a", 1.0, 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_level_label, "scale", Vector2(1.0, 1.0), 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _plunge() -> void:
	_show_level_title()
	$SfxFall.play()
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
