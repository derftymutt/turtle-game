# main_menu.gd
extends CanvasLayer

## Main Menu - Level selection screen with Guide button

@onready var title_label = $Control/CenterContainer/VBoxContainer/TitleLabel
@onready var level_container = $Control/CenterContainer/VBoxContainer/LevelContainer

var guide_screen: GuideScreen = null

func _ready():
	# Find guide screen in the scene
	guide_screen = get_tree().get_first_node_in_group("guide_screen")
	
	# Create level and menu buttons
	_create_level_buttons()

func _create_level_buttons():
	"""Create a button for each registered level"""
	
	# === START GAME BUTTON (Big, prominent) ===
	var start_button = Button.new()
	start_button.text = "Start Game"
	start_button.custom_minimum_size = Vector2(150, 40)
	start_button.add_theme_font_size_override("font_size", 18)
	start_button.pressed.connect(_on_start_game_pressed)
	
	if level_container:
		level_container.add_child(start_button)
	
	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	if level_container:
		level_container.add_child(spacer1)
	
	# === LEVEL SELECT BUTTONS (Smaller, dev tools) ===
	# Get levels from LevelManager instead of GameManager
	for level_num in LevelManager.level_scenes.keys():
		var button = Button.new()
		
		# Format level name and display high score
		var level_name = "level_%d" % level_num
		var display_name = "Level %d" % level_num
		var high_score = GameManager.get_high_score(level_name)
		button.text = "%s\nHigh Score: %d" % [display_name, high_score]
		button.custom_minimum_size = Vector2(100, 30)
		button.add_theme_font_size_override("font_size", 12)
		
		# Connect button to load level by number
		button.pressed.connect(func(): _on_level_selected(level_num))
		
		if level_container:
			level_container.add_child(button)
	
	# Add spacing
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	if level_container:
		level_container.add_child(spacer2)
	
	# === GUIDE BUTTON ===
	var guide_button = Button.new()
	guide_button.text = "Guide"
	guide_button.custom_minimum_size = Vector2(100, 20)
	guide_button.add_theme_font_size_override("font_size", 12)
	guide_button.pressed.connect(_on_guide_pressed)
	
	if level_container:
		level_container.add_child(guide_button)
	
	# === QUIT BUTTON ===
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(100, 20)
	quit_button.add_theme_font_size_override("font_size", 12)
	quit_button.pressed.connect(_on_quit_pressed)
	
	if level_container:
		level_container.add_child(quit_button)
	
	# Focus "Start Game" button for keyboard/controller input
	if level_container.get_child_count() > 0:
		start_button.grab_focus()

func _on_start_game_pressed():
	"""Start from level 1 (main game flow)"""
	print("Starting game from Level 1")
	
	# Reset game state
	GameManager.reset_game()
	
	# Load level 1 via LevelManager
	LevelManager.load_level(1)

func _on_level_selected(level_num: int):
	"""Load a specific level (dev/testing)"""
	print("Loading level: ", level_num)
	
	# Reset carrying state (don't carry pieces between level jumps)
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	
	# Load level via LevelManager
	LevelManager.load_level(level_num)

func _on_guide_pressed():
	"""Show the guide screen"""
	if guide_screen and guide_screen.has_method("show_guide"):
		visible = false  # Hide main menu
		guide_screen.show_guide()
	else:
		push_warning("MainMenu: Guide screen not found!")

func _on_quit_pressed():
	"""Quit the game"""
	get_tree().quit()

func show_menu():
	"""Called by guide screen when returning to menu"""
	visible = true
	
	# Refocus first button to prevent input leaking
	if level_container and level_container.get_child_count() > 0:
		level_container.get_child(0).grab_focus()
