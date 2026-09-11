# pause_menu.gd
extends CanvasLayer
class_name PauseMenu

## Pause menu — toggled by the "pause" input action during gameplay

const _VBOX := "Control/CenterContainer/PanelContainer/VBoxContainer"
const _TECH := "Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoContainer"

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")

var _sfx_nav:    AudioStreamPlayer
var _sfx_select: AudioStreamPlayer

@onready var resume_button    = $Control/CenterContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var swap_tech_button = $Control/CenterContainer/PanelContainer/VBoxContainer/SwapTechButton
@onready var options_button   = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsButton
@onready var quit_button      = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton
@onready var guide_screen     = $GuideScreen

@onready var slot_l_icon: TextureRect = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLIcon
@onready var slot_l_name: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLName
@onready var slot_l_desc: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLDesc

@onready var slot_r_icon: TextureRect = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRIcon
@onready var slot_r_name: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRName
@onready var slot_r_desc: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRDesc

func _ready():
	add_to_group("pause_menu")
	visible = false

	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	_sfx_nav.volume_db = -10.0
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = -10.0
	add_child(_sfx_select)

	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
		resume_button.focus_entered.connect(func(): _sfx_nav.play())
	if swap_tech_button:
		swap_tech_button.pressed.connect(_on_swap_tech_pressed)
		swap_tech_button.focus_entered.connect(func(): _sfx_nav.play())
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
		options_button.focus_entered.connect(func(): _sfx_nav.play())
	if quit_button:
		quit_button.text = "Quit to Menu"
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(func(): _sfx_nav.play())

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
	if _sfx_select:
		_sfx_select.play()
	_resume()

func _on_options_pressed():
	if _sfx_select:
		_sfx_select.play()
	visible = false
	if guide_screen and guide_screen.has_method("show_guide"):
		guide_screen.show_guide(func():
			visible = true
			if resume_button:
				resume_button.grab_focus()
		)

func _on_swap_tech_pressed():
	if _sfx_select:
		_sfx_select.play()
	AlienTechManager.swap_slots()
	_update_tech_display()

func _update_tech_display():
	_update_slot(0, AlienTechManager.slots[0], slot_l_icon, slot_l_name, slot_l_desc)
	_update_slot(1, AlienTechManager.slots[1], slot_r_icon, slot_r_name, slot_r_desc)

func _update_slot(slot_index: int, slot: Dictionary, icon: TextureRect, name_lbl: Label, desc_lbl: Label):
	if slot.is_empty():
		if icon:
			icon.modulate = Color(0.4, 0.4, 0.4, 1.0)
		if name_lbl:
			name_lbl.text = "— empty —"
			name_lbl.modulate = Color(0.5, 0.5, 0.5, 1.0)
		if desc_lbl:
			desc_lbl.text = ""
	else:
		var tech_color: Color = slot.get("color", Color.WHITE)
		if icon:
			icon.modulate = Color.WHITE
		if name_lbl:
			name_lbl.text = slot.get("name", "")
			name_lbl.modulate = tech_color
		if desc_lbl:
			var desc_text: String = slot.get("description", "")
			# Hot-effect text is a surprise discovered through play — only ever
			# shown once the tech is actually hot, never as a spoiler up front.
			if AlienTechManager.is_slot_hot(slot_index):
				var hot_text: String = slot.get("hot_description", "")
				if not hot_text.is_empty():
					desc_text += "\n[HOT] %s" % hot_text
			desc_lbl.text = desc_text
			desc_lbl.modulate = Color(0.88, 0.88, 0.88, 1.0)

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
	if _sfx_select:
		_sfx_select.play()
	_show_save_prompt(func():
		get_tree().paused = false
		GameManager.load_main_menu()
	)
