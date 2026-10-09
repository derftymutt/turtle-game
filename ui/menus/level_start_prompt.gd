# level_start_prompt.gd
extends CanvasLayer
class_name LevelStartPrompt

## Holds a freshly loaded level still behind a short countdown, so the player
## can look the level over and make a plan before anything moves. Each number
## plunges in from the top of the screen and lands with a little overshoot,
## as the number before it quickly fades out of the spot; the last one fades
## away.
## Any button
## skips the rest of the countdown and starts at once. It pauses the tree the
## moment it is added — from LevelBase._ready(), so the level never runs a
## frame first. Built in code and added by LevelBase.show_start_prompt(). No
## panel or dimming — the level itself is what the player is meant to read.

## The countdown ran out (or was skipped) and the level is running.
signal started

## Presses this soon after the prompt appears are ignored — the player may
## still be mashing through the screen that led here.
const _ARM_DELAY_MSEC: int = 400
const _COUNTDOWN_SECONDS: float = 3.0
## A beat before the first number drops, so the screen is seen first and
## the "3" isn't missed
const _START_DELAY: float = 0.5
## How much of each number's second it spends plunging in from above
const _PLUNGE_PORTION: float = 0.3
const _PLUNGE_HEIGHT: float = 260.0
## The number before it fades out over this much of the new one's plunge
const _REPLACE_FADE: float = 0.5
## How much of the last number's second it spends fading out
const _FADE_PORTION: float = 0.35
## A little south of the screen centre
const _TEXT_OFFSET_Y: float = 44.0
## Under the pause menu (layer 8), which can open on top of this
const _LAYER: int = 5

var _label: Label
## The number being replaced, still in the spot until the new one lands
var _previous_label: Label
var _waiting: bool = false
var _menu_open: bool = false
var _shown_msec: int = 0
var _delay: float = _START_DELAY
var _remaining: float = _COUNTDOWN_SECONDS

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = _LAYER

	_previous_label = _make_number_label()
	_label = _make_number_label()
	_place_numbers()

	get_tree().paused = true
	_shown_msec = Time.get_ticks_msec()
	_waiting = true

func _make_number_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Screen-sized and moved as a whole, so the centred number can be animated
	label.size = get_viewport().get_visible_rect().size
	label.position = Vector2(0.0, _TEXT_OFFSET_Y)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.visible = false
	add_child(label)
	return label

func _process(delta: float) -> void:
	if not _waiting:
		return
	# Out of the way, and on hold, while the pause menu is open over it
	var pause_menu := get_tree().get_first_node_in_group("pause_menu") as CanvasLayer
	_menu_open = pause_menu != null and pause_menu.visible
	if _menu_open:
		_label.visible = false
		_previous_label.visible = false
		return
	if _delay > 0.0:
		_delay -= delta
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_start()
		return
	_place_numbers()

## Where the numbers are in this second: the new one plunging in or sitting,
## the one before it fading out of the spot as that starts, and the last one
## fading. Driven by the countdown itself (not a tween) so it holds with it
## under the pause menu.
func _place_numbers() -> void:
	var number: int = maxi(1, ceili(_remaining))
	var t: float = fposmod(-_remaining, 1.0)  # 0..1 through this second
	var plunge: float = clampf(t / _PLUNGE_PORTION, 0.0, 1.0)
	# Ease out with overshoot: drops past its spot and settles back
	var u: float = plunge - 1.0
	var landed: float = 1.0 + 2.70158 * u * u * u + 1.70158 * u * u
	_label.text = str(number)
	_label.position = Vector2(0.0, _TEXT_OFFSET_Y - _PLUNGE_HEIGHT * (1.0 - landed))
	_label.visible = _delay <= 0.0
	_label.modulate.a = 1.0
	if number == 1:
		_label.modulate.a = clampf((1.0 - t) / _FADE_PORTION, 0.0, 1.0)
	_previous_label.text = str(number + 1)
	_previous_label.visible = _label.visible and number < ceili(_COUNTDOWN_SECONDS) and plunge < _REPLACE_FADE
	_previous_label.modulate.a = 1.0 - plunge / _REPLACE_FADE

func _unhandled_input(event: InputEvent) -> void:
	if not _waiting or _menu_open:
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
		get_viewport().set_input_as_handled()
		_start()

func _start() -> void:
	_waiting = false
	get_tree().paused = false
	started.emit()
	queue_free()
