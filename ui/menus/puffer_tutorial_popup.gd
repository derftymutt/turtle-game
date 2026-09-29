# puffer_tutorial_popup.gd
extends CanvasLayer
class_name PufferTutorialPopup

## One-time explainer the first time (per run) the turtle rams into a puffer
## fish at super speed. Spawned at runtime by PufferFish, so it works in any
## level without being placed in the scene. Same show-once/dismiss-on-any-input/
## pause convention as FlipperReminderPopup.

# Loaded at show time, not preloaded — the scene references this script.
const _SCENE_PATH: String = "res://ui/menus/puffer_tutorial_popup.tscn"
const _BLINK_PERIOD_MSEC: float = 500.0
const _BLINK_LOW_ALPHA: float = 0.25
# Mouse mode puts the flippers on LMB/RMB — a click already in flight when
# this pops up mustn't dismiss it unread.
const _CLICK_ARM_DELAY_MSEC: int = 500

@onready var _key_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/KeyHintLabel

var _eject_action: String = ""
var _shown_msec: int = 0

## Shows the popup unless it's already been shown this run.
static func show_once(tree: SceneTree, eject_action: String) -> void:
	if GameManager.has_shown_puffer_tutorial:
		return
	GameManager.has_shown_puffer_tutorial = true
	var popup := (load(_SCENE_PATH) as PackedScene).instantiate() as PufferTutorialPopup
	popup._eject_action = eject_action
	# Deferred: this is called from a physics callback (SuperSpeedArea contact)
	tree.current_scene.add_child.call_deferred(popup)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_key_label.text = "Use %s to eject from the mouth!" % _eject_key_label()
	_shown_msec = Time.get_ticks_msec()
	get_tree().paused = true

func _process(_delta: float) -> void:
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	_key_label.modulate.a = 1.0 if blink_on else _BLINK_LOW_ALPHA

## Read from the InputMap so the text follows any rebinding of the action.
func _eject_key_label() -> String:
	for event in InputMap.action_get_events(_eject_action):
		if GameSettings.using_gamepad and event is InputEventJoypadButton:
			match (event as InputEventJoypadButton).button_index:
				JOY_BUTTON_A: return "A"
				JOY_BUTTON_B: return "B"
				JOY_BUTTON_X: return "X"
				JOY_BUTTON_Y: return "Y"
		elif not GameSettings.using_gamepad and event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
	return "the eject button"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and Time.get_ticks_msec() - _shown_msec < _CLICK_ARM_DELAY_MSEC:
		return
	var is_dismiss_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_dismiss_input:
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		queue_free()
