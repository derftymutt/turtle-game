# game_over_screen.gd
extends CanvasLayer
class_name GameOverScreen

## Game Over screen with restart, main menu, and quit options

@onready var game_over_panel = $Control/CenterContainer/PanelContainer
@onready var vbox_container = $Control/CenterContainer/PanelContainer/VBoxContainer
@onready var hint_label = $Control/CenterContainer/PanelContainer/VBoxContainer/HintLabel
@onready var final_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var high_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/HighScoreLabel
@onready var attempts_label = $Control/CenterContainer/PanelContainer/VBoxContainer/AttemptsLabel
@onready var retry_button = $Control/CenterContainer/PanelContainer/VBoxContainer/RetryButton
@onready var menu_button = $Control/CenterContainer/PanelContainer/VBoxContainer/MenuButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton

var final_score: int = 0

const HINTS: Array[String] = [
	"UFO Parts are heavy. Drop them if you need to.",
	"You won't keep holding a UFO part if you take damage",
	"Recover energy sparkly fast resting on pinball parts (and your workshop)",
	"Reincarnation only remembers your most recent alien tech",
	"Hold your breath longer with air bubble powerups",
	"Crocodiles just don't wanna die do they",
	"Clean up the ocean for points",
	"The ocean is so happy those plastic bottles are gone, she'll give you a powerup",
	"Alien tech encrusted in trash appear every 200 points",
	"A clean ocean allows health plants to grow",
	"Turtles eat apples",
	"Pinball flippers get the job done",
	"Nothing can stop you in super speed",
	"It's tiring to swim. Swim smart!",
	"What's in the sky?",
	"Crabs make babies if left alone",
	"Sea urchins can't be bothered",
	"Bumper pogo",
	"It's a dance",
	"Turtles never run out of saliva",
	"Relax and let the environment do the work",
	"Breathe",
	"Crocodiles love a good race",
	"You're the only turtle you know that can get from surface to sea floor in one full energy sprint",
	"You're the turtle, not the hare, after all",
	"Listen to your lungs!",
	"Why's the US military so uptight about aliens?",
	"Trying a variety of alien techs will gain you wisdom",
	"Ocean currents weeeeeeeee!",
	"Your name is Flip for a reason",
]

static var _shown_hint_indices: Array[int] = []

static func _pick_hint() -> String:
	if _shown_hint_indices.size() >= HINTS.size():
		_shown_hint_indices.clear()
	var remaining: Array[int] = []
	for i in range(HINTS.size()):
		if not _shown_hint_indices.has(i):
			remaining.append(i)
	var idx: int = remaining[randi() % remaining.size()]
	_shown_hint_indices.append(idx)
	return HINTS[idx]

func _ready():
	add_to_group("game_over_screen")
	
	# Start hidden
	visible = false
	
	# Connect buttons
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func show_game_over(score: int):
	"""Display the game over screen with final score and high score"""
	final_score = score

	# Get current level info from LevelManager
	var level_name = LevelManager.get_current_level_name()
	var high_score = GameManager.get_high_score(level_name)

	if hint_label:
		hint_label.text = _pick_hint()

	# Show final score
	if final_score_label:
		final_score_label.text = "Final Score: %d" % final_score

	# Show attempt count
	if attempts_label:
		attempts_label.text = "Attempts: %d" % LevelManager.attempt_count

	# Show high score with "NEW HIGH SCORE!" if applicable
	if high_score_label:
		if score > high_score:
			high_score_label.text = "NEW HIGH SCORE!"
			high_score_label.modulate = Color.GOLD
		else:
			high_score_label.text = "High Score: %d" % high_score
			high_score_label.modulate = Color.WHITE

	# Remove oldest alien tech if the player had both slots filled
	var lost_tech := AlienTechManager.remove_oldest_tech()
	if not lost_tech.is_empty() and vbox_container and retry_button:
		var tech_lost_label := Label.new()
		tech_lost_label.text = "%s alien tech lost" % lost_tech
		tech_lost_label.modulate = Color(1.0, 0.45, 0.2)
		tech_lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox_container.add_child(tech_lost_label)
		vbox_container.move_child(tech_lost_label, retry_button.get_index())

	visible = true
	
	# Pause the game
	get_tree().paused = true
	
	# Focus the restart button for keyboard input
	if retry_button:
		retry_button.grab_focus()

func _on_retry_pressed():
	# Unpause
	get_tree().paused = false
	
	# Restart current level via LevelManager
	LevelManager.restart_current_level()

func _on_menu_pressed():
	# Unpause
	get_tree().paused = false
	
	# Return to main menu
	GameManager.load_main_menu()

func _on_quit_pressed():
	# Quit the game
	get_tree().quit()

func _input(event):
	if not visible:
		return
	
	# Keyboard/controller confirm
	if event.is_action_pressed("ui_accept"):
		if retry_button and retry_button.has_focus():
			_on_retry_pressed()
		elif menu_button and menu_button.has_focus():
			_on_menu_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()
