# pause_menu.gd
extends CanvasLayer
class_name PauseMenu

## Pause menu — toggled by the "pause" input action during gameplay

@onready var resume_button = $Control/CenterContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var swap_tech_button = $Control/CenterContainer/PanelContainer/VBoxContainer/SwapTechButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton
@onready var slot_l_label = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoContainer/SlotLLabel
@onready var slot_r_label = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoContainer/SlotRLabel

func _ready():
	add_to_group("pause_menu")
	visible = false

	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if swap_tech_button:
		swap_tech_button.pressed.connect(_on_swap_tech_pressed)
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

func _open():
	get_tree().paused = true
	visible = true
	_update_tech_display()
	if resume_button:
		resume_button.grab_focus()

func _resume():
	get_tree().paused = false
	visible = false

func _on_resume_pressed():
	_resume()

func _on_swap_tech_pressed():
	AlienTechManager.swap_slots()
	_update_tech_display()

func _update_tech_display():
	var slot_a = AlienTechManager.slots[0]
	var slot_b = AlienTechManager.slots[1]

	if slot_l_label:
		if slot_a.is_empty():
			slot_l_label.text = "[L] — empty —"
			slot_l_label.modulate = Color(0.6, 0.6, 0.6)
		else:
			slot_l_label.text = "[L] %s\n%s" % [slot_a.get("name", ""), slot_a.get("description", "")]
			var col = slot_a.get("color", Color.WHITE)
			slot_l_label.modulate = Color(col.r, col.g, col.b, 1.0)

	if slot_r_label:
		if slot_b.is_empty():
			slot_r_label.text = "[R] — empty —"
			slot_r_label.modulate = Color(0.6, 0.6, 0.6)
		else:
			slot_r_label.text = "[R] %s\n%s" % [slot_b.get("name", ""), slot_b.get("description", "")]
			var col = slot_b.get("color", Color.WHITE)
			slot_r_label.modulate = Color(col.r, col.g, col.b, 1.0)

func _show_save_prompt(action: Callable):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Save Progress?"
	dialog.dialog_text = "Save and resume at Level %d later?" % LevelManager.current_level_number
	dialog.ok_button_text = "Save"
	dialog.cancel_button_text = "Cancel"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	dialog.add_button("Don't Save", false, "no_save")
	dialog.confirmed.connect(func():
		SaveManager.save_game()
		dialog.queue_free()
		action.call()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action_name: StringName):
		if action_name == "no_save":
			dialog.queue_free()
			action.call()
	)
	dialog.popup_centered()

func _on_quit_pressed():
	_show_save_prompt(func():
		get_tree().paused = false
		GameManager.load_main_menu()
	)
