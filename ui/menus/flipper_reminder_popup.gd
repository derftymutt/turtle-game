# flipper_reminder_popup.gd
extends CanvasLayer
class_name FlipperReminderPopup

## One-time nudge for level 1: if the player delivers 2 UFO pieces without ever
## having been launched by a pinball flipper, remind them the flippers exist.
## Same show-once/dismiss-on-any-input/pause convention as BossIntroPopup.

const _BLINK_PERIOD_MSEC: float = 500.0
const _BLINK_LOW_ALPHA: float = 0.25

@onready var _hint_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/FlipperHintLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	LevelManager.piece_delivered.connect(_on_piece_delivered)

func _process(_delta: float) -> void:
	if not visible:
		return
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	_hint_label.modulate.a = 1.0 if blink_on else _BLINK_LOW_ALPHA

func _on_piece_delivered(pieces_collected: int, _pieces_needed: int) -> void:
	if GameManager.has_shown_flipper_reminder or GameManager.has_used_flipper:
		return
	if pieces_collected < 2:
		return
	GameManager.has_shown_flipper_reminder = true
	_hint_label.text = "Use flippers with LT / RT (%s)" % (
		"Left/Right Click" if GameSettings.mouse_mode else "Left/Right Shift")
	visible = true
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var is_dismiss_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_dismiss_input:
		get_viewport().set_input_as_handled()
		visible = false
		get_tree().paused = false
