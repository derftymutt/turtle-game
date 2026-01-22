extends CanvasLayer
class_name GuideScreen

## Simple two-page guide: How to Play + Controls

@onready var content_label = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ContentLabel
@onready var page_indicator = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PageIndicator
@onready var prev_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/PrevButton
@onready var next_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/NextButton
@onready var back_button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/BackButton

var current_page: int = 0
var pages: Array[String] = []

func _ready():
	visible = false
	_build_pages()
	
	# Connect button signals
	if prev_button:
		prev_button.pressed.connect(_on_prev_pressed)
	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	_update_page()

func show_guide():
	"""Display the guide screen"""
	visible = true
	current_page = 0
	_update_page()
	
	# Focus first button for controller navigation
	if prev_button:
		prev_button.grab_focus()

func hide_guide():
	"""Hide the guide screen"""
	visible = false

func _build_pages():
	var page1 = """
	
  ***HOW TO PLAY***

• Collect stars! Twinkling stars on the sea floor are worth the most
• Avoid enemies! (shoot piranhas)
• Don't run out of breath! Get air bubbles or surface when needed
• Turtles can't kick forever! Mind your Stamina!
• Flipper/Bumper super speed = invincibility + damage
• Can you get 500 points? 1000?"""
	
	var page2 = """
	
***CONTROLS***

THRUST: Left Stick / WASD
SHOOT: Right Stick / IJKL
FLIPPER LEFT: L Trigger / L Shift
FLIPPER RIGHT: R Trigger / R Shift"""
	
	pages = [page1, page2]

func _update_page():
	"""Update displayed content based on current page"""
	if current_page < 0:
		current_page = 0
	if current_page >= pages.size():
		current_page = pages.size() - 1
	
	# Update content
	if content_label:
		content_label.text = pages[current_page]
	
	# Update page indicator
	if page_indicator:
		page_indicator.text = "Page %d / %d" % [current_page + 1, pages.size()]
	
	# Update button states (disable when can't navigate further)
	if prev_button:
		prev_button.disabled = (current_page == 0)
	if next_button:
		next_button.disabled = (current_page == pages.size() - 1)

func _on_prev_pressed():
	"""Navigate to previous page"""
	if current_page > 0:
		current_page -= 1
		_update_page()

func _on_next_pressed():
	"""Navigate to next page"""
	if current_page < pages.size() - 1:
		current_page += 1
		_update_page()

func _on_back_pressed():
	"""Return to main menu"""
	hide_guide()
	
	# Find and show main menu
	var main_menu = get_parent()
	if main_menu and main_menu.has_method("show_menu"):
		main_menu.show_menu()
		# Prevent input from leaking to main menu
		get_viewport().set_input_as_handled()

func _input(event):
	"""Handle controller input for guide navigation"""
	if not visible:
		return
	
	# Controller button activates focused button (like main menu)
	if event is InputEventJoypadButton and event.pressed:
		var focused = get_viewport().gui_get_focus_owner()
		if focused is Button and not focused.disabled:
			focused.pressed.emit()
