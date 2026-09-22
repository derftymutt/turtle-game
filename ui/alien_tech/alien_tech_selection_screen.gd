extends CanvasLayer
class_name AlienTechSelectionScreen

## Shown when a new alien tech piece completes the collection threshold.
##
## The two equipped-tech display boxes (styled after the pause menu's
## tech-info panel) are themselves the "equip" controls: whichever one has
## focus previews the newly found tech — pulsing green border, full
## description — while the other keeps showing whatever is really equipped
## there. Move focus with left/right, confirm with ui_accept (Enter/A) or a
## click, or move focus to Skip to back out without equipping anything.

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")
const _TEXT_SHINE_SHADER = preload("res://ui/alien_tech/shaders/text_shine.gdshader")

# Left/right slots are always triggered by the same physical inputs
# regardless of which tech occupies them — lead with the gamepad button,
# then the keyboard key, matching the pause menu's "Left/Right Bumper or Q/E"
# phrasing.
# The keyboard half comes from GameSettings.tech_slot_key_label() (it depends
# on the keyboard-only setting).
const _SLOT_GAMEPAD_HINTS: Array[String] = ["LB", "RB"]
const _ALWAYS_ACTIVE_TEXT: String = "Always Active"

const _INPUT_HINT_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)
const _ALWAYS_ACTIVE_COLOR: Color = Color(0.55, 1.0, 0.6, 1.0)

const _ACTIVE_BLINK_PERIOD_MSEC: int = 300
const _ACTIVE_BLINK_LOW_ALPHA: float = 0.35

const _CANDIDATE_PULSE_PERIOD_SEC: float = 1.0
const _CANDIDATE_BORDER_ALPHA_RANGE := Vector2(0.5, 1.0)
const _CANDIDATE_BG_ALPHA_RANGE := Vector2(0.03, 0.12)

# "Alien tech" gets its own living, faintly otherworldly card instead of the
# other menus' static blue — the border hue slowly drifts through a
# violet-to-hot-pink range, and the background (a deeper purple, not pink —
# see _MENU_BG_BASE_COLOR) gently pulses in brightness on its own, mostly-dark
# range, out of phase with the border so the two never feel mechanically
# locked together.
const _MENU_BORDER_HUE_MIN: float = 0.80
const _MENU_BORDER_HUE_MAX: float = 0.93
const _MENU_BORDER_HUE_PERIOD_SEC: float = 3.5
const _MENU_BORDER_SATURATION: float = 0.7
const _MENU_BG_BASE_COLOR := Color(0.16, 0.04, 0.26, 0.75)
const _MENU_BG_BRIGHTNESS_RANGE := Vector2(0.85, 1.05)
const _MENU_BG_PULSE_PERIOD_SEC: float = 5.0

# The player is very often still holding a direction (swimming toward the
# piece, usually downward) the instant this screen steals focus — left
# unguarded, that stale held input reads as an immediate "navigate to Skip"
# to Godot's own held-direction menu repeat. So navigation/confirm input is
# ignored until every guarded action reads released (arms instantly for a
# player whose hands are already neutral), or after a timeout cap so a
# stuck input can't lock the menu out indefinitely.
# The flippers are guarded too: in mouse mode they're LMB/RMB, and a player
# mid-flip must not have that click land on whichever panel is under the cursor.
const _GUARDED_ACTIONS: Array[String] = ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept", "flipper_left", "flipper_right"]
const _INPUT_ARM_TIMEOUT_SEC: float = 1.5
# Even once armed, clicks are ignored this long after the screen appears — a
# player hammering the flipper buttons won't have noticed the screen yet.
const _CLICK_ARM_DELAY_MSEC: int = 500

@onready var outer_panel:     PanelContainer = $"Control/CenterContainer/PanelContainer"
@onready var title_label:     Label = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel"
@onready var tech_name_label: Label = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechNameLabel"
@onready var hook_label:      Label = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HookLabel"

@onready var skip_panel: PanelContainer = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonsRow/SkipPanel"
@onready var skip_label: Label = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ButtonsRow/SkipPanel/SkipRow/SkipLabel"

@onready var help_panel: PanelContainer = $"Control/CenterContainer/PanelContainer/HelpMargin/HelpPanel"

