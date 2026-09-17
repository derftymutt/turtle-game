extends CanvasLayer
class_name TurtleConfirmDialog

## Reusable inline confirm dialog — a green-bordered, blue-carded modal with
## plain-text + turtle + sheen options (see turtle_option_list.gd), replacing
## Godot's native ConfirmationDialog (a Window popup whose title bar/buttons
## can't be restyled to match the rest of this UI). Appears on top of
## whatever's already showing — it's a small centered card over a translucent
## backdrop, not a full-screen takeover.
##
## Usage:
##   var dialog := TurtleConfirmDialog.new()
##   add_child(dialog)  # any live node — it's a self-contained CanvasLayer
##   dialog.show_dialog("Save and resume at Level %d later?" % level, [
##       {"text": "Save", "callback": func(): SaveManager.save_game()},
##       {"text": "Don't Save"},
##       {"text": "Cancel", "is_cancel": true},
##   ], "Save Progress?")
##
## Each option dict is {text: String, callback: Callable (optional),
## is_cancel: bool (optional)}. The dialog frees itself once an option is
## chosen (after calling its callback, if any) or when dismissed via
## ui_cancel (which acts like pressing whichever option has is_cancel=true,
## or just closes with no callback if none is marked).

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")

const _PANEL_BG_COLOR := Color(0.03, 0.1654902, 0.415, 1.0)
const _PANEL_BORDER_COLOR := Color(0.4, 1.0, 0.45, 1.0)
const _OVERLAY_COLOR := Color(0, 0.3019608, 1, 0.5)

const _CARD_WIDTH: float = 380.0
const _OPTION_FONT_SIZE: int = 16

var _sfx_nav: AudioStreamPlayer
var _sfx_select: AudioStreamPlayer
var _option_list: TurtleOptionList
var _options: Array = []
var _resolved: bool = false
var _previous_focus: Control = null


func show_dialog(message: String, options: Array, title: String = "") -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# This dialog is always add_child()'d onto whatever menu is opening it, so
	# it's a CanvasLayer nested inside that menu's own CanvasLayer. Nested
	# CanvasLayers composite purely by `layer` number, globally, regardless of
	# tree nesting — leaving this at the default (1), the same as every menu
	# that might spawn it, means which one wins is undefined (it happened to
	# render on top for pause_menu/game_over/main_menu but landed *underneath*
	# alien_tech_selection_screen). Force it above anything else in the game.
	layer = 10
	_options = options
	# Freeing this dialog's own focused button (in _choose(), below) leaves
	# the viewport with no focus owner at all — nothing restores it
	# automatically, so whichever button opened this dialog would silently
	# stop receiving input afterward (its turtle indicator just stays put,
	# masking the fact that nothing actually has focus anymore). Restore it
	# explicitly once this dialog resolves.
	_previous_focus = get_viewport().gui_get_focus_owner()
	# Godot dispatches _input()/_unhandled_input() tree-wide regardless of
	# visual stacking — being on top on screen doesn't stop an ancestor's own
	# _input() (e.g. pause_menu.gd listening for the raw "pause" action) from
	# also reacting to the same key press. A very low process_priority makes
	# ours run first in that dispatch order so set_input_as_handled() below
	# actually stops it from reaching the menu underneath — and _input()
	# (not _unhandled_input()) is required for that priority to matter, since
	# _unhandled_input only ever sees events no _input() already consumed.
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

	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 18)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title_label)

	var message_label := Label.new()
	message_label.text = message
	message_label.add_theme_font_size_override("font_size", 13)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message_label)

	var options_column := VBoxContainer.new()
	options_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_column.add_theme_constant_override("separation", 6)
	vbox.add_child(options_column)

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(control)

	var first_button: Button = null
	for option: Dictionary in _options:
		var btn := _option_list.create_option(options_column, option.get("text", ""), _OPTION_FONT_SIZE, func(): _choose(option))
		btn.focus_entered.connect(func(): _sfx_nav.play())
		if first_button == null:
			first_button = btn

	# Same layout-settle race every other TurtleOptionList consumer hits on
	# first show — see pause_menu.gd's _open() for the full explanation.
	await get_tree().process_frame
	await get_tree().process_frame
	if first_button:
		first_button.grab_focus()


func _choose(option: Dictionary) -> void:
	if _resolved:
		return
	_resolved = true
	if _sfx_select:
		_sfx_select.play()
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()
	var callback: Callable = option.get("callback", Callable())
	if callback.is_valid():
		callback.call()
	queue_free()


func _input(event: InputEvent) -> void:
	if _resolved:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		for option: Dictionary in _options:
			if option.get("is_cancel", false):
				_choose(option)
				return
		_resolved = true
		queue_free()
