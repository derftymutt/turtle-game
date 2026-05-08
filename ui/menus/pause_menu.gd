# pause_menu.gd
extends CanvasLayer
class_name PauseMenu

## Pause menu — toggled by the "pause" input action during gameplay

@onready var resume_button = $Control/CenterContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton

func _ready():
	add_to_group("pause_menu")
	visible = false

	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if quit_button:
		quit_button.text = "Quit to Menu"
		quit_button.pressed.connect(_on_quit_pressed)

func _input(event):
	if event.is_action_pressed("pause"):
		if visible:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed("ui_accept"):
		if resume_button and resume_button.has_focus():
			_on_resume_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()

func _open():
	get_tree().paused = true
	visible = true
	if resume_button:
		resume_button.grab_focus()

func _resume():
	get_tree().paused = false
	visible = false

func _on_resume_pressed():
	_resume()

func _show_save_prompt(action: Callable):
	"""Show a save-before-quitting dialog, then call action regardless of choice."""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Save Progress?"
	dialog.dialog_text = "Save and resume at Level %d later?" % LevelManager.current_level_number
	dialog.ok_button_text = "Save"
	dialog.cancel_button_text = "Don't Save"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	dialog.confirmed.connect(func():
		SaveManager.save_game()
		dialog.queue_free()
		action.call()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		action.call()
	)
	dialog.popup_centered()

func _on_quit_pressed():
	_show_save_prompt(func():
		get_tree().paused = false
		GameManager.load_main_menu()
	)
