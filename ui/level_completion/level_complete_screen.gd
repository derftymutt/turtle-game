# level_complete_screen.gd
extends CanvasLayer
class_name LevelCompleteScreen

## Simple overlay screen shown when a level is completed

@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var score_label: Label = $CenterContainer/VBoxContainer/StatsContainer/ScoreLabel
@onready var time_bonus_label: Label = $CenterContainer/VBoxContainer/StatsContainer/TimeBonusLabel
@onready var first_try_label: Label = $CenterContainer/VBoxContainer/StatsContainer/FirstTryLabel
@onready var variety_label: Label = $CenterContainer/VBoxContainer/StatsContainer/VarietyLabel
@onready var total_score_label: Label = $CenterContainer/VBoxContainer/StatsContainer/TotalScoreLabel
@onready var attempts_label: Label = $CenterContainer/VBoxContainer/StatsContainer/AttemptsLabel
@onready var next_level_button: Button = $CenterContainer/VBoxContainer/NextLevelButton
@onready var sfx_beat: AudioStreamPlayer = $SfxBeat

func _ready():
	hide()
	next_level_button.pressed.connect(_on_next_level_pressed)

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
		score_label.text = "Level Score: %d" % level_score

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
		total_score_label.text = "Total Score: %d" % run_total

	if attempts_label:
		if level_continues == 0:
			attempts_label.text = ""
			attempts_label.modulate = Color.GOLD
		else:
			attempts_label.text = "Continues used: %d" % level_continues
			attempts_label.modulate = Color.WHITE

	get_tree().paused = true
	show()
	if sfx_beat:
		sfx_beat.play()
	_play_entrance_animation()
	next_level_button.grab_focus()

func _on_next_level_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://cut_scenes/level_transition_cutscene.tscn")

func _play_entrance_animation():
	var container = $CenterContainer/VBoxContainer
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
