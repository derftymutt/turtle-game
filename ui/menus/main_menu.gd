# main_menu.gd
extends CanvasLayer

## Main Menu — shows Continue (if save exists) and New Game.
## Level-select dev buttons are shown only when GameManager.DEV_MODE is true.

@onready var title_label = $Control/CenterContainer/VBoxContainer/TitleLabel
@onready var level_container = $Control/CenterContainer/VBoxContainer/LevelContainer

var guide_screen = null
var game_info_screen = null

const _HARD_RED    := Color(1.0, 0.18, 0.18)
const _HARD_GOLD   := Color(1.0, 0.45, 0.45)   # tinted gold for record labels in hard mode
const _NORMAL_GOLD := Color(1.0, 0.85, 0.0)

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.wav")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.wav")

var _sfx_nav:         AudioStreamPlayer
var _sfx_select:      AudioStreamPlayer
var _nav_sound_ready: bool = false

func _ready():
	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	_sfx_nav.volume_db = 0.0
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = 0.0
	add_child(_sfx_select)

	guide_screen = get_tree().get_first_node_in_group("guide_screen")
	game_info_screen = get_tree().get_first_node_in_group("game_info_screen")
	_build_buttons()
	if GameSettings.hard_mode and title_label:
		title_label.add_theme_color_override("font_color", _HARD_RED)
	# Enable nav sound next frame so the automatic grab_focus() in _build_buttons()
	# doesn't trigger it on load before the player has touched anything.
	call_deferred("_enable_nav_sound")

func _format_ms(ms: int) -> String:
	var total_sec := ms / 1000
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	return "%d:%02d" % [minutes, seconds]

func _build_buttons():
	var is_hard := GameSettings.hard_mode
	var text_color  := _HARD_RED   if is_hard else Color.WHITE
	var record_color := _HARD_GOLD if is_hard else _NORMAL_GOLD

	# === NORMAL MODE BEST VICTORY RECORDS ===
	var best_victory   := SaveManager.get_best_victory_score()
	var best_time_ms   := SaveManager.get_best_victory_time_ms()
	if best_victory > 0 or best_time_ms > 0:
		var records_label := Label.new()
		var records_text := ""
		if best_victory > 0:
			records_text += "Best Score: %d" % best_victory
		if best_time_ms > 0:
			if records_text != "":
				records_text += "   "
			records_text += "Best Time: %s" % _format_ms(best_time_ms)
		records_label.text = records_text
		records_label.add_theme_font_size_override("font_size", 13)
		records_label.add_theme_color_override("font_color", _NORMAL_GOLD if not is_hard else Color(_NORMAL_GOLD.r * 0.6, _NORMAL_GOLD.g * 0.6, _NORMAL_GOLD.b * 0.6))
		records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_container.add_child(records_label)

	# === HARD MODE BEST VICTORY RECORDS ===
	var hard_best_score := SaveManager.get_best_victory_score_hard()
	var hard_best_time  := SaveManager.get_best_victory_time_ms_hard()
	if hard_best_score > 0 or hard_best_time > 0:
		var hard_label := Label.new()
		var hard_text := "[HARD]  "
		if hard_best_score > 0:
			hard_text += "Best Score: %d" % hard_best_score
		if hard_best_time > 0:
			if hard_best_score > 0:
				hard_text += "   "
			hard_text += "Best Time: %s" % _format_ms(hard_best_time)
		hard_label.text = hard_text
		hard_label.add_theme_font_size_override("font_size", 13)
		hard_label.add_theme_color_override("font_color", _HARD_RED)
		hard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_container.add_child(hard_label)

	# === CONTINUE (only when a save exists) ===
	if SaveManager.has_save():
		var level = SaveManager.get_save_level()
		var save_is_hard := SaveManager.get_save_hard_mode()
		var continue_button = Button.new()
		continue_button.text = "Continue  (Level %d)%s" % [level, "  [HARD]" if save_is_hard else ""]
		continue_button.custom_minimum_size = Vector2(200, 40)
		continue_button.add_theme_font_size_override("font_size", 18)
		if save_is_hard:
			continue_button.add_theme_color_override("font_color", _HARD_RED)
		elif is_hard:
			continue_button.add_theme_color_override("font_color", text_color)
		continue_button.pressed.connect(_on_continue_pressed)
		_wire_button_sounds(continue_button)
		level_container.add_child(continue_button)

	# === NEW GAME ===
	var new_game_button = Button.new()
	new_game_button.text = "New Game"
	new_game_button.custom_minimum_size = Vector2(200, 40)
	new_game_button.add_theme_font_size_override("font_size", 18)
	new_game_button.add_theme_color_override("font_color", text_color)
	new_game_button.pressed.connect(_on_new_game_pressed)
	_wire_button_sounds(new_game_button)
	level_container.add_child(new_game_button)

	# === DEV LEVEL SELECT (hidden in release builds) ===
	if GameManager.DEV_MODE:
		var dev_row = HBoxContainer.new()
		dev_row.add_theme_constant_override("separation", 4)
		level_container.add_child(dev_row)

		for level_num in LevelManager.level_scenes.keys():
			var btn = Button.new()
			btn.text = str(level_num)
			btn.custom_minimum_size = Vector2(28, 28)
			btn.add_theme_font_size_override("font_size", 10)
			btn.add_theme_color_override("font_color", text_color)
			btn.pressed.connect(func(): _on_dev_level_selected(level_num))
			_wire_button_sounds(btn)
			dev_row.add_child(btn)

	# === OPTIONS ===
	var guide_button = Button.new()
	guide_button.text = "Options"
	guide_button.custom_minimum_size = Vector2(100, 10)
	guide_button.add_theme_font_size_override("font_size", 8)
	guide_button.add_theme_color_override("font_color", text_color)
	guide_button.pressed.connect(_on_guide_pressed)
	_wire_button_sounds(guide_button)
	level_container.add_child(guide_button)

	# === QUIT ===
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(100, 10)
	quit_button.add_theme_font_size_override("font_size", 8)
	quit_button.add_theme_color_override("font_color", text_color)
	quit_button.pressed.connect(_on_quit_pressed)
	_wire_button_sounds(quit_button)
	level_container.add_child(quit_button)

	# Focus the first Button child (skip Labels)
	for child in level_container.get_children():
		if child is Button:
			child.grab_focus()
			break

