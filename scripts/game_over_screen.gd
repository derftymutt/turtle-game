extends CanvasLayer
class_name GameOverScreen

## Game Over screen with restart and quit options

@onready var game_over_panel = $CenterContainer/PanelContainer
@onready var final_score_label = $CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var restart_button = $CenterContainer/PanelContainer/VBoxContainer/RestartButton
@onready var quit_button = $CenterContainer/PanelContainer/VBoxContainer/QuitButton

var final_score: int = 0

func _ready():
	add_to_group("game_over_screen")
	
	# Start hidden
	visible = false
	
	# Connect buttons
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func show_game_over(score: int):
	"""Display the game over screen with final score"""
	final_score = score
	
	if final_score_label:
		final_score_label.text = "Final Score: %d" % final_score
	
	visible = true
	
	# Pause the game
	get_tree().paused = true
	
	# Focus the restart button for keyboard input
	if restart_button:
		restart_button.grab_focus()

func _on_restart_pressed():
	# Unpause
	get_tree().paused = false
	
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_quit_pressed():
	# Quit the game
	get_tree().quit()

func _input(event):
	# Allow restart with spacebar/enter/any controller button when game over
	if visible:
		# Keyboard: spacebar or enter
		if event.is_action_pressed("ui_accept"):
			_on_restart_pressed()
			return
		
		# Controller: any button press (joypad buttons)
		if event is InputEventJoypadButton and event.pressed:
			# Check which button is focused and activate it
			if restart_button and restart_button.has_focus():
				_on_restart_pressed()
			elif quit_button and quit_button.has_focus():
				_on_quit_pressed()
			return
