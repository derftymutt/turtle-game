extends CanvasLayer
class_name GuideScreen

@onready var content_label = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ContentLabel
@onready var page_indicator = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PageIndicator
@onready var prev_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/PrevButton
@onready var next_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/NextButton
@onready var back_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/BackButton

# NEW: Container for controls page with checkbox
@onready var controls_container = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ControlsContainer
@onready var controls_text = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ControlsContainer/ControlsText
@onready var invert_thrust_checkbox = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ControlsContainer/InvertThrustCheckbox

var current_page: int = 0
var pages: Array[String] = []

func _ready():
	visible = false
	add_to_group("guide_screen")
	_build_pages()
	
	# Connect button signals
	if prev_button:
		prev_button.pressed.connect(_on_prev_pressed)
	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Connect checkbox signal
	if invert_thrust_checkbox:
		invert_thrust_checkbox.toggled.connect(_on_invert_thrust_toggled)
		invert_thrust_checkbox.button_pressed = GameSettings.thrust_inverted

	# Fix focus navigation on page 2: the disabled NextButton sits between the
	# checkbox and the other buttons, causing dpad DOWN from the checkbox to dead-end.
	# Explicitly wire neighbors to route around it.
	if invert_thrust_checkbox and prev_button and back_button:
		invert_thrust_checkbox.focus_neighbor_bottom = invert_thrust_checkbox.get_path_to(prev_button)
		prev_button.focus_neighbor_top = prev_button.get_path_to(invert_thrust_checkbox)
		back_button.focus_neighbor_top = back_button.get_path_to(invert_thrust_checkbox)

	_update_page()

func show_guide():
	"""Display the guide screen"""
	visible = true
	current_page = 0
	_update_page()
	
	if next_button and not next_button.disabled:
		next_button.grab_focus()
	elif back_button:
		back_button.grab_focus()

func hide_guide():
	"""Hide the guide screen"""
	visible = false

func _build_pages():
	var page1 = """


DONT PANIC!
- Pick up UFO parts from the ocean floor and bring them to your UFO workshop to assemble
the UFO and get to the next level. "X" will drop a carried piece pre delivery (they're heavy)
- Each level requires a different amount of parts, shown in top left of screen
- Health: Lost from enemy contact/projectiles and running out of air. 
	Gained by collecting health plants that spawn on walls every 300 points
- Air: lost while underwater. Gained by surfacing or collecting air bubbles.
- Energy: Lost by swimming. Gained by resting, especially on walls (the relief!)
- Fast movement gives you a glowing trail of "Super Speed"
	Super Speed = invincibility + damage enemies on contact
- Cleanup ocean trash by shooting complete groups to spawn powerups
- Cleanup space trash as well by shooting complete groups
- Collect stars for points. Ocean floor stars are most valuable. 
	Points also given for shooting ocean/space trash and UFO piece delivery. Leave no trace!
"""
	
	# Page 2 is now just the basic controls text
	# The checkbox will be shown separately below it
	var page2 = """


	***CONTROLS***

	THRUST: Left Stick / WASD
	SHOOT: Right Stick / IJKL
	FLIPPER LEFT: L Trigger / L Shift
	FLIPPER RIGHT: R Trigger / R Shift
	DROP UFO PIECE: X / Space

	CONTROL OPTIONS:"""
	
	pages = [page1, page2]

func _update_page():
	"""Update displayed content based on current page"""
	if current_page < 0:
		current_page = 0
	if current_page >= pages.size():
		current_page = pages.size() - 1
	
	# Show either regular content or controls container
	if current_page == 1:  # Controls page
		# Hide regular label, show controls container
		if content_label:
			content_label.visible = false
		if controls_container:
			controls_container.visible = true
		if controls_text:
			controls_text.text = pages[current_page]
	else:  # Other pages
		# Show regular label, hide controls container
		if content_label:
			content_label.visible = true
			content_label.text = pages[current_page]
		if controls_container:
			controls_container.visible = false
	
	# Update page indicator
	if page_indicator:
		page_indicator.text = "Page %d / %d" % [current_page + 1, pages.size()]
	
	# Update button states
	if prev_button:
		prev_button.disabled = (current_page == 0)
	if next_button:
		next_button.disabled = (current_page == pages.size() - 1)

	# When NextButton is disabled it blocks horizontal dpad movement between
	# PrevButton and BackButton. Wire them directly on the last page and reset
	# to automatic navigation on all other pages.
	if prev_button and back_button:
		if next_button.disabled:
			prev_button.focus_neighbor_right = prev_button.get_path_to(back_button)
			back_button.focus_neighbor_left = back_button.get_path_to(prev_button)
		else:
			prev_button.focus_neighbor_right = NodePath("")
			back_button.focus_neighbor_left = NodePath("")

func _on_prev_pressed():
	if current_page > 0:
		current_page -= 1
		_update_page()

func _on_next_pressed():
	if current_page < pages.size() - 1:
		current_page += 1
		_update_page()

func _on_back_pressed():
	hide_guide()
	var main_menu = get_parent()
	if main_menu and main_menu.has_method("show_menu"):
		main_menu.show_menu()

func _on_invert_thrust_toggled(pressed: bool):
	GameSettings.set_thrust_inverted(pressed)
	print("Thrust inverted: ", pressed)
