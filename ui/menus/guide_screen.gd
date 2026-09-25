extends CanvasLayer
class_name GuideScreen

@onready var content_container: VBoxContainer = $Control/CenterContainer/MarginContainer/VBoxContainer/ContentContainer
@onready var back_button: Button = $Control/CenterContainer/MarginContainer/VBoxContainer/OptionsColumn/BackButton
@onready var _control: Control = $Control

var invert_thrust_checkbox: CheckBox
var keyboard_only_checkbox: CheckBox
var fast_mode_checkbox: CheckBox
var _mouse_mode_note: Label
## Keyboard-column labels whose text depends on GameSettings.mouse_mode,
## keyed by action name — see _refresh_keyboard_labels().
var _keyboard_labels: Dictionary = {}

## [keyboard-only, mouse mode] — must match GameSettings._apply_mouse_mode_bindings().
const _KEYBOARD_TEXT := {
	"Shoot":          ["IJKL",    "Mouse aim"],
	"Flipper Left":   ["L Shift", "Left Click"],
	"Flipper Right":  ["R Shift", "Right Click"],
	"Drop UFO Piece": ["Space",   "F"],
	"Tech Left":      ["Q",       "L Shift"],
	"Tech Right":     ["E",       "Space"],
}
var _back_callback: Callable

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

func _ready():
	visible = false
	add_to_group("guide_screen")
	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
		_option_list.wire_option(back_button)
	_build_content()

func show_guide(back_callback: Callable = Callable()):
	_back_callback = back_callback
	visible = true
	# This CanvasLayer's Control subtree doesn't get a real layout pass while
	# hidden, so the button's get_global_rect() is still stale for a frame or
	# two after it's shown — wait for layout to actually settle before
	# positioning the turtle indicator against it (same fix as
	# pause_menu.gd's _open()).
	await get_tree().process_frame
	await get_tree().process_frame
	if back_button:
		back_button.grab_focus()

func hide_guide():
	visible = false

func _build_content():
	if not content_container:
		return

	content_container.add_child(_section_label("CONTROLS"))
	content_container.add_child(_control_row("ACTION", "CONTROLLER", "KEYBOARD", true))
	content_container.add_child(HSeparator.new())

	var controls := [
		["Move",          "Left Stick",  "WASD"],
		["Shoot",         "Right Stick", "IJKL"],
		["Flipper Left",  "L Trigger",   "L Shift"],
		["Flipper Right", "R Trigger",   "R Shift"],
		["Drop UFO Piece","X",           "Space"],
		["Tech Left",     "L Bumper",    "Q"],
		["Tech Right",    "R Bumper",    "E"],
		["Pause",         "Start",       "Escape"],
	]
	for row: Array in controls:
		var control_row := _control_row(row[0], row[1], row[2], false)
		content_container.add_child(control_row)
		if _KEYBOARD_TEXT.has(row[0]):
			_keyboard_labels[row[0]] = control_row.get_child(2)

	content_container.add_child(_spacer(4))
	content_container.add_child(HSeparator.new())
	content_container.add_child(_section_label("SETTINGS"))

	invert_thrust_checkbox = CheckBox.new()
	invert_thrust_checkbox.text = "Invert Thrust  (kick left → propel right)"
	invert_thrust_checkbox.add_theme_font_size_override("font_size", 10)
	invert_thrust_checkbox.button_pressed = GameSettings.thrust_inverted
	invert_thrust_checkbox.toggled.connect(_on_invert_thrust_toggled)
	content_container.add_child(invert_thrust_checkbox)

	keyboard_only_checkbox = CheckBox.new()
	keyboard_only_checkbox.text = "Keyboard Only  (aim with I J K L, no mouse)"
	keyboard_only_checkbox.add_theme_font_size_override("font_size", 10)
	keyboard_only_checkbox.button_pressed = not GameSettings.mouse_mode
	keyboard_only_checkbox.toggled.connect(_on_keyboard_only_toggled)
	content_container.add_child(keyboard_only_checkbox)

	_mouse_mode_note = Label.new()
	_mouse_mode_note.text = "Mouse aim fires on its own - Tab or middle click toggles"
	_mouse_mode_note.add_theme_font_size_override("font_size", 9)
	_mouse_mode_note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	content_container.add_child(_mouse_mode_note)
	_refresh_keyboard_labels()

	fast_mode_checkbox = CheckBox.new()
	fast_mode_checkbox.text = "Fast Mode  (whole game at %sx speed)" % GameSettings.FAST_GAME_SPEED
	fast_mode_checkbox.add_theme_font_size_override("font_size", 10)
	fast_mode_checkbox.button_pressed = GameSettings.fast_mode
	fast_mode_checkbox.toggled.connect(_on_fast_mode_toggled)
	content_container.add_child(fast_mode_checkbox)

	# Focus wiring only after all nodes share a parent tree
	invert_thrust_checkbox.focus_neighbor_bottom = invert_thrust_checkbox.get_path_to(keyboard_only_checkbox)
	keyboard_only_checkbox.focus_neighbor_top = keyboard_only_checkbox.get_path_to(invert_thrust_checkbox)
	keyboard_only_checkbox.focus_neighbor_bottom = keyboard_only_checkbox.get_path_to(fast_mode_checkbox)
	fast_mode_checkbox.focus_neighbor_top = fast_mode_checkbox.get_path_to(keyboard_only_checkbox)
	if back_button:
		fast_mode_checkbox.focus_neighbor_bottom = fast_mode_checkbox.get_path_to(back_button)
		back_button.focus_neighbor_top = back_button.get_path_to(fast_mode_checkbox)

func _on_back_pressed():
	hide_guide()
	if _back_callback.is_valid():
		var cb := _back_callback
		_back_callback = Callable()
		cb.call()
	else:
		var main_menu = get_parent()
		if main_menu and main_menu.has_method("show_menu"):
			main_menu.show_menu()

func _on_invert_thrust_toggled(pressed: bool):
	GameSettings.set_thrust_inverted(pressed)

func _on_fast_mode_toggled(pressed: bool):
	GameSettings.set_fast_mode(pressed)

func _on_keyboard_only_toggled(pressed: bool):
	GameSettings.set_mouse_mode(not pressed)
	_refresh_keyboard_labels()

func _refresh_keyboard_labels() -> void:
	var index := 1 if GameSettings.mouse_mode else 0
	for action: String in _keyboard_labels:
		(_keyboard_labels[action] as Label).text = _KEYBOARD_TEXT[action][index]
	if _mouse_mode_note:
		# Hidden, not freed, so the menu doesn't reflow when toggled.
		_mouse_mode_note.modulate.a = 1.0 if GameSettings.mouse_mode else 0.0


# ── layout helpers ────────────────────────────────────────────────────────────

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _control_row(action: String, keyboard: String, controller: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var font_size := 9 if is_header else 10
	var color := Color(0.65, 0.65, 0.65) if is_header else Color(1, 1, 1)

	for col_text: String in [action, keyboard, controller]:
		var l := Label.new()
		l.text = col_text
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", color)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)

	return row

func _spacer(height: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s
