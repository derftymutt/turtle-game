extends CanvasLayer
class_name GuideScreen

@onready var content_container: VBoxContainer = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ContentContainer
@onready var back_button: Button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/BackButton

var invert_thrust_checkbox: CheckBox
var hard_mode_checkbox: CheckBox
var _back_callback: Callable

func _ready():
	visible = false
	add_to_group("guide_screen")
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	_build_content()

func show_guide(back_callback: Callable = Callable()):
	_back_callback = back_callback
	visible = true
	if back_button:
		back_button.grab_focus()

func hide_guide():
	visible = false

func _build_content():
	if not content_container:
		return

	content_container.add_child(_section_label("CONTROLS"))
	content_container.add_child(_control_row("ACTION", "KEYBOARD", "CONTROLLER", true))
	content_container.add_child(HSeparator.new())

	var controls := [
		["Move",          "WASD",    "Left Stick"],
		["Shoot",         "IJKL",    "Right Stick"],
		["Tech Left",     "Q",       "L Bumper"],
		["Tech Right",    "E",       "R Bumper"],
		["Flipper Left",  "L Shift", "L Trigger"],
		["Flipper Right", "R Shift", "R Trigger"],
		["Drop UFO Piece","Space",   "X"],
		["Pause",         "Escape",  "Start"],
	]
	for row: Array in controls:
		content_container.add_child(_control_row(row[0], row[1], row[2], false))

	content_container.add_child(_spacer(4))
	content_container.add_child(HSeparator.new())
	content_container.add_child(_section_label("SETTINGS"))

	invert_thrust_checkbox = CheckBox.new()
	invert_thrust_checkbox.text = "Invert Thrust  (kick left → propel right)"
	invert_thrust_checkbox.add_theme_font_size_override("font_size", 10)
	invert_thrust_checkbox.button_pressed = GameSettings.thrust_inverted
	invert_thrust_checkbox.toggled.connect(_on_invert_thrust_toggled)

	hard_mode_checkbox = CheckBox.new()
	hard_mode_checkbox.text = "Hard Mode  (health carries over between levels)"
	hard_mode_checkbox.add_theme_font_size_override("font_size", 10)
	hard_mode_checkbox.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	hard_mode_checkbox.button_pressed = GameSettings.hard_mode
	hard_mode_checkbox.toggled.connect(_on_hard_mode_toggled)

	if back_button:
		invert_thrust_checkbox.focus_neighbor_bottom = invert_thrust_checkbox.get_path_to(hard_mode_checkbox)
		hard_mode_checkbox.focus_neighbor_top = hard_mode_checkbox.get_path_to(invert_thrust_checkbox)
		hard_mode_checkbox.focus_neighbor_bottom = hard_mode_checkbox.get_path_to(back_button)
		back_button.focus_neighbor_top = back_button.get_path_to(hard_mode_checkbox)

	content_container.add_child(invert_thrust_checkbox)
	content_container.add_child(hard_mode_checkbox)

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

func _on_hard_mode_toggled(pressed: bool):
	if SaveManager.has_save():
		# Revert the checkbox immediately — user must confirm before it sticks
		hard_mode_checkbox.set_block_signals(true)
		hard_mode_checkbox.button_pressed = GameSettings.hard_mode
		hard_mode_checkbox.set_block_signals(false)

		var dialog = ConfirmationDialog.new()
		dialog.title = "Switch Hard Mode?"
		dialog.dialog_text = "Changing hard mode will delete your current saved progress. Continue?"
		dialog.ok_button_text = "Switch & Delete Save"
		dialog.cancel_button_text = "Cancel"
		dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(dialog)
		dialog.confirmed.connect(func():
			SaveManager.delete_save()
			GameSettings.set_hard_mode(pressed)
			hard_mode_checkbox.set_block_signals(true)
			hard_mode_checkbox.button_pressed = pressed
			hard_mode_checkbox.set_block_signals(false)
			dialog.queue_free()
		)
		dialog.canceled.connect(func():
			dialog.queue_free()
		)
		dialog.popup_centered()
	else:
		GameSettings.set_hard_mode(pressed)


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
