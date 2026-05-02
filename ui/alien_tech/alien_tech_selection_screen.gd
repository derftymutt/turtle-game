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
	_awaiting_slot_choice = false
	_pending_tech_id = ""
	_build_tech_cards(choices)
	if slot_label:
		slot_label.visible = false
	if title_label:
		title_label.text = "Alien Tech Acquired!"
	if subtitle_label:
		subtitle_label.text = "Choose an upgrade:"
	visible = true
	get_tree().paused = true

func _hide_screen():
	visible = false
	get_tree().paused = false
	_clear_cards()

func _build_tech_cards(choices: Array):
	_clear_cards()
	if not cards_container:
		return
	var first_btn: Button = null
	for tech in choices:
		var btn = _make_card(tech)
		cards_container.add_child(btn)
		if first_btn == null:
			first_btn = btn
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(80, 90)
	cancel.focus_mode = Control.FOCUS_ALL
	cancel.add_theme_font_size_override("font_size", 9)
	cancel.pressed.connect(_on_cancel)
	cards_container.add_child(cancel)
	if first_btn:
		first_btn.grab_focus()

func _make_card(tech: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(140, 90)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 9)
	var mode_text = "ACTIVE" if tech.get("needs_input", false) else "PASSIVE"
	btn.text = "%s\n%s\n[%s]" % [tech.get("name", "?"), tech.get("description", ""), mode_text]
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var col: Color = tech.get("color", Color.WHITE)
	btn.modulate = col.lerp(Color.WHITE, 0.4)
	var id: String = tech.get("id", "")
	btn.pressed.connect(func(): _on_card_pressed(id))
	return btn

func _clear_cards():
	if not cards_container:
		return
	for child in cards_container.get_children():
		child.queue_free()

func _on_card_pressed(tech_id: String):
	var empty_slot = AlienTechManager.find_empty_slot()
	if empty_slot != -1:
		AlienTechManager.assign_tech(tech_id, empty_slot)
		_hide_screen()
	else:
		_pending_tech_id = tech_id
		_awaiting_slot_choice = true
		_show_slot_choice_ui(tech_id)

func _show_slot_choice_ui(incoming_id: String):
	_clear_cards()
	var incoming = AlienTechRegistry.get_tech(incoming_id)
	if title_label:
		title_label.text = "Both slots full — replace which?"
	if subtitle_label:
		subtitle_label.text = "Incoming: %s" % incoming.get("name", "?")
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
		btn.text = "Tech %s — replace: %s" % [slot_side, existing_name]
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
