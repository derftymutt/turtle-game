# main_menu.gd
extends CanvasLayer

## Main Menu — shows Continue (if save exists) and New Game.
## Level-select dev buttons are shown only when GameManager.DEV_MODE is true.

@onready var title_label = $Control/CenterContainer/VBoxContainer/TitleLabel
@onready var level_container = $Control/CenterContainer/VBoxContainer/LevelContainer

var guide_screen = null

func _ready():
	guide_screen = get_tree().get_first_node_in_group("guide_screen")
	_build_buttons()

func _format_ms(ms: int) -> String:
	var total_sec := ms / 1000
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	return "%d:%02d" % [minutes, seconds]

func _build_buttons():
	# === BEST VICTORY RECORDS ===
	var best_victory := SaveManager.get_best_victory_score()
	var best_time_ms := SaveManager.get_best_victory_time_ms()
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
		records_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_container.add_child(records_label)

	# === CONTINUE (only when a save exists) ===
	if SaveManager.has_save():
		var level = SaveManager.get_save_level()
		var continue_button = Button.new()
		continue_button.text = "Continue  (Level %d)" % level
		continue_button.custom_minimum_size = Vector2(200, 40)
		continue_button.add_theme_font_size_override("font_size", 18)
		continue_button.pressed.connect(_on_continue_pressed)
		level_container.add_child(continue_button)

	# === NEW GAME ===
	var new_game_button = Button.new()
	new_game_button.text = "New Game"
	new_game_button.custom_minimum_size = Vector2(200, 40)
	new_game_button.add_theme_font_size_override("font_size", 18)
	new_game_button.pressed.connect(_on_new_game_pressed)
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
			btn.pressed.connect(func(): _on_dev_level_selected(level_num))
			dev_row.add_child(btn)

	# === GUIDE ===
	var guide_button = Button.new()
	guide_button.text = "Guide/Options/Help/PANIC!!!"
	guide_button.custom_minimum_size = Vector2(100, 10)
	guide_button.add_theme_font_size_override("font_size", 8)
	guide_button.pressed.connect(_on_guide_pressed)
	level_container.add_child(guide_button)

	# === QUIT ===
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(100, 10)
	quit_button.add_theme_font_size_override("font_size", 8)
	quit_button.pressed.connect(_on_quit_pressed)
	level_container.add_child(quit_button)

	# Focus the first Button child (skip Labels)
	for child in level_container.get_children():
		if child is Button:
			child.grab_focus()
			break

func _on_continue_pressed():
	SaveManager.apply_save()
	LevelManager.attempt_count = 1
	LevelManager.load_level(LevelManager.current_level_number)

func _on_new_game_pressed():
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
	LevelManager.load_level(1)

func _on_dev_level_selected(level_num: int):
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	LevelManager.load_level(level_num)

func _on_guide_pressed():
	if guide_screen and guide_screen.has_method("show_guide"):
		visible = false
		guide_screen.show_guide()
	else:
		push_warning("MainMenu: Guide screen not found!")

func _on_quit_pressed():
	get_tree().quit()

func show_menu():
	"""Called by guide screen when returning to menu"""
	visible = true
	if level_container:
		for child in level_container.get_children():
			if child is Button:
				child.grab_focus()
				break
