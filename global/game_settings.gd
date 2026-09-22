extends Node

## Global game settings that persist across scenes and sessions

const SETTINGS_PATH = "user://settings.json"

## Mouse mode: tapped to turn auto-fire on/off. Created at runtime (not in
## project.godot) because it only exists while mouse mode is on.
const TOGGLE_FIRE_ACTION := &"toggle_fire"

## Emitted when the player switches between gamepad and keyboard/mouse.
signal input_device_changed(using_gamepad: bool)

## Gamepad counts as "in use" once a stick is pushed at least this far —
## high enough that drift on a resting controller never trips it.
const _GAMEPAD_AXIS_THRESHOLD := 0.5
## Mouse counts as "in use" once it has travelled this far (window pixels)
## since the gamepad took over, so a bumped desk doesn't steal control back.
const _MOUSE_MOTION_THRESHOLD := 20.0

# Control settings
var thrust_inverted: bool = false
## Default layout for keyboard players: the mouse aims (always firing, Tab or
## middle click toggles) and LMB/RMB work the flippers, with the left-hand keys
## rearranged around WASD — see _apply_mouse_mode_bindings(). Off = the
## keyboard-only IJKL layout from project.godot. Mouse aim only actually runs
## while the keyboard/mouse is the active device — see mouse_aim_active().
var mouse_mode: bool = true

## True while the gamepad is the device the player last touched.
var using_gamepad: bool = false

var _mouse_travel: float = 0.0

## [action, event] pairs this script added to / removed from the InputMap for
## mouse mode, so turning it back off restores exactly what project.godot had.
var _added_events: Array = []
var _removed_events: Array = []


func _ready():
	# Device switches have to be seen while menus have the tree paused too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	using_gamepad = not Input.get_connected_joypads().is_empty()
	_load_settings()
	_apply_mouse_mode_bindings()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_using_gamepad(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= _GAMEPAD_AXIS_THRESHOLD:
		_set_using_gamepad(true)
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		_set_using_gamepad(false)
	elif event is InputEventMouseMotion and using_gamepad:
		_mouse_travel += event.relative.length()
		if _mouse_travel >= _MOUSE_MOTION_THRESHOLD:
			_set_using_gamepad(false)

func _set_using_gamepad(value: bool) -> void:
	_mouse_travel = 0.0
	if using_gamepad == value:
		return
	using_gamepad = value
	input_device_changed.emit(using_gamepad)

## Whether the cursor should be aiming (and auto-firing) right now.
func mouse_aim_active() -> bool:
	return mouse_mode and not using_gamepad

func _load_settings():
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Dictionary:
		thrust_inverted = result.get("thrust_inverted", false)
		mouse_mode = result.get("mouse_mode", true)

func _save_settings():
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"thrust_inverted": thrust_inverted,
			"mouse_mode": mouse_mode,
		}))
		file.close()

func set_thrust_inverted(inverted: bool):
	thrust_inverted = inverted
	_save_settings()
	get_tree().call_group("player", "_on_settings_changed")

func set_mouse_mode(enabled: bool):
	mouse_mode = enabled
	_save_settings()
	_apply_mouse_mode_bindings()
	get_tree().call_group("player", "_on_settings_changed")


# ── Keyboard labels for UI text (gamepad labels don't change) ────────────────

func tech_slot_key_label(slot_index: int) -> String:
	if mouse_mode:
		return "L Shift" if slot_index == 0 else "Space"
	return "Q" if slot_index == 0 else "E"

func drop_key_label() -> String:
	return "F" if mouse_mode else "Space"


# ── InputMap rewiring ────────────────────────────────────────────────────────

## Rewires the InputMap for the current mouse_mode. The right hand is on the
## mouse, so the flippers move to LMB/RMB, and the left hand's most-used,
## often-held actions (the tech slots) go on the keys reachable without lifting
## off WASD — Left Shift (pinky) and Space (thumb). Drop moves to F, and the
## auto-fire toggle goes on Tab / middle click; Q/E are unbound. Right Shift
## stays on the right flipper. Gamepad bindings are never touched.
func _apply_mouse_mode_bindings() -> void:
	# Always undo our previous changes first so this is safe to call repeatedly.
	for pair in _added_events:
		InputMap.action_erase_event(pair[0], pair[1])
	for pair in _removed_events:
		InputMap.action_add_event(pair[0], pair[1])
	_added_events.clear()
	_removed_events.clear()
	if InputMap.has_action(TOGGLE_FIRE_ACTION):
		InputMap.erase_action(TOGGLE_FIRE_ACTION)

	if not mouse_mode:
		return

	_remove_key(&"flipper_left", KEY_SHIFT, KEY_LOCATION_LEFT)
	_remove_key(&"drop_piece", KEY_SPACE)
	_remove_key(&"tech_slot_left", KEY_Q)
	_remove_key(&"tech_slot_right", KEY_E)

	_add_event(&"flipper_left", _mouse_button(MOUSE_BUTTON_LEFT))
	_add_event(&"flipper_right", _mouse_button(MOUSE_BUTTON_RIGHT))
	_add_event(&"tech_slot_left", _key(KEY_SHIFT, KEY_LOCATION_LEFT))
	_add_event(&"tech_slot_right", _key(KEY_SPACE))
	_add_event(&"drop_piece", _key(KEY_F))

	InputMap.add_action(TOGGLE_FIRE_ACTION)
	InputMap.action_add_event(TOGGLE_FIRE_ACTION, _key(KEY_TAB))
	InputMap.action_add_event(TOGGLE_FIRE_ACTION, _mouse_button(MOUSE_BUTTON_MIDDLE))

func _add_event(action: StringName, ev: InputEvent) -> void:
	InputMap.action_add_event(action, ev)
	_added_events.append([action, ev])

## Removes the action's key events for this physical key. With a location,
## only that side's key (and side-less events) go — Right Shift survives a
## Left Shift removal.
func _remove_key(action: StringName, keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey and ev.physical_keycode == keycode):
			continue
		if location != KEY_LOCATION_UNSPECIFIED and ev.location != location and ev.location != KEY_LOCATION_UNSPECIFIED:
			continue
		InputMap.action_erase_event(action, ev)
		_removed_events.append([action, ev])

func _key(keycode: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.location = location
	return ev

func _mouse_button(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev
