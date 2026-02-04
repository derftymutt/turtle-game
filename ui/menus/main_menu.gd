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
	# Create level buttons
	for level_id in GameManager.levels.keys():
		var button = Button.new()
		
		# Format level name and display high score
		var display_name = level_id.replace("_", " ").capitalize()
		var high_score = GameManager.get_high_score(level_id)
		button.text = "%s\nHigh Score: %d" % [display_name, high_score]
		button.custom_minimum_size = Vector2(100, 30)  # Changed from 200x60
		
		# Optional: Make the font smaller
		button.add_theme_font_size_override("font_size", 12)  # Adjust size as needed
		
		# Connect button to load level
		button.pressed.connect(func(): _on_level_selected(level_id))
		
		if level_container:
			level_container.add_child(button)
	
	# Add guide button
	var guide_button = Button.new()
	guide_button.text = "Guide"
	guide_button.custom_minimum_size = Vector2(100, 20)  # Changed from 200x40
	guide_button.add_theme_font_size_override("font_size", 12)
	guide_button.pressed.connect(_on_guide_pressed)
	
	if level_container:
		level_container.add_child(guide_button)
	
	# Add quit button
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(100, 20)  # Changed from 200x40
	quit_button.add_theme_font_size_override("font_size", 12)
	quit_button.pressed.connect(_on_quit_pressed)
	
	if level_container:
		level_container.add_child(quit_button)
	
	# Focus first button for keyboard/controller input
	if level_container.get_child_count() > 0:
		level_container.get_child(0).grab_focus()

func _on_level_selected(level_id: String):
	"""Load the selected level"""
	print("Loading level: ", level_id)
	GameManager.load_level(level_id)

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
