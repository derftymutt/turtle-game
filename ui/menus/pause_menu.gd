# pause_menu.gd
extends CanvasLayer
class_name PauseMenu

## Pause menu — toggled by the "pause" input action during gameplay

const _VBOX := "Control/CenterContainer/PanelContainer/VBoxContainer"
const _TECH := "Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoContainer"

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")

# Same input-hint / status-line convention as the alien tech selection
# screen, so the two read as one system.
const _SLOT_INPUT_HINTS: Array[String] = ["LB · Q", "RB · E"]
const _ALWAYS_ACTIVE_TEXT: String = "Always Active"
const _INPUT_HINT_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)
const _ALWAYS_ACTIVE_COLOR: Color = Color(0.55, 1.0, 0.6, 1.0)

const _BLINK_PERIOD_MSEC: int = 300
const _BLINK_LOW_ALPHA: float = 0.35

var _sfx_nav:    AudioStreamPlayer
var _sfx_select: AudioStreamPlayer

# Whether each slot's input-hint line and "Hot!" badge should currently
# blink (set on each display refresh, read every _process).
var _slot_input_blinking: Array[bool] = [false, false]
var _slot_hot_blinking: Array[bool] = [false, false]

@onready var resume_button    = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/ResumeButton
@onready var swap_tech_button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/SwapTechButton
@onready var options_button   = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/OptionsButton
@onready var quit_button      = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/QuitButton
@onready var guide_screen     = $GuideScreen
@onready var _control: Control = $Control

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

@onready var slot_l_icon:  TextureRect = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLIcon
@onready var slot_l_input: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLInput
@onready var slot_l_name:  Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLName
@onready var slot_l_desc:  Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLDesc
@onready var slot_l_hot_row:   VBoxContainer = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLHotRow
@onready var slot_l_hot_badge: Label         = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLHotRow/SlotLHotBadge
@onready var slot_l_hot_desc:  Label         = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLRow/SlotLTextContainer/SlotLHotRow/SlotLHotDesc

@onready var slot_r_icon:  TextureRect = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRIcon
@onready var slot_r_input: Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRInput
@onready var slot_r_name:  Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRName
@onready var slot_r_desc:  Label       = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRDesc
@onready var slot_r_hot_row:   VBoxContainer = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRHotRow
@onready var slot_r_hot_badge: Label         = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRHotRow/SlotRHotBadge
@onready var slot_r_hot_desc:  Label         = $Control/CenterContainer/PanelContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRRow/SlotRTextContainer/SlotRHotRow/SlotRHotDesc

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

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)

	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
		resume_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(resume_button)
	if swap_tech_button:
		swap_tech_button.pressed.connect(_on_swap_tech_pressed)
		swap_tech_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(swap_tech_button)
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
		options_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(options_button)
	if quit_button:
		quit_button.text = "Quit to Menu"
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(quit_button)

func _input(event):
	if event.is_action_pressed("pause"):
		if visible:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	var blink_on := int(Time.get_ticks_msec() / _BLINK_PERIOD_MSEC) % 2 == 0
	var alpha := 1.0 if blink_on else _BLINK_LOW_ALPHA
	if _slot_input_blinking[0]:
		slot_l_input.modulate.a = alpha
	if _slot_input_blinking[1]:
		slot_r_input.modulate.a = alpha
	if _slot_hot_blinking[0]:
		slot_l_hot_badge.modulate.a = alpha
	if _slot_hot_blinking[1]:
		slot_r_hot_badge.modulate.a = alpha

func _open():
	get_tree().paused = true
	visible = true
	_update_tech_display()
	# This CanvasLayer's Control subtree doesn't get a real layout pass while
	# visible=false, so a button's get_global_rect() is still stale for a
	# frame or two after it flips true — wait for layout to actually settle
	# before positioning the turtle indicator against it (same class of fix
	# as main_menu.gd's _reveal_options; two frames here since one proved
	# borderline once the panel gained its own border/margin stylebox).
	await get_tree().process_frame
	await get_tree().process_frame
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
			await get_tree().process_frame
			await get_tree().process_frame
			if resume_button:
				resume_button.grab_focus()
		)

func _on_swap_tech_pressed():
	if _sfx_select:
		_sfx_select.play()
	AlienTechManager.swap_slots()
	_update_tech_display()

func _update_tech_display():
	_update_slot(0, AlienTechManager.slots[0], slot_l_icon, slot_l_input, slot_l_name, slot_l_desc, slot_l_hot_row, slot_l_hot_desc)
	_update_slot(1, AlienTechManager.slots[1], slot_r_icon, slot_r_input, slot_r_name, slot_r_desc, slot_r_hot_row, slot_r_hot_desc)

func _update_slot(slot_index: int, slot: Dictionary, icon: TextureRect, input_lbl: Label, name_lbl: Label, desc_lbl: Label, hot_row: VBoxContainer, hot_desc: Label):
	if slot.is_empty():
		if icon:
			icon.modulate = Color(0.4, 0.4, 0.4, 1.0)
		if input_lbl:
			input_lbl.visible = false
			input_lbl.modulate.a = 1.0
		_slot_input_blinking[slot_index] = false
		if name_lbl:
			name_lbl.text = "— empty —"
			name_lbl.modulate = Color(0.5, 0.5, 0.5, 1.0)
		if desc_lbl:
			desc_lbl.text = ""
		if hot_row:
			hot_row.visible = false
		_slot_hot_blinking[slot_index] = false
		return

	var tech_color: Color = slot.get("color", Color.WHITE)
	var needs_input: bool = slot.get("needs_input", false)
	if icon:
		icon.modulate = Color.WHITE
	if name_lbl:
		name_lbl.text = slot.get("name", "")
		name_lbl.modulate = tech_color
	if input_lbl:
		input_lbl.visible = true
		_slot_input_blinking[slot_index] = true
		if needs_input:
			input_lbl.text = _SLOT_INPUT_HINTS[slot_index]
			input_lbl.add_theme_color_override("font_color", _INPUT_HINT_COLOR)
		else:
			input_lbl.text = _ALWAYS_ACTIVE_TEXT
			input_lbl.add_theme_color_override("font_color", _ALWAYS_ACTIVE_COLOR)
	if desc_lbl:
		desc_lbl.text = slot.get("description", "")
		desc_lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Hot-effect text is a surprise discovered through play — only ever
	# shown once the tech is actually hot, never as a spoiler up front.
	var hot_text: String = ""
	if AlienTechManager.is_slot_hot(slot_index):
		hot_text = slot.get("hot_description", "")
	if hot_row:
		if hot_text.is_empty():
			hot_row.visible = false
			_slot_hot_blinking[slot_index] = false
		else:
			hot_row.visible = true
			_slot_hot_blinking[slot_index] = true
			if hot_desc:
				hot_desc.text = hot_text

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