# Skip is styled as a third slot-like panel (same _style_unfocused/
# _style_candidate pulsing border as the two tech slots, see _ready() and
# _apply_candidate_style()) rather than a plain button, so this menu reads as
# one consistent set of three bordered options instead of two bordered boxes
# plus an unrelated-looking button.
var _skip_shine_material: ShaderMaterial
var _skip_shine_start_msec: int = 0

@onready var slot_l_panel: PanelContainer = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel"
@onready var slot_l_input:    Label       = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLInputRow/SlotLInput"
@onready var slot_l_replaces: Label       = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLInputRow/SlotLReplaces"
@onready var slot_l_name:  Label          = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLName"
@onready var slot_l_desc:  Label          = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLDesc"
@onready var slot_l_hot_row:   VBoxContainer = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLHotRow"
@onready var slot_l_hot_badge: Label         = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLHotRow/SlotLHotBadge"
@onready var slot_l_hot_desc:  Label         = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotLPanel/SlotLRow/SlotLTextContainer/SlotLHotRow/SlotLHotDesc"

@onready var slot_r_panel: PanelContainer = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel"
@onready var slot_r_input:    Label       = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRInputRow/SlotRInput"
@onready var slot_r_replaces: Label       = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRInputRow/SlotRReplaces"
@onready var slot_r_name:  Label          = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRName"
@onready var slot_r_desc:  Label          = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRDesc"
@onready var slot_r_hot_row:   VBoxContainer = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRHotRow"
@onready var slot_r_hot_badge: Label         = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRHotRow/SlotRHotBadge"
@onready var slot_r_hot_desc:  Label         = $"Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TechInfoMargin/TechInfoContainer/SlotRPanel/SlotRRow/SlotRTextContainer/SlotRHotRow/SlotRHotDesc"

var _sfx_nav: AudioStreamPlayer
var _sfx_select: AudioStreamPlayer

var _pending_tech_id: String = ""

# Which slot currently previews the found tech: 0 (left), 1 (right), -1 when
# Skip has focus, or _HELP_CANDIDATE when Help has focus — the last two both
# mean neither slot should preview it.
var _candidate_slot: int = 0

const _HELP_CANDIDATE: int = -2

# Whether each slot currently needs a blinking input hint (set on each
# display refresh, read every _process so the blink itself costs no lookups).
var _slot_blinking: Array[bool] = [false, false]

# Whether each slot's "Hot!" badge is currently shown and should blink.
var _slot_hot_blinking: Array[bool] = [false, false]

var _pulse_time: float = 0.0

var _style_unfocused: StyleBoxFlat
var _style_candidate: StyleBoxFlat

# Drives the outer card's living pink glow/breathing — see
# _update_menu_flair() and the _MENU_* constants above.
var _menu_style: StyleBoxFlat
var _menu_flair_time: float = 0.0

# Drives the flashlight-style shine sweep on tech_name_label — see
# text_shine.gdshader. band_left_x/band_right_x (the sweep's travel range)
# are recomputed every frame in _process() from the label's own font metrics
# rather than set once, so a layout pass landing a frame late never leaves
# them stale.
var _shine_material: ShaderMaterial

# See _GUARDED_ACTIONS above.
var _input_armed: bool = false
var _input_arm_elapsed: float = 0.0
var _shown_msec: int = 0


