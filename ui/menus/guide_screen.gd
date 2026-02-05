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


  ***HOW TO PLAY***

- Collect stars for points. Twinkling stars on the sea floor are worth *ALOT* more
- Avoid enemies! Shoot piranhas. Invincible enemies shake when shot.
- Don't run out of breath! You will quickly lose health if you do. 
	- Gain breath from air bubbles (but don't pop them!) or surfacing
- Turtles can't kick forever! Mind your Stamina! (speed up recovery touching walls/flippers)
- Super Speed (from bumpers, flippers, swimming in shallow water) = invincibility + damage
- Stay alive and go for a high score! Can you get 500 points? 1000? More??"""
	
	# Page 2 is now just the basic controls text
	# The checkbox will be shown separately below it
	var page2 = """


***CONTROLS***

THRUST: Left Stick / WASD
SHOOT: Right Stick / IJKL
FLIPPER LEFT: L Trigger / L Shift
FLIPPER RIGHT: R Trigger / R Shift

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
