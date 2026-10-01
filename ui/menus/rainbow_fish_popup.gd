# rainbow_fish_popup.gd
extends CanvasLayer
class_name RainbowFishPopup

## Announces a Rainbow Fish round the moment it starts: pauses the game (so
## the round timer doesn't run while it's up) until any button is pressed.
## Spawned at runtime by RainbowFishSpawner, once per round. Same
## dismiss-on-any-input/pause convention as PufferTutorialPopup.

# Loaded at show time, not preloaded — the scene references this script.
const _SCENE_PATH: String = "res://ui/menus/rainbow_fish_popup.tscn"
const _BLINK_PERIOD_MSEC: float = 500.0
const _BLINK_LOW_ALPHA: float = 0.25
# Mouse mode puts the flippers on LMB/RMB — a click already in flight when
# this pops up mustn't dismiss it unread.
const _CLICK_ARM_DELAY_MSEC: int = 500

@onready var _message: RichTextLabel = $Control/CenterContainer/PanelContainer/VBoxContainer/MessageLabel
@onready var _hint_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/HintLabel

var _shown_msec: int = 0

static func show_round(tree: SceneTree) -> void:
	var popup := (load(_SCENE_PATH) as PackedScene).instantiate() as RainbowFishPopup
	tree.current_scene.add_child(popup)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_message.text = "[center][rainbow freq=0.6 sat=0.75 val=1.0]Save the rainbow fish trapped in 6-pack rings!\nYou don't have much time![/rainbow][/center]"
	_shown_msec = Time.get_ticks_msec()
	get_tree().paused = true

func _process(_delta: float) -> void:
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	_hint_label.modulate.a = 1.0 if blink_on else _BLINK_LOW_ALPHA

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