func _on_continue_pressed():
	if _sfx_select:
		_sfx_select.play()
	SaveManager.apply_save()
	LevelManager.attempt_count = 1
	LevelManager.load_level(LevelManager.current_level_number)

func _on_new_game_pressed():
	if _sfx_select:
		_sfx_select.play()
	if SaveManager.has_save():
		_confirm_overwrite_save()
	else:
		_start_new_game()

func _confirm_overwrite_save():
	var level = SaveManager.get_save_level()
	var dialog = ConfirmationDialog.new()
	dialog.title = "Start New Game?"
	dialog.dialog_text = "Your saved progress at Level %d will be lost." % level
	dialog.ok_button_text = "New Game"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func():
		SaveManager.delete_save()
		dialog.queue_free()
		_start_new_game()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _start_new_game():
	GameManager.reset_game()
	if game_info_screen and game_info_screen.has_method("show_screen"):
		visible = false
		game_info_screen.show_screen()
	else:
		LevelManager.load_level(1)

func _on_dev_level_selected(level_num: int):
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	LevelManager.load_level(level_num)

func _on_guide_pressed():
	if _sfx_select:
		_sfx_select.play()
	if guide_screen and guide_screen.has_method("show_guide"):
		visible = false
		guide_screen.show_guide(func(): show_menu())
	else:
		push_warning("MainMenu: Guide screen not found!")

func _on_quit_pressed():
	if _sfx_select:
		_sfx_select.play()
	get_tree().quit()

func _enable_nav_sound() -> void:
	_nav_sound_ready = true

func _wire_button_sounds(btn: Button) -> void:
	btn.focus_entered.connect(func(): if _nav_sound_ready: _sfx_nav.play())

func show_menu():
	"""Called by guide screen when returning to menu"""
	visible = true
	_refresh_colors()
	for child in level_container.get_children():
		if child is Button:
			child.grab_focus()
			break

func _refresh_colors():
	"""Re-applies hard-mode text color to all existing menu elements (no rebuild needed)"""
	var is_hard := GameSettings.hard_mode
	var text_color := _HARD_RED if is_hard else Color.WHITE
	if title_label:
		if is_hard:
			title_label.add_theme_color_override("font_color", _HARD_RED)
		else:
			title_label.remove_theme_color_override("font_color")
	if not level_container:
		return
	for child in level_container.get_children():
		if child is Button:
			child.add_theme_color_override("font_color", text_color)
		elif child is Label:
			# Hard mode record label stays red; normal record label follows mode
			if not child.text.begins_with("[HARD]"):
				child.add_theme_color_override("font_color",
					_HARD_GOLD if is_hard else _NORMAL_GOLD)
