extends CanvasLayer
class_name AlienTechHelpDialog

## Info popup opened from the "?" button on the Alien Tech selection screen.
## Same green-bordered, blue-carded card as TurtleConfirmDialog (see
## ui/shared/turtle_confirm_dialog.gd), but:
##  - the backdrop is fully opaque, not translucent — the selection screen
##    behind it has its own living purple/pink glow (see
##    alien_tech_selection_screen.gd's _update_menu_flair()) that would keep
##    shining through a half-see-through overlay and fight with plain help
##    text sitting on top of it.
##  - the body is a RichTextLabel instead of a plain Label, so the Left/Right
##    tech slot icons can sit inline with their sentences — same technique as
##    tutorial_director.gd's inline-icon prompts (_show_intro(), etc).
## Only ever has a single "Got it" option, styled via TurtleOptionList like
## every other selectable option in this game (turtle indicator + green
## shine on focus).

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")
const _LEFT_SLOT_ICON  = preload("res://ui/hud/sprites/tech_left_icon.png")
const _RIGHT_SLOT_ICON = preload("res://ui/hud/sprites/tech_right_icon.png")

const _PANEL_BG_COLOR := Color(0.03, 0.1654902, 0.415, 1.0)
const _PANEL_BORDER_COLOR := Color(0.4, 1.0, 0.45, 1.0)
const _OVERLAY_COLOR := Color(0, 0.3019608, 1, 1.0)

const _CARD_WIDTH: float = 380.0
const _BODY_FONT_SIZE: int = 13
const _OPTION_FONT_SIZE: int = 16
# Same size the tech slot panels use for these icons (SlotLIcon/SlotRIcon in
# alien_tech_selection_screen.tscn) — keeps this dialog's inline icons
# reading as the same symbol, not a differently-sized reprint of it.
const _SLOT_ICON_SIZE: int = 14

var _sfx_nav: AudioStreamPlayer
var _sfx_select: AudioStreamPlayer
var _option_list: TurtleOptionList
var _resolved: bool = false
var _previous_focus: Control = null


func show_dialog() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Same reasoning as TurtleConfirmDialog: nested CanvasLayers composite by
	# `layer` number globally, so this needs to sit above the alien tech
	# selection screen it was opened from.
	layer = 10
	_previous_focus = get_viewport().gui_get_focus_owner()
	# Same reasoning as TurtleConfirmDialog: a low process_priority makes our
	# _input() run before the selection screen's own, so set_input_as_handled()
	# actually stops ui_cancel from also reaching it.
	process_priority = -1000

	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	add_child(_sfx_select)

	var overlay := ColorRect.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.color = _OVERLAY_COLOR
	add_child(overlay)

	var control := Control.new()
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(control)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	control.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _PANEL_BG_COLOR
	style.set_border_width_all(2)
	style.border_color = _PANEL_BORDER_COLOR
	style.content_margin_left = 16.0
	style.content_margin_top = 14.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_CARD_WIDTH, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var body := RichTextLabel.new()
	body.fit_content = true
	body.scroll_active = false
	body.add_theme_font_size_override("normal_font_size", _BODY_FONT_SIZE)
	vbox.add_child(body)
	_build_body(body)

	var options_column := VBoxContainer.new()
	options_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_column.add_theme_constant_override("separation", 6)
	vbox.add_child(options_column)

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(control)

	var got_it_btn := _option_list.create_option(options_column, "Got it", _OPTION_FONT_SIZE, _dismiss)
	got_it_btn.focus_entered.connect(func(): _sfx_nav.play())

	# Same layout-settle race every other TurtleOptionList consumer hits on
	# first show — see pause_menu.gd's _open() for the full explanation.
	await get_tree().process_frame
	await get_tree().process_frame
	got_it_btn.grab_focus()


func _build_body(body: RichTextLabel) -> void:
	body.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	body.append_text("Alien Techs are special powerups.\n\n")
	body.append_text("You can equip at most 2 at a time, one each in your Left and Right tech slots.\n\n")
	body.append_text("The left slot ")
	body.add_image(_LEFT_SLOT_ICON, _SLOT_ICON_SIZE, _SLOT_ICON_SIZE)
	body.append_text(" is triggered with LB (Left Bumper) or \"%s\"\n" % GameSettings.tech_slot_key_label(0))
	body.append_text("The right slot ")
	body.add_image(_RIGHT_SLOT_ICON, _SLOT_ICON_SIZE, _SLOT_ICON_SIZE)
	body.append_text(" is triggered with RB (Right Bumper) or \"%s\"\n\n" % GameSettings.tech_slot_key_label(1))
	body.append_text("Some techs are always on, while some require triggering.\n")
	body.append_text("This info is displayed in the info box describing the tech.\n(Also shown in the pause menu).")
	body.pop()


func _dismiss() -> void:
	if _resolved:
		return
	_resolved = true
	if _sfx_select:
		_sfx_select.play()
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()
	queue_free()


func _input(event: InputEvent) -> void:
	if _resolved:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_dismiss()
