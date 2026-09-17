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
@onready var play_again_button:  Button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/PlayAgainButton
@onready var main_menu_button:   Button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/MainMenuButton
@onready var _control: Control = $Control

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

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
	# Run state (equipped techs, hearts, etc.) is deliberately NOT reset here —
	# this screen now shows as an overlay on top of the still-alive, paused
	# level so the player can see exactly how they finished (techs equipped,
	# health, etc.). Resetting now would visibly clear that state on the HUD
	# behind this screen. See _on_play_again_pressed()/_on_main_menu_pressed(),
	# which reset only once the player is actually leaving this screen.

	# Populate labels
	if final_score_label:
		final_score_label.text = "Final Score: %s" % FormatUtil.comma_int(final_score)

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
		best_score_label.text = "Best Victory: %s" % FormatUtil.comma_int(new_best)
		best_score_label.visible = true

	if new_best_label:
		new_best_label.visible = is_new_best

	if best_time_label:
		best_time_label.text = "Best Time: %s" % _format_ms(new_best_time)
		best_time_label.visible = new_best_time > 0

	if new_best_time_label:
		new_best_time_label.visible = is_new_best_time

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)

	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_option_list.wire_option(play_again_button)
	_option_list.wire_option(main_menu_button)

	# Belt-and-suspenders: this scene is freshly loaded via
	# change_scene_to_file() so its layout is normally already valid by the
	# time _ready() runs, but every other screen using TurtleOptionList
	# needed a settle frame before its first grab_focus() — cheap to match.
	await get_tree().process_frame
	await get_tree().process_frame
	play_again_button.grab_focus()

func _on_play_again_pressed():
	get_tree().paused = false
	GameManager.reset_game()
	LevelManager.load_level(1)

func _on_main_menu_pressed():
	get_tree().paused = false
	GameManager.reset_game()
	GameManager.load_main_menu()
