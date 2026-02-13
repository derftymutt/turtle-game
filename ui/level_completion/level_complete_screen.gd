# level_complete_screen.gd
extends CanvasLayer
class_name LevelCompleteScreen

## Simple overlay screen shown when a level is completed
## Displays completion message and score before transitioning to next level

# Node references
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var pieces_label: Label = $CenterContainer/VBoxContainer/StatsContainer/PiecesLabel
@onready var score_label: Label = $CenterContainer/VBoxContainer/StatsContainer/ScoreLabel
@onready var continue_label: Label = $CenterContainer/VBoxContainer/ContinueLabel

# Animation
var pulse_timer: float = 0.0
var pulse_speed: float = 3.0

func _ready():
	# Start hidden
	hide()
	
	# Verify node references
	if not title_label:
		push_warning("LevelCompleteScreen: Missing TitleLabel!")
	if not score_label:
		push_warning("LevelCompleteScreen: Missing ScoreLabel!")
	if not pieces_label:
		push_warning("LevelCompleteScreen: Missing PiecesLabel!")
	if not continue_label:
		push_warning("LevelCompleteScreen: Missing ContinueLabel!")

func _process(delta):
	# Pulse the "Assembling UFO..." text
	if visible and continue_label:
		pulse_timer += delta * pulse_speed
		var alpha = (sin(pulse_timer) + 1.0) / 2.0
		continue_label.modulate.a = 0.5 + (alpha * 0.5)

func show_completion(level_number: int, final_score: int, pieces_collected: int, pieces_needed: int):
	"""Display the level complete screen with stats"""
	# Update labels
	if title_label:
		title_label.text = "Level %d Complete!" % level_number
	
	if pieces_label:
		pieces_label.text = "All %d UFO Pieces Collected!" % pieces_needed
	
	if score_label:
		score_label.text = "Score: %d" % final_score
	
	if continue_label:
		continue_label.text = "Assembling UFO..."
		pulse_timer = 0.0
	
	# Play entrance animation
	show()
	_play_entrance_animation()
	
	print("🎉 Level Complete screen shown!")

func _play_entrance_animation():
	"""Simple fade-in and scale animation"""
	var container = $CenterContainer/VBoxContainer
	
	if not container:
		return
	
	# Start from small and transparent
	container.scale = Vector2(0.5, 0.5)
	container.modulate.a = 0.0
	
	# Tween to full size and opacity
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(container, "scale", Vector2.ONE, 0.5)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.tween_property(container, "modulate:a", 1.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Hide the screen (called before scene transition)
func hide_screen():
	hide()
