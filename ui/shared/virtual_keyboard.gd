# virtual_keyboard.gd
extends VBoxContainer
class_name VirtualKeyboard

## On-screen keyboard for typing into a LineEdit with a gamepad (Godot's
## DisplayServer.virtual_keyboard_show() only works on mobile/web). A grid of
## key Buttons: the stick / D-pad moves between them through Godot's normal
## focus navigation, A presses the focused key.
##
## Shortcuts: B = Backspace, Y = Space.
##
## Typing goes into `target` at its caret, so the field's own max_length still
## applies. Text that was already in the field when the keyboard took over
## (a prefilled default) is replaced by the first letter typed, the same way a
## selected field behaves with a real keyboard. Letters auto-capitalise at the
## start of each word; the Shift key flips that for the next letter.
##
## Usage: VirtualKeyboard.new(), set `target`, add it to the tree, then
## focus_first_key(). Connect `done` for the Done key.

signal done

const _ROWS: Array[String] = [
	"ABCDEFGHIJ",
	"KLMNOPQRST",
	"UVWXYZ-.'!",
	"1234567890",
]
const KEY_FONT_SIZE := 14
const KEY_SIZE := Vector2(20, 20)

var target: LineEdit = null

var _letter_keys: Array[Button] = []
var _first_key: Button = null
var _shift := false
## True until the first key is typed — a prefilled default gets replaced.
var _replace_pending := true


func _init() -> void:
	add_theme_constant_override("separation", 2)
	var grid := GridContainer.new()
	grid.columns = _ROWS[0].length()
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for row in _ROWS:
		for ch in row:
			var key := _make_key(ch, _type.bind(ch))
			key.custom_minimum_size = KEY_SIZE
			grid.add_child(key)
			if ch >= "A" and ch <= "Z":
				_letter_keys.append(key)
			if _first_key == null:
				_first_key = key

	var specials := HBoxContainer.new()
	specials.add_theme_constant_override("separation", 2)
	specials.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(specials)
	var shift_key := _make_key("Shift", _toggle_shift)
	var space_key := _make_key("Space", _type.bind(" "))
	space_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back_key := _make_key("Del", _backspace)
	var done_key := _make_key("Done", func() -> void: done.emit())
	for key in [shift_key, space_key, back_key, done_key]:
		key.custom_minimum_size = Vector2(0, KEY_SIZE.y)
		specials.add_child(key)
	_refresh_case()


func focus_first_key() -> void:
	if _first_key:
		_first_key.grab_focus()


func _make_key(label: String, on_press: Callable) -> Button:
	var key := Button.new()
	key.text = label
	key.focus_mode = Control.FOCUS_ALL
	key.add_theme_font_size_override("font_size", KEY_FONT_SIZE)
	key.pressed.connect(on_press)
	return key


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventJoypadButton) or not event.pressed:
		return
	match (event as InputEventJoypadButton).button_index:
		JOY_BUTTON_B:
			_backspace()
			get_viewport().set_input_as_handled()
		JOY_BUTTON_Y:
			_type(" ")
			get_viewport().set_input_as_handled()


func _type(ch: String) -> void:
	if target == null:
		return
	if _replace_pending:
		_replace_pending = false
		target.clear()
	if ch.length() == 1 and ch >= "A" and ch <= "Z" and not _upper_next():
		ch = ch.to_lower()
	target.insert_text_at_caret(ch)
	if _shift:
		_shift = false
	_refresh_case()


func _backspace() -> void:
	if target == null:
		return
	_replace_pending = false
	var caret := target.caret_column
	if caret > 0:
		target.delete_text(caret - 1, caret)
	_refresh_case()


func _toggle_shift() -> void:
	_shift = not _shift
	_refresh_case()


## Capital at the start of a word (or of a field about to be replaced),
## flipped by Shift.
func _upper_next() -> bool:
	var at_word_start := true
	if target and not _replace_pending:
		var before := target.text.left(target.caret_column)
		at_word_start = before.is_empty() or before.ends_with(" ")
	return at_word_start != _shift


## Letter keys show the case they'll type.
func _refresh_case() -> void:
	var upper := _upper_next()
	for key in _letter_keys:
		key.text = key.text.to_upper() if upper else key.text.to_lower()
