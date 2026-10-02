# rainbow_bonus_summary.gd
extends CanvasLayer
class_name RainbowBonusSummary

## End-of-level results for the bonus rainbow level: fruit collected per
## colour band and the points they're worth, then the total. Pauses the game
## until any button is pressed, then calls `on_done`. Spawned by
## RainbowBonusLevel. Same dismiss-on-any-input/pause convention as
## RainbowFishPopup.

const _SCENE_PATH: String = "res://ui/menus/rainbow_bonus_summary.tscn"
const _BLINK_PERIOD_MSEC: float = 500.0
const _BLINK_LOW_ALPHA: float = 0.25
# Mouse mode puts the flippers on LMB/RMB — a click already in flight when
# this pops up mustn't dismiss it unread.
const _CLICK_ARM_DELAY_MSEC: int = 500

@onready var _body: RichTextLabel = $Control/CenterContainer/PanelContainer/VBoxContainer/BodyLabel
@onready var _hint_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/HintLabel

var _counts: Array[int] = []
var _points: Array[int] = []
var _on_done: Callable
var _shown_msec: int = 0
var _done: bool = false

## `counts[band]` / `points[band]`: fruit collected and points earned in each
## band (0 = red … 6 = violet).
static func show_summary(tree: SceneTree, counts: Array[int], points: Array[int], on_done: Callable) -> void:
	var summary := (load(_SCENE_PATH) as PackedScene).instantiate() as RainbowBonusSummary
	summary._counts = counts
	summary._points = points
	summary._on_done = on_done
	tree.current_scene.add_child(summary)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_body.text = _build_text()
	_shown_msec = Time.get_ticks_msec()
	get_tree().paused = true

func _build_text() -> String:
	var lines: Array[String] = ["[center][rainbow freq=0.6 sat=0.75 val=1.0]Rainbow Bonus![/rainbow]", ""]
	var total := 0
	var any := false
	for band in RainbowFish.COLORS.size():
		var count: int = _counts[band] if band < _counts.size() else 0
		var pts: int = _points[band] if band < _points.size() else 0
		total += pts
		if count == 0:
			continue
		any = true
		var color := RainbowFish.COLORS[band].lerp(Color.WHITE, 0.25).to_html(false)
		lines.append("[color=#%s]%s[/color]   fruit x%d   %d" % [color, RainbowFish.COLOR_NAMES[band].capitalize(), count, pts])
	if not any:
		lines.append("No fruit collected")
	lines.append("")
	lines.append("Total   %d" % total)
	lines.append("[/center]")
	return "\n".join(lines)

func _process(_delta: float) -> void:
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	_hint_label.modulate.a = 1.0 if blink_on else _BLINK_LOW_ALPHA

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and Time.get_ticks_msec() - _shown_msec < _CLICK_ARM_DELAY_MSEC:
		return
	var is_dismiss_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_dismiss_input:
		_done = true
		get_viewport().set_input_as_handled()
		queue_free()
		if _on_done.is_valid():
			_on_done.call()