func _ready():
	add_to_group("alien_tech_selection")
	visible = false

	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	_sfx_nav.volume_db = -10.0
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = -10.0
	add_child(_sfx_select)

	_style_unfocused = StyleBoxFlat.new()
	_style_unfocused.bg_color = Color(1, 1, 1, 0.0)
	_style_unfocused.set_content_margin_all(6)
	_style_unfocused.set_border_width_all(1)
	_style_unfocused.border_color = Color(1, 1, 1, 0.12)
	_style_unfocused.set_corner_radius_all(3)

	_style_candidate = StyleBoxFlat.new()
	_style_candidate.set_content_margin_all(6)
	_style_candidate.set_border_width_all(2)
	_style_candidate.set_corner_radius_all(3)

	_menu_style = StyleBoxFlat.new()
	_menu_style.set_border_width_all(2)
	_menu_style.bg_color = _MENU_BG_BASE_COLOR
	_menu_style.border_color = Color.from_hsv(_MENU_BORDER_HUE_MIN, _MENU_BORDER_SATURATION, 1.0)
	outer_panel.add_theme_stylebox_override("panel", _menu_style)

	_shine_material = ShaderMaterial.new()
	_shine_material.shader = _TEXT_SHINE_SHADER
	tech_name_label.material = _shine_material

	for panel in [slot_l_panel, slot_r_panel]:
		panel.add_theme_stylebox_override("panel", _style_unfocused)
		panel.mouse_entered.connect(func(): panel.grab_focus())

	slot_l_panel.focus_entered.connect(_on_slot_focused.bind(0))
	slot_r_panel.focus_entered.connect(_on_slot_focused.bind(1))
	slot_l_panel.gui_input.connect(_on_slot_gui_input.bind(0))
	slot_r_panel.gui_input.connect(_on_slot_gui_input.bind(1))
	slot_l_panel.focus_neighbor_right = slot_l_panel.get_path_to(slot_r_panel)
	slot_r_panel.focus_neighbor_left = slot_r_panel.get_path_to(slot_l_panel)
	slot_r_panel.focus_neighbor_right = slot_r_panel.get_path_to(skip_panel)

	_skip_shine_material = ShaderMaterial.new()
	_skip_shine_material.shader = _TEXT_SHINE_SHADER
	_skip_shine_material.set_shader_parameter("shine_color", Vector3(0.4, 1.0, 0.45))

	skip_panel.add_theme_stylebox_override("panel", _style_unfocused)
	skip_panel.focus_neighbor_left = skip_panel.get_path_to(slot_r_panel)
	skip_panel.focus_entered.connect(_on_skip_focused)
	skip_panel.gui_input.connect(_on_skip_gui_input)
	skip_panel.mouse_entered.connect(func(): skip_panel.grab_focus())

	help_panel.add_theme_stylebox_override("panel", _style_unfocused)
	help_panel.focus_entered.connect(_on_help_focused)
	help_panel.gui_input.connect(_on_help_gui_input)
	help_panel.mouse_entered.connect(func(): help_panel.grab_focus())
	help_panel.focus_neighbor_bottom = help_panel.get_path_to(slot_l_panel)
	slot_l_panel.focus_neighbor_top = slot_l_panel.get_path_to(help_panel)
	slot_r_panel.focus_neighbor_top = slot_r_panel.get_path_to(help_panel)

	AlienTechManager.selection_ready.connect(_on_selection_ready)


func _process(delta: float) -> void:
	if not visible:
		return

	if not _input_armed:
		_input_arm_elapsed += delta
		var any_guarded_action_held := false
		for action in _GUARDED_ACTIONS:
			if Input.is_action_pressed(action):
				any_guarded_action_held = true
				break
		if not any_guarded_action_held or _input_arm_elapsed >= _INPUT_ARM_TIMEOUT_SEC:
			_input_armed = true

	_update_name_shine()
	_update_skip_shine()
	_update_menu_flair(delta)

	var active_blink_on := int(Time.get_ticks_msec() / _ACTIVE_BLINK_PERIOD_MSEC) % 2 == 0
	var input_alpha := 1.0 if active_blink_on else _ACTIVE_BLINK_LOW_ALPHA
	if _slot_blinking[0]:
		slot_l_input.modulate.a = input_alpha
	if _slot_blinking[1]:
		slot_r_input.modulate.a = input_alpha
	if _slot_hot_blinking[0]:
		slot_l_hot_badge.modulate.a = input_alpha
	if _slot_hot_blinking[1]:
		slot_r_hot_badge.modulate.a = input_alpha

	# Skip is now a third slot-like panel using this same _style_candidate
	# object when it's the focused one (_candidate_slot == -1), so the pulse
	# always has exactly one live user — no need to gate this on a specific
	# _candidate_slot value anymore.
	_pulse_time += delta
	var t := fmod(_pulse_time, _CANDIDATE_PULSE_PERIOD_SEC) / _CANDIDATE_PULSE_PERIOD_SEC
	var pulse := (sin(t * TAU) + 1.0) * 0.5
	_style_candidate.border_color = Color(0.4, 1.0, 0.4, lerpf(_CANDIDATE_BORDER_ALPHA_RANGE.x, _CANDIDATE_BORDER_ALPHA_RANGE.y, pulse))
	_style_candidate.bg_color = Color(0.4, 1.0, 0.4, lerpf(_CANDIDATE_BG_ALPHA_RANGE.x, _CANDIDATE_BG_ALPHA_RANGE.y, pulse))


