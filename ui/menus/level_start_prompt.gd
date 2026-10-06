# level_start_prompt.gd
extends CanvasLayer
class_name LevelStartPrompt

## Holds a freshly loaded level still behind a blinking "Press any button to
## start", so the player can look the level over and make a plan before
## anything moves. It pauses the tree the moment it is added — from
## LevelBase._ready(), so the level never runs a frame first. Built in code and
## added by LevelBase.show_start_prompt(). Same dismiss-on-any-input/pause convention as RainbowFishPopup, but with no
## panel or dimming — the level itself is what the player is meant to read.

## The player pressed something and the level is running.
signal started

## Presses this soon after the prompt appears are ignored — the player may
## still be mashing through the screen that led here.
const _ARM_DELAY_MSEC: int = 400
const _BLINK_PERIOD_MSEC: float = 500.0
const _BLINK_LOW_ALPHA: float = 0.25
## A little south of the screen centre
const _TEXT_OFFSET_Y: float = 44.0
## Under the pause menu (layer 8), which can open on top of this
const _LAYER: int = 5

var _label: Label
var _waiting: bool = false
var _shown_msec: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = _LAYER

	_label = Label.new()
	_label.text = "Press any button to start"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_top = _TEXT_OFFSET_Y * 2.0  # shifts the centred text down by _TEXT_OFFSET_Y
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	get_tree().paused = true
	_shown_msec = Time.get_ticks_msec()
	_waiting = true

func _process(_delta: float) -> void:
	if not _waiting:
		return
	# Out of the way while the pause menu is open over it
	var pause_menu := get_tree().get_first_node_in_group("pause_menu") as CanvasLayer
	_label.visible = not (pause_menu and pause_menu.visible)
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	_label.modulate.a = 1.0 if blink_on else _BLINK_LOW_ALPHA

func _unhandled_input(event: InputEvent) -> void:
	if not _waiting or not _label.visible:
		return
	if Time.get_ticks_msec() - _shown_msec < _ARM_DELAY_MSEC:
		return
	# Pause still opens the pause menu, which hands the frozen level back
	if event.is_action("pause"):
		return
	var is_start_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_start_input:
		_waiting = false
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		started.emit()
		queue_free()
