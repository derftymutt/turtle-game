extends CanvasLayer
class_name GameOverScreen

## Game Over screen with restart, main menu, and quit options

@onready var game_over_panel = $Control/CenterContainer/PanelContainer
@onready var final_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var high_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/HighScoreLabel
@onready var restart_button = $Control/CenterContainer/PanelContainer/VBoxContainer/RestartButton
@onready var menu_button = $Control/CenterContainer/PanelContainer/VBoxContainer/MenuButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton

var final_score: int = 0
var current_level: String = ""

func _ready():
	add_to_group("game_over_screen")
	
	# Start hidden
	visible = false
	
	# Connect buttons
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func show_game_over(score: int, level_name: String = ""):
	"""Display the game over screen with final score and high score"""
	final_score = score
	current_level = level_name
	
	if final_score_label:
		final_score_label.text = "Final Score: %d" % final_score
	
	# Show high score
	if high_score_label and not level_name.is_empty():
		var high_score = GameManager.get_high_score(level_name)
		if score > high_score:
			high_score_label.text = "NEW HIGH SCORE!"
			high_score_label.modulate = Color.GOLD
		else:
			high_score_label.text = "High Score: %d" % high_score
			high_score_label.modulate = Color.WHITE
	
	visible = true
	
	# Pause the game
	get_tree().paused = true
	
	# Focus the restart button for keyboard input
	if restart_button:
		restart_button.grab_focus()

func _on_restart_pressed():
	# Unpause
	get_tree().paused = false
	
	# Restart through GameManager
	if not current_level.is_empty():
		GameManager.restart_current_level()
	else:
		# Fallback
		get_tree().reload_current_scene()

func _on_menu_pressed():
	print("Menu button pressed!")
	print("Current level: ", current_level)
	print("GameManager exists: ", GameManager != null)
	
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
	
	# Any button press activates focused button
	if event is InputEventKey and event.pressed and not event.echo:
		if restart_button and restart_button.has_focus():
			_on_restart_pressed()
		elif menu_button and menu_button.has_focus():
			_on_menu_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()
	
	# Controller buttons
	if event is InputEventJoypadButton and event.pressed:
		if restart_button and restart_button.has_focus():
			_on_restart_pressed()
		elif menu_button and menu_button.has_focus():
			_on_menu_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()