func _on_selection_ready(choices: Array):
	if choices.is_empty():
		return
	_pending_tech_id = choices[0].get("id", "")
	_build_offer_display(choices[0])
	visible = true
	get_tree().paused = true
	_input_armed = false
	_input_arm_elapsed = 0.0
	_shown_msec = Time.get_ticks_msec()
	_menu_flair_time = 0.0
	if _candidate_slot == 1:
		slot_r_panel.grab_focus()
	else:
		slot_l_panel.grab_focus()


func _hide_screen():
	visible = false
	get_tree().paused = false


## Feeds text_shine.gdshader the actual on-screen bounds of the found tech's
## name (normalized 0..1 across the viewport, see the shader's own comment
## for why) so its highlight sweeps across just the letters — TechNameLabel
## is centered in a much wider, fixed-width panel, so its own get_global_rect()
## alone would have the band crossing mostly empty padding.
func _update_name_shine() -> void:
	if _shine_material == null or tech_name_label.text == "":
		return
	var font := tech_name_label.get_theme_font("font")
	var font_size := tech_name_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(tech_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_rect := tech_name_label.get_global_rect()
	var text_left := label_rect.position.x + (label_rect.size.x - text_width) * 0.5
	var vp_width := get_viewport().get_visible_rect().size.x
	_shine_material.set_shader_parameter("band_left_uv", text_left / vp_width)
	_shine_material.set_shader_parameter("band_right_uv", (text_left + text_width) / vp_width)
	_shine_material.set_shader_parameter("shine_time", Time.get_ticks_msec() / 1000.0)


## Same technique as _update_name_shine(), but only while Skip is actually
## the focused/candidate option (_candidate_slot == -1) — skip_label doesn't
## carry the shine material at all otherwise, see _on_skip_focused()/
## _on_slot_focused().
func _update_skip_shine() -> void:
	if _candidate_slot != -1 or skip_label.material == null:
		return
	var font := skip_label.get_theme_font("font")
	var font_size := skip_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(skip_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_rect := skip_label.get_global_rect()
	var vp_width := get_viewport().get_visible_rect().size.x
	_skip_shine_material.set_shader_parameter("band_left_uv", label_rect.position.x / vp_width)
	_skip_shine_material.set_shader_parameter("band_right_uv", (label_rect.position.x + text_width) / vp_width)
	_skip_shine_material.set_shader_parameter("shine_time", (Time.get_ticks_msec() - _skip_shine_start_msec) / 1000.0)


## Gives the outer card a slow, living shimmer instead of a static color —
## the border hue drifts through a violet-to-pink range, and the background
## pulses in brightness on its own out-of-phase cycle so nothing feels
## mechanically synced. Purely cosmetic, unrelated to the (separate) green
## candidate pulse on whichever slot/Skip currently has focus.
func _update_menu_flair(delta: float) -> void:
	_menu_flair_time += delta

	var hue_t := (sin(_menu_flair_time * TAU / _MENU_BORDER_HUE_PERIOD_SEC) + 1.0) * 0.5
	var hue := lerpf(_MENU_BORDER_HUE_MIN, _MENU_BORDER_HUE_MAX, hue_t)
	_menu_style.border_color = Color.from_hsv(hue, _MENU_BORDER_SATURATION, 1.0)

	# Phase-shifted from the border cycle above so the background never
	# breathes in lockstep with it.
	var bright_t := (sin(_menu_flair_time * TAU / _MENU_BG_PULSE_PERIOD_SEC + 2.0) + 1.0) * 0.5
	var brightness := lerpf(_MENU_BG_BRIGHTNESS_RANGE.x, _MENU_BG_BRIGHTNESS_RANGE.y, bright_t)
	_menu_style.bg_color = Color(
		_MENU_BG_BASE_COLOR.r * brightness,
		_MENU_BG_BASE_COLOR.g * brightness,
		_MENU_BG_BASE_COLOR.b * brightness,
		_MENU_BG_BASE_COLOR.a
	)


func _build_offer_display(tech: Dictionary):
	title_label.text = "Alien Tech Found!"

	var tech_color: Color = tech.get("color", Color.WHITE)
	tech_name_label.text = tech.get("name", "?")
	tech_name_label.modulate = tech_color

	hook_label.text = tech.get("hook", "")

	_candidate_slot = _default_candidate_slot()
	_pulse_time = 0.0
	_refresh_slots()
	_apply_candidate_style()


## Prefers whichever slot is currently empty, so a player with one tech
## equipped sees the new one drop straight into the open slot instead of
## overtaking the one they already picked. Ties (both empty, or both full)
## default to the left slot.
func _default_candidate_slot() -> int:
	var left_empty: bool = AlienTechManager.slots[0].is_empty()
	var right_empty: bool = AlienTechManager.slots[1].is_empty()
	if right_empty and not left_empty:
		return 1
	return 0


# ─── Slot display ─────────────────────────────────────────────────────────────

func _refresh_slots():
	var pending_tech: Dictionary = AlienTechRegistry.get_tech(_pending_tech_id)
	for i in AlienTechManager.MAX_SLOTS:
		if i == _candidate_slot:
			_render_slot(i, pending_tech, false)
		else:
			_render_slot(i, AlienTechManager.slots[i], true)


func _render_slot(slot_index: int, tech: Dictionary, is_really_equipped: bool):
	var input_lbl:    Label = slot_l_input    if slot_index == 0 else slot_r_input
	var replaces_lbl: Label = slot_l_replaces if slot_index == 0 else slot_r_replaces
	var name_lbl:  Label = slot_l_name  if slot_index == 0 else slot_r_name
	var desc_lbl:  Label = slot_l_desc  if slot_index == 0 else slot_r_desc
	var hot_row:   VBoxContainer = slot_l_hot_row  if slot_index == 0 else slot_r_hot_row
	var hot_desc:  Label         = slot_l_hot_desc if slot_index == 0 else slot_r_hot_desc

	if tech.is_empty():
		input_lbl.visible = false
		_slot_blinking[slot_index] = false
		input_lbl.modulate.a = 1.0
		replaces_lbl.visible = false
		name_lbl.text = "— empty —"
		name_lbl.modulate = Color(0.5, 0.5, 0.5, 1.0)
		desc_lbl.text = ""
		hot_row.visible = false
		_slot_hot_blinking[slot_index] = false
		return

	var tech_color: Color = tech.get("color", Color.WHITE)
	var needs_input: bool = tech.get("needs_input", false)

	name_lbl.modulate = tech_color
	name_lbl.text = tech.get("name", "")
	input_lbl.visible = true
	_slot_blinking[slot_index] = true
	if needs_input:
		input_lbl.text = "%s · %s" % [_SLOT_GAMEPAD_HINTS[slot_index], GameSettings.tech_slot_key_label(slot_index)]
		input_lbl.add_theme_color_override("font_color", _INPUT_HINT_COLOR)
	else:
		input_lbl.text = _ALWAYS_ACTIVE_TEXT
		input_lbl.add_theme_color_override("font_color", _ALWAYS_ACTIVE_COLOR)

	# This is the preview slot (showing the not-yet-equipped found tech, see
	# _refresh_slots()) and picking it would knock out a tech that's really
	# equipped there right now — call that out on the same line as the input
	# hint so a player with both slots full can see the trade-off up front.
	var old_tech: Dictionary = AlienTechManager.slots[slot_index]
	if not is_really_equipped and not old_tech.is_empty():
		replaces_lbl.text = "Replaces %s" % old_tech.get("name", "")
		replaces_lbl.visible = true
	else:
		replaces_lbl.visible = false

	desc_lbl.text = tech.get("description", "")
	desc_lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Hot-effect text only ever applies to a tech actually equipped and
	# played with — never spoil it on a not-yet-equipped preview.
	var hot_text: String = ""
	if is_really_equipped and AlienTechManager.is_slot_hot(slot_index):
		hot_text = tech.get("hot_description", "")
	if hot_text.is_empty():
		hot_row.visible = false
		_slot_hot_blinking[slot_index] = false
	else:
		hot_row.visible = true
		_slot_hot_blinking[slot_index] = true
		hot_desc.text = hot_text


func _apply_candidate_style():
	slot_l_panel.add_theme_stylebox_override("panel", _style_candidate if _candidate_slot == 0 else _style_unfocused)
	slot_r_panel.add_theme_stylebox_override("panel", _style_candidate if _candidate_slot == 1 else _style_unfocused)
	skip_panel.add_theme_stylebox_override("panel", _style_candidate if _candidate_slot == -1 else _style_unfocused)
	help_panel.add_theme_stylebox_override("panel", _style_candidate if _candidate_slot == _HELP_CANDIDATE else _style_unfocused)


func _on_slot_focused(slot_index: int):
	_sfx_nav.play()
	_candidate_slot = slot_index
	_pulse_time = 0.0
	_refresh_slots()
	_apply_candidate_style()
	skip_label.material = null


func _on_skip_focused():
	_sfx_nav.play()
	_candidate_slot = -1
	_pulse_time = 0.0
	_refresh_slots()
	_apply_candidate_style()
	_skip_shine_start_msec = Time.get_ticks_msec()
	skip_label.material = _skip_shine_material


func _on_help_focused():
	_sfx_nav.play()
	_candidate_slot = _HELP_CANDIDATE
	_pulse_time = 0.0
	_refresh_slots()
	_apply_candidate_style()
	skip_label.material = null


# ─── Equip / Skip ─────────────────────────────────────────────────────────────

func _on_slot_gui_input(event: InputEvent, slot_index: int):
	var is_click := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_click = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if is_click or event.is_action_pressed("ui_accept"):
		_equip_into(slot_index)


func _on_skip_gui_input(event: InputEvent) -> void:
	var is_click := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_click = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if is_click or event.is_action_pressed("ui_accept"):
		_on_skip_pressed()


func _on_help_gui_input(event: InputEvent) -> void:
	var is_click := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		is_click = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if is_click or event.is_action_pressed("ui_accept"):
		_show_help_dialog()


func _show_help_dialog():
	if _sfx_select:
		_sfx_select.play()
	var dialog := AlienTechHelpDialog.new()
	add_child(dialog)
	dialog.show_dialog()


func _equip_into(slot_index: int):
	if _sfx_select:
		_sfx_select.play()
	if _pending_tech_id.is_empty():
		_close_screen()
		return
	AlienTechManager.assign_tech(_pending_tech_id, slot_index)
	_close_screen()


func _on_skip_pressed():
	if _sfx_select:
		_sfx_select.play()
	_confirm_skip()


func _confirm_skip():
	if _pending_tech_id.is_empty():
		_close_screen()
		return
	var tech = AlienTechRegistry.get_tech(_pending_tech_id)
	var tech_name: String = tech.get("name", "this tech")
	var dialog := TurtleConfirmDialog.new()
	add_child(dialog)
	# A multi-line lambda nested inside an array/dict literal confuses
	# GDScript's indentation parser ("unindent doesn't match" at the dict's
	# closing brace) — define it as a plain local first instead.
	var do_skip := func():
		AlienTechManager.record_skipped_tech(_pending_tech_id)
		_close_screen()
	dialog.show_dialog(
		"Are you sure you don't wanna equip %s?" % tech_name,
		[
			{"text": "Skip It", "callback": do_skip},
			{"text": "Keep Looking", "is_cancel": true},
		]
	)


func _close_screen():
	_pending_tech_id = ""
	_hide_screen()


func _input(event: InputEvent):
	if not visible:
		return
	if event is InputEventMouseButton and (not _input_armed or Time.get_ticks_msec() - _shown_msec < _CLICK_ARM_DELAY_MSEC):
		get_viewport().set_input_as_handled()
		return
	if not _input_armed:
		for action in _GUARDED_ACTIONS:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		_confirm_skip()
