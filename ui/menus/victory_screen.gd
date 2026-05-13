# victory_screen.gd
extends CanvasLayer

@onready var final_score_label:  Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var attempts_label:     Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/AttemptsLabel
@onready var total_time_label:   Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/TotalTimeLabel
@onready var success_time_label: Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/SuccessTimeLabel
@onready var best_score_label:    Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/BestScoreLabel
@onready var new_best_label:      Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/NewBestLabel
@onready var best_time_label:     Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/BestTimeLabel
@onready var new_best_time_label: Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/NewBestTimeLabel
@onready var alien_techs_label:  Label  = $Control/CenterContainer/PanelContainer/VBoxContainer/AlienTechsLabel
@onready var play_again_button:  Button = $Control/CenterContainer/PanelContainer/VBoxContainer/PlayAgainButton
@onready var main_menu_button:   Button = $Control/CenterContainer/PanelContainer/VBoxContainer/MainMenuButton

const _HARD_RED := Color(1.0, 0.18, 0.18)

func _format_ms(ms: int) -> String:
	var total_sec := ms / 1000
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	return "%d:%02d" % [minutes, seconds]

func _ready():
	# Capture run stats before resetting anything
	var final_score    := GameManager.total_score
	var total_continues := LevelManager.continue_count
	var total_ms       := LevelManager.total_time_ms
	var success_ms     := LevelManager.successful_time_ms
	var tech_count     := AlienTechManager.get_variety_count()
	var is_hard        := GameSettings.hard_mode

	if is_hard:
		# Hard mode: save to separate hard mode records
		var prev_best_hard := SaveManager.get_best_victory_score_hard()
		SaveManager.save_victory_score_hard(final_score)
		var new_best_hard  := SaveManager.get_best_victory_score_hard()
		var is_new_best    := (prev_best_hard == 0 or final_score > prev_best_hard)

		var prev_best_time_hard := SaveManager.get_best_victory_time_ms_hard()
		SaveManager.save_victory_time_hard(success_ms)
		var new_best_time_hard  := SaveManager.get_best_victory_time_ms_hard()
		var is_new_best_time    := success_ms > 0 and (prev_best_time_hard == 0 or success_ms < prev_best_time_hard)

		# The run save is no longer useful — clear it
		SaveManager.delete_save()
		GameManager.reset_game()

		# Populate labels
		if final_score_label:
			final_score_label.text = "[HARD MODE] Final Score: %d" % final_score
			final_score_label.add_theme_color_override("font_color", _HARD_RED)

		if attempts_label:
			if total_continues == 0:
				attempts_label.text = "No continues — flawless run!"
			else:
				attempts_label.text = "Total Continues: %d" % total_continues

		if alien_techs_label:
			alien_techs_label.text = "Alien Techs: %d" % tech_count

		if total_time_label:
			total_time_label.text = "Total Time: %s" % _format_ms(total_ms)

		if success_time_label:
			success_time_label.text = "Successful Time: %s" % _format_ms(success_ms)

		if best_score_label:
			best_score_label.text = "Hard Mode Best: %d" % new_best_hard
			best_score_label.add_theme_color_override("font_color", _HARD_RED)
			best_score_label.visible = true

		if new_best_label:
			new_best_label.visible = is_new_best
			if is_new_best:
				new_best_label.add_theme_color_override("font_color", _HARD_RED)

		if best_time_label:
			best_time_label.text = "Hard Mode Best Time: %s" % _format_ms(new_best_time_hard)
			best_time_label.add_theme_color_override("font_color", _HARD_RED)
			best_time_label.visible = new_best_time_hard > 0

		if new_best_time_label:
			new_best_time_label.visible = is_new_best_time
			if is_new_best_time:
				new_best_time_label.add_theme_color_override("font_color", _HARD_RED)

	else:
		# Normal mode
		var prev_best := SaveManager.get_best_victory_score()
		SaveManager.save_victory_score(final_score)
		var new_best  := SaveManager.get_best_victory_score()
		var is_new_best := (prev_best == 0 or final_score > prev_best)

		var prev_best_time := SaveManager.get_best_victory_time_ms()
		SaveManager.save_victory_time(success_ms)
		var new_best_time  := SaveManager.get_best_victory_time_ms()
		var is_new_best_time := success_ms > 0 and (prev_best_time == 0 or success_ms < prev_best_time)

		# The run save is no longer useful — clear it
		SaveManager.delete_save()
		GameManager.reset_game()

		# Populate labels
		if final_score_label:
			final_score_label.text = "Final Score: %d" % final_score

		if attempts_label:
			if total_continues == 0:
				attempts_label.text = "No continues — flawless run!"
			else:
				attempts_label.text = "Total Continues: %d" % total_continues

		if alien_techs_label:
			alien_techs_label.text = "Alien Techs: %d" % tech_count

		if total_time_label:
			total_time_label.text = "Total Time: %s" % _format_ms(total_ms)

		if success_time_label:
			success_time_label.text = "Successful Time: %s" % _format_ms(success_ms)

		if best_score_label:
			best_score_label.text = "Best Victory: %d" % new_best
			best_score_label.visible = true

		if new_best_label:
			new_best_label.visible = is_new_best

		if best_time_label:
			best_time_label.text = "Best Time: %s" % _format_ms(new_best_time)
			best_time_label.visible = new_best_time > 0

		if new_best_time_label:
			new_best_time_label.visible = is_new_best_time

	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	play_again_button.grab_focus()

func _on_play_again_pressed():
	# reset_game() was already called in _ready(); just start level 1
	LevelManager.load_level(1)

func _on_main_menu_pressed():
	GameManager.load_main_menu()
