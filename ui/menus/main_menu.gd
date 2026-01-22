extends CanvasLayer

## Main Menu - Level selection screen

@onready var title_label = $Control/CenterContainer/VBoxContainer/TitleLabel
@onready var level_container = $Control/CenterContainer/VBoxContainer/LevelContainer

func _ready():
	# Create level buttons dynamically
	_create_level_buttons()

func _input(event):
	# Any key/button press activates focused button
	if event is InputEventKey and event.pressed and not event.echo:
		var focused = get_viewport().gui_get_focus_owner()
		if focused is Button:
			focused.pressed.emit()
	
	if event is InputEventJoypadButton and event.pressed:
		var focused = get_viewport().gui_get_focus_owner()
		if focused is Button:
			focused.pressed.emit()

func _create_level_buttons():
	"""Create a button for each registered level"""
	for level_id in GameManager.levels.keys():
		var button = Button.new()
		
		# Format level name nicely
		var display_name = level_id.replace("_", " ").capitalize()
		var high_score = GameManager.get_high_score(level_id)
		
		# Show level name and high score
		button.text = "%s\nHigh Score: %d" % [display_name, high_score]
		button.custom_minimum_size = Vector2(200, 60)
		
		# Connect button press
		button.pressed.connect(func(): _on_level_selected(level_id))
		
		# Add to container
		if level_container:
			level_container.add_child(button)
	
	# Add quit button
	var quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(200, 40)
	quit_button.pressed.connect(_on_quit_pressed)
	
	if level_container:
		level_container.add_child(quit_button)
		
	# Focus first button for keyboard/controller input
	if level_container.get_child_count() > 0:
		level_container.get_child(0).grab_focus()

func _on_level_selected(level_id: String):
	print("Loading level: ", level_id)
	GameManager.load_level(level_id)

func _on_quit_pressed():
	get_tree().quit()
