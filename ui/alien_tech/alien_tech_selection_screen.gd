extends CanvasLayer
class_name AlienTechSelectionScreen

@onready var title_label:     Label         = $Control/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var subtitle_label:  Label         = $Control/PanelContainer/MarginContainer/VBoxContainer/SubtitleLabel
@onready var cards_container: HBoxContainer = $Control/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer
@onready var slot_label:      Label         = $Control/PanelContainer/MarginContainer/VBoxContainer/SlotLabel

var _pending_tech_id: String = ""
var _awaiting_slot_choice: bool = false

func _ready():
	add_to_group("alien_tech_selection")
	visible = false
	AlienTechManager.selection_ready.connect(_on_selection_ready)

func _on_selection_ready(choices: Array):
	if choices.is_empty():
		return
	_awaiting_slot_choice = false
	_pending_tech_id = choices[0].get("id", "")
	_build_tech_display(choices[0])
	if slot_label:
		slot_label.visible = false
	visible = true
	get_tree().paused = true

func _hide_screen():
	visible = false
	get_tree().paused = false
	_clear_cards()

func _build_tech_display(tech: Dictionary):
	_clear_cards()
	if title_label:
		title_label.text = "Alien Tech Found!"
	if subtitle_label:
		var mode_text = "ACTIVE" if tech.get("needs_input", false) else "PASSIVE"
		subtitle_label.text = "%s  [%s]\n%s" % [tech.get("name", "?"), mode_text, tech.get("description", "")]
	if not cards_container:
		return

	var tech_color: Color = tech.get("color", Color.WHITE)

	var equip_btn = Button.new()
	equip_btn.text = "Equip"
	equip_btn.custom_minimum_size = Vector2(120, 50)
	equip_btn.focus_mode = Control.FOCUS_ALL
	equip_btn.add_theme_font_size_override("font_size", 11)
	equip_btn.modulate = tech_color.lerp(Color.WHITE, 0.35)
	equip_btn.pressed.connect(_on_equip_pressed)
	cards_container.add_child(equip_btn)
	equip_btn.grab_focus()

	var skip_btn = Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(80, 50)
	skip_btn.focus_mode = Control.FOCUS_ALL
	skip_btn.add_theme_font_size_override("font_size", 11)
	skip_btn.pressed.connect(_on_cancel)
	cards_container.add_child(skip_btn)

func _clear_cards():
	if not cards_container:
		return
	for child in cards_container.get_children():
		child.queue_free()

func _on_equip_pressed():
	if _pending_tech_id.is_empty():
		_hide_screen()
		return
	var empty_slot = AlienTechManager.find_empty_slot()
	if empty_slot != -1:
		AlienTechManager.assign_tech(_pending_tech_id, empty_slot)
		_hide_screen()
	else:
		_awaiting_slot_choice = true
		_show_slot_choice_ui(_pending_tech_id)

func _show_slot_choice_ui(incoming_id: String):
	_clear_cards()
	var incoming = AlienTechRegistry.get_tech(incoming_id)
	if title_label:
		title_label.text = "Both slots full — replace which?"
	if subtitle_label:
		subtitle_label.text = "Equipping: %s" % incoming.get("name", "?")
	if slot_label:
		slot_label.visible = false
	if not cards_container:
		return
	var first_btn: Button = null
	for i in AlienTechManager.MAX_SLOTS:
		var existing = AlienTechManager.slots[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(160, 60)
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 9)
		var slot_side = "Left (LB)" if i == 0 else "Right (RB)"
		var existing_name = existing.get("name", "Empty") if not existing.is_empty() else "Empty"
		btn.text = "Slot %s — replace: %s" % [slot_side, existing_name]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var captured: int = i
		btn.pressed.connect(func(): _on_replace_pressed(captured))
		cards_container.add_child(btn)
		if first_btn == null:
			first_btn = btn
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(70, 60)
	cancel.focus_mode = Control.FOCUS_ALL
	cancel.add_theme_font_size_override("font_size", 9)
	cancel.pressed.connect(_on_cancel)
	cards_container.add_child(cancel)
	if first_btn:
		first_btn.grab_focus()

func _on_replace_pressed(slot_index: int):
	if _pending_tech_id.is_empty():
		_hide_screen()
		return
	AlienTechManager.assign_tech(_pending_tech_id, slot_index)
	_hide_screen()

func _on_cancel():
	_pending_tech_id = ""
	_awaiting_slot_choice = false
	_hide_screen()

func _input(event: InputEvent):
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
