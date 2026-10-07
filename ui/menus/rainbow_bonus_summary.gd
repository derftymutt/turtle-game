# rainbow_bonus_summary.gd
extends CanvasLayer
class_name RainbowBonusSummary

## End-of-level results for the bonus rainbow level: fruit collected per
## colour band and the points they're worth, the total, and the rainbow heart
## earned. Pauses the game until any button is pressed, then calls `on_done`.
## Spawned by RainbowBonusLevel. Same dismiss-on-any-input/pause convention as
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
var _heart_gained: bool = false
var _on_done: Callable
var _shown_msec: int = 0
var _done: bool = false

## `counts[band]` / `points[band]`: fruit collected and points earned in each
## band (0 = red … 6 = violet).
static func show_summary(tree: SceneTree, counts: Array[int], points: Array[int], heart_gained: bool, on_done: Callable) -> void:
	var summary := (load(_SCENE_PATH) as PackedScene).instantiate() as RainbowBonusSummary
	summary._counts = counts
	summary._points = points
	summary._heart_gained = heart_gained
	summary._on_done = on_done
	tree.current_scene.add_child(summary)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_body.clear()
	_body.append_text(_build_text())
	if _heart_gained:
		_body.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
		_body.add_image(HeartsDisplay.rainbow_heart_texture(), 22, 20)
		_body.append_text("  gained!")
		_body.pop()
	_shown_msec = Time.get_ticks_msec()
	get_tree().paused = true

## One table row per colour with fruit: name, amount collected, that colour's
## multiplier (in its colour) and the points. Numbers are right-aligned so the
## columns line up down the rainbow.
func _build_text() -> String:
	var lines: Array[String] = [
		"[center][rainbow freq=0.6 sat=0.75 val=1.0]Rainbow Bonus![/rainbow]",
		"[font_size=11][color=#a0a0b0]%d pts per fruit[/color][/font_size]" % Fruit.BASE_POINTS,
		"",
	]
	var total := 0
	var rows: Array[String] = []
	var band_count := RainbowFish.COLORS.size()
	for band in band_count:
		var count: int = _counts[band] if band < _counts.size() else 0
		var pts: int = _points[band] if band < _points.size() else 0
		total += pts
		if count == 0:
			continue
		var color := RainbowFish.COLORS[band].lerp(Color.WHITE, 0.25).to_html(false)
		# Same value as RainbowBonusLevel.level_value(): red 7 … violet 1
		var multiplier := band_count - band
		rows.append(_cell("[color=#%s]%s[/color]" % [color, RainbowFish.COLOR_NAMES[band].capitalize()], false)
				+ _cell(str(count))
				+ _cell("[color=#%s]x%d[/color]" % [color, multiplier])
				+ _cell(str(pts)))
	if rows.is_empty():
		lines.append("No fruit collected")
		lines.append("")
		lines.append("Total   0")
	else:
		rows.append(_cell("", false) + _cell("") + _cell("") + _cell(""))
		rows.append(_cell("Total", false) + _cell("") + _cell("") + _cell(str(total)))
		lines.append("[table=4]%s[/table]" % "".join(rows))
	lines.append("[/center]")
	return "\n".join(lines) + "\n"

func _cell(text: String, right_aligned: bool = true) -> String:
	text = ("[right]%s[/right]" if right_aligned else "[left]%s[/left]") % text
	return "[cell padding=7,0,7,0]%s[/cell]" % text

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
