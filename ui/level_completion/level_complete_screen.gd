# level_complete_screen.gd
extends CanvasLayer
class_name LevelCompleteScreen

## Simple overlay screen shown when a level is completed

@onready var title_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/TitleLabel
@onready var score_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/ScoreLabel
@onready var time_bonus_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/TimeBonusLabel
@onready var first_try_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/FirstTryLabel
@onready var variety_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/VarietyLabel
@onready var total_score_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/TotalScoreLabel
@onready var attempts_label: Label = $Control/CenterContainer/PanelContainer/VBoxContainer/StatsContainer/AttemptsLabel
@onready var next_level_button: Button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/NextLevelButton
@onready var sfx_beat: AudioStreamPlayer = $SfxBeat
@onready var _control: Control = $Control

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

# Mouse mode puts the flippers on LMB/RMB, so a player mid-flip when this
# screen pops up would otherwise click whatever button is under the cursor.
const _CLICK_ARM_DELAY_MSEC: int = 500
var _shown_msec: int = 0

func _ready():
	hide()
	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)
	next_level_button.pressed.connect(_on_next_level_pressed)
	_option_list.wire_option(next_level_button)

func show_completion(
	level_number: int,
	level_score: int,
	run_total: int,
	time_bonus: int,
	first_try_bonus: int,
	variety_count: int,
	_pieces_collected: int,
	_pieces_needed: int,
	level_continues: int = 0
):
	if title_label:
		title_label.text = "Level %d Complete!" % level_number

	if score_label:
		score_label.text = "Level Score: %s" % FormatUtil.comma_int(level_score)

	if time_bonus_label:
		time_bonus_label.text = "Time Bonus: +%d" % time_bonus
		time_bonus_label.modulate = Color.CYAN if time_bonus > 0 else Color.GRAY

	if first_try_label:
		if first_try_bonus > 0:
			first_try_label.text = "First Try! +%d" % first_try_bonus
			first_try_label.modulate = Color.GOLD
			first_try_label.visible = true
		else:
			first_try_label.visible = false

	if variety_label:
		var variety_pts = variety_count * LevelManager.VARIETY_BONUS_PER_TECH
		variety_label.text = "Tech Variety: %d unique (+%d at run end)" % [variety_count, variety_pts]
		variety_label.modulate = Color.MEDIUM_PURPLE

	if total_score_label:
		total_score_label.text = "Total Score: %s" % FormatUtil.comma_int(run_total)

	if attempts_label:
		if level_continues == 0:
			attempts_label.text = ""
			attempts_label.modulate = Color.GOLD
		else:
			attempts_label.text = "Continues used: %d" % level_continues
			attempts_label.modulate = Color.WHITE

	get_tree().paused = true
	show()
	_shown_msec = Time.get_ticks_msec()
	if sfx_beat:
		sfx_beat.play()
	_play_entrance_animation()
	# This CanvasLayer's Control subtree doesn't get a real layout pass while
	# hidden, so the button's get_global_rect() is still stale for a frame or
	# two after it's shown — wait for layout to actually settle before
	# positioning the turtle indicator against it (same fix as
	# pause_menu.gd's _open()).
	await get_tree().process_frame
	await get_tree().process_frame
	next_level_button.grab_focus()

func _on_next_level_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cut_scenes/level_transition_cutscene.tscn")

func _play_entrance_animation():
	var container = $Control/CenterContainer/PanelContainer
	if not container:
		return

	container.scale = Vector2(0.5, 0.5)
	container.modulate.a = 0.0

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "scale", Vector2.ONE, 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "modulate:a", 1.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_screen():
	get_tree().paused = false
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and Time.get_ticks_msec() - _shown_msec < _CLICK_ARM_DELAY_MSEC:
		get_viewport().set_input_as_handled()
		return
