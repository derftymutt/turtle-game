# main_menu.gd
extends CanvasLayer

## Main Menu — shows Continue (if save exists) and New Game.
## Level-select dev buttons are shown only when GameManager.DEV_MODE is true.

@onready var title_label = $Control/VBoxContainer/TitleMargin/TitleLabel
@onready var level_container = $Control/VBoxContainer/ButtonCenter/LevelContainer
@onready var button_center: CenterContainer = $Control/VBoxContainer/ButtonCenter
@onready var turtle_indicator: TextureRect = $Control/TurtleIndicator
@onready var water_ripple: WaterRippleOverlay = $WaterRippleOverlay

var guide_screen = null
var game_info_screen = null

const _NORMAL_GOLD := Color(1.0, 0.85, 0.0)
const _TITLE_GREEN := Color(0.6, 0.8980392, 0.3137255, 1.0)
const _SHINE_GREEN := Color(0.4, 1.0, 0.45, 1.0)

const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")
const _TEXT_SHINE_SHADER = preload("res://ui/alien_tech/shaders/text_shine.gdshader")

# Title drop-in: starts off-screen above, dropped in with an elastic curve so
# it overshoots past its resting spot (max depth) before slowly settling back
# up with a decaying wiggle — see _animate_title_intro().
const _TITLE_DROP_START_OFFSET: float = 220.0
const _TITLE_DROP_DURATION: float = 1.6
const _TITLE_WIGGLE_START_DEGREES: float = -5.0

# The elastic curve's visible settle reads as "done" well before the tween
# itself actually finishes — the tail end is a string of imperceptible
# sub-pixel oscillations. Reveal the options on their own shorter timer
# instead of waiting on the tween's real completion, so they don't lag
# behind what the eye already reads as settled. Tune independently of
# _TITLE_DROP_DURATION to taste.
const _OPTIONS_REVEAL_DELAY: float = 1.1

const _OPTIONS_FADE_DURATION: float = 0.5
const _INDICATOR_MOVE_DURATION: float = 0.15
const _INDICATOR_GAP: float = 6.0
const _OPTION_FONT_SIZE: int = 18

# First-reveal-only: the turtle indicator waits for the option text to be
# well into its own fade-in before it scoots into place — sliding it at the
# same time as the fade starts left it arriving while still mostly
# transparent, so the scoot itself was barely visible.
const _INDICATOR_REVEAL_DELAY: float = 0.3
const _INDICATOR_REVEAL_DURATION: float = 0.4
const _INDICATOR_REVEAL_OFFSET := Vector2(-18.0, -18.0)

const _CONTROLLER_LABEL_TOP_GAP: float = 14.0
const _RECORDS_TO_OPTIONS_GAP: float = 14.0

const _TURTLE_SHOOT_SPRITE = preload("res://entities/player/sprites/turtle_shoot.png")
const _TURTLE_SHOOT_REGION := Rect2(48.0, 0.0, 24.0, 24.0) # east-facing "shoot" pose, matches idle_e's frame layout

var _sfx_nav:         AudioStreamPlayer
var _sfx_select:      AudioStreamPlayer
var _nav_sound_ready: bool = false

@onready var _sfx_theme: AudioStreamPlayer = $SfxTheme

# Drives the flashlight-style shine sweep on whichever selectable option
# currently has focus — see text_shine.gdshader. One shared material is
# reused across all options (only one is ever focused at a time) and its
# band bounds are recomputed every frame from that option's own font metrics,
# same technique as the alien tech selection screen's found-tech name.
var _shine_material: ShaderMaterial
var _shine_target: Button = null
var _shine_start_msec: int = 0

var _indicator_tween: Tween
var _suppress_indicator_slide: bool = false
var _turtle_idle_texture: Texture2D
var _turtle_shoot_texture: Texture2D

# Holds only the selectable options (Continue/Start/Tutorial/Options/Quit),
# separate from level_container's other children (records label, dev grid,
# controller-recommended label). Kept in its own SIZE_SHRINK_CENTER column so
# it's centered against its own widest option text, not against those wider,
# unrelated labels — otherwise left-aligned option text ends up looking
# stuck to the left of screen center instead of centered as a group.
var _options_column: VBoxContainer


func _ready():
	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	_sfx_nav.volume_db = 0.0
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = 0.0
	add_child(_sfx_select)

	_sfx_theme.finished.connect(func(): _sfx_theme.play())

	_shine_material = ShaderMaterial.new()
	_shine_material.shader = _TEXT_SHINE_SHADER
	_shine_material.set_shader_parameter("shine_color", Vector3(_SHINE_GREEN.r, _SHINE_GREEN.g, _SHINE_GREEN.b))

	_turtle_idle_texture = turtle_indicator.texture
	_turtle_shoot_texture = AtlasTexture.new()
	_turtle_shoot_texture.atlas = _TURTLE_SHOOT_SPRITE
	_turtle_shoot_texture.region = _TURTLE_SHOOT_REGION

	guide_screen = get_tree().get_first_node_in_group("guide_screen")
	game_info_screen = get_tree().get_first_node_in_group("game_info_screen")
	_build_buttons(false)
	if title_label:
		title_label.add_theme_color_override("font_color", _TITLE_GREEN)
	# Enable nav sound next frame so the automatic grab_focus() in _reveal_options()
	# doesn't trigger it on load before the player has touched anything.
	call_deferred("_enable_nav_sound")
	_animate_title_intro()


func _process(_delta: float) -> void:
	if _shine_target and is_instance_valid(_shine_target):
		_update_option_shine(_shine_target)


func _format_ms(ms: int) -> String:
	var total_sec := ms / 1000
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	return "%d:%02d" % [minutes, seconds]


# ─── Title intro ──────────────────────────────────────────────────────────────

## Drops the title in from above the screen with a quick fall that overshoots
## past its resting position (max depth), then eases back up with a decaying
## wiggle as it settles — a single elastic-out tween naturally produces that
## fast-drop/overshoot/settle shape. Reveals the selectable options once it
## comes to rest.
func _animate_title_intro() -> void:
	if not title_label:
		_reveal_options()
		return

	await get_tree().process_frame

	title_label.pivot_offset = title_label.size * 0.5
	var rest_y: float = title_label.position.y
	title_label.position.y = rest_y - _TITLE_DROP_START_OFFSET
	title_label.rotation_degrees = _TITLE_WIGGLE_START_DEGREES

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(title_label, "position:y", rest_y, _TITLE_DROP_DURATION)
	tween.parallel().tween_property(title_label, "rotation_degrees", 0.0, _TITLE_DROP_DURATION)

	get_tree().create_timer(_OPTIONS_REVEAL_DELAY).timeout.connect(_reveal_options)


## Fades in the selectable options once the title has settled, then brings in
## the subtle water ripple overlay behind them.
func _reveal_options() -> void:
	button_center.visible = true
	turtle_indicator.visible = true

	# ButtonCenter was hidden (zero size / uncomputed layout) up to this
	# point, so its children's get_global_rect() is still stale the instant
	# it becomes visible — wait one frame for the container to actually lay
	# itself out before reading a rect to place the indicator against.
	await get_tree().process_frame

	var first_option: Button = null
	for child in _options_column.get_children():
		if child is Button:
			first_option = child
			break

	create_tween().tween_property(button_center, "modulate:a", 1.0, _OPTIONS_FADE_DURATION)

	if first_option:
		# Grab focus (arms nav/shine) without letting it trigger the normal
		# instant slide — _scoot_indicator_in drives the first-reveal motion
		# on its own timing instead, see its comment for why.
		_suppress_indicator_slide = true
		first_option.grab_focus()
		_suppress_indicator_slide = false
		_scoot_indicator_in(first_option)

	if water_ripple:
		water_ripple.enabled = true


# ─── Selectable options (turtle indicator + text shine, no button look) ───────

## Creates a plain-text selectable option: no button box/border/hover look —
## the currently focused one is instead marked by the turtle indicator
## sliding alongside it and its text rippling with the green shine shader
## (same technique as the Alien Tech Found name in alien_tech_selection_screen.gd).
func _add_selectable_option(text: String, font_size: int, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, max(28, font_size + 14))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	btn.add_theme_stylebox_override("disabled", empty_style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.pressed.connect(callback)
	btn.focus_entered.connect(_on_option_focused.bind(btn))
	btn.focus_exited.connect(_on_option_unfocused.bind(btn))
	_wire_button_sounds(btn)
	_options_column.add_child(btn)
	return btn


func _on_option_focused(btn: Button) -> void:
	_shine_target = btn
	_shine_start_msec = Time.get_ticks_msec()
	btn.material = _shine_material
	if not _suppress_indicator_slide:
		_move_indicator_to(btn)


func _on_option_unfocused(btn: Button) -> void:
	btn.material = null
	if _shine_target == btn:
		_shine_target = null


func _indicator_target_pos(target: Control) -> Vector2:
	var rect := target.get_global_rect()
	return Vector2(
		rect.position.x - _INDICATOR_GAP - turtle_indicator.size.x,
		rect.position.y + (rect.size.y - turtle_indicator.size.y) * 0.5
	)


## Pokes the turtle's head out to the right (the shoot_e pose) for the
## duration of the slide, then relaxes it back to idle once it settles —
## a little flourish for "the turtle reacting to a new selection."
func _move_indicator_to(target: Control) -> void:
	var target_pos := _indicator_target_pos(target)
	if _indicator_tween:
		_indicator_tween.kill()
	_indicator_tween = create_tween()
	_indicator_tween.tween_callback(func(): turtle_indicator.texture = _turtle_shoot_texture)
	_indicator_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_indicator_tween.tween_property(turtle_indicator, "position", target_pos, _INDICATOR_MOVE_DURATION)
	_indicator_tween.tween_callback(func(): turtle_indicator.texture = _turtle_idle_texture)


## First-reveal-only entrance: holds the indicator offset from its target and
## fully transparent until the option text has had a moment to fade in on
## its own, then scoots it into place — see _INDICATOR_REVEAL_DELAY's comment
## for why this can't just piggyback on the normal focus-triggered slide.
func _scoot_indicator_in(target: Control) -> void:
	var target_pos := _indicator_target_pos(target)
	turtle_indicator.position = target_pos + _INDICATOR_REVEAL_OFFSET
	turtle_indicator.modulate.a = 0.0

	if _indicator_tween:
		_indicator_tween.kill()
	_indicator_tween = create_tween()
	# tween_interval() only holds up the NEXT sequential step — set_parallel(true)
	# right after it would instead make that next step start alongside the
	# interval (i.e. also at t=0), silently skipping the delay entirely. Chain
	# .parallel() onto the second property tween instead, so only it rides
	# alongside the first (which itself still waits out the interval).
	_indicator_tween.tween_interval(_INDICATOR_REVEAL_DELAY)
	_indicator_tween.tween_property(turtle_indicator, "modulate:a", 1.0, _INDICATOR_REVEAL_DURATION)
	_indicator_tween.parallel().tween_property(turtle_indicator, "position", target_pos, _INDICATOR_REVEAL_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Feeds text_shine.gdshader the actual on-screen bounds of the focused
## option's text (normalized 0..1 across the viewport — see the shader's own
## comment for why), same technique as the found-tech name shine.
func _update_option_shine(btn: Button) -> void:
	var font := btn.get_theme_font("font")
	var font_size := btn.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var rect := btn.get_global_rect()
	var vp_width := get_viewport().get_visible_rect().size.x
	_shine_material.set_shader_parameter("band_left_uv", rect.position.x / vp_width)
	_shine_material.set_shader_parameter("band_right_uv", (rect.position.x + text_width) / vp_width)
	_shine_material.set_shader_parameter("shine_time", (Time.get_ticks_msec() - _shine_start_msec) / 1000.0)


func _build_buttons(grab_focus: bool = true):
	# === BEST VICTORY RECORDS ===
	var best_victory   := SaveManager.get_best_victory_score()
	var best_time_ms   := SaveManager.get_best_victory_time_ms()
	if best_victory > 0 or best_time_ms > 0:
		var records_label := Label.new()
		var records_text := ""
		if best_victory > 0:
			records_text += "Best Score: %s" % FormatUtil.comma_int(best_victory)
		if best_time_ms > 0:
			if records_text != "":
				records_text += "   "
			records_text += "Best Time: %s" % _format_ms(best_time_ms)
		records_label.text = records_text
		records_label.add_theme_font_size_override("font_size", 13)
		records_label.add_theme_color_override("font_color", _NORMAL_GOLD)
		records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_container.add_child(records_label)

		var records_spacer := Control.new()
		records_spacer.custom_minimum_size = Vector2(0, _RECORDS_TO_OPTIONS_GAP)
		level_container.add_child(records_spacer)

	_options_column = VBoxContainer.new()
	_options_column.add_theme_constant_override("separation", 3)
	_options_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	level_container.add_child(_options_column)

	# === CONTINUE (only when a save exists) ===
	if SaveManager.has_save():
		var level = SaveManager.get_save_level()
		_add_selectable_option("Continue  (Level %d)" % level, _OPTION_FONT_SIZE, _on_continue_pressed)

	# === NEW GAME ===
	_add_selectable_option("Start", _OPTION_FONT_SIZE, _on_new_game_pressed)

	# === TUTORIAL (optional, standalone — no scoring or progression) ===
	_add_selectable_option("Tutorial", _OPTION_FONT_SIZE, _on_tutorial_pressed)

	# === DEV LEVEL SELECT (hidden in release builds) ===
	if GameManager.DEV_MODE:
		var dev_row = HBoxContainer.new()
		dev_row.add_theme_constant_override("separation", 4)
		level_container.add_child(dev_row)

		for level_num in LevelManager.level_scenes.keys():
			var btn = Button.new()
			btn.text = str(level_num)
			btn.custom_minimum_size = Vector2(28, 28)
			btn.add_theme_font_size_override("font_size", 10)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.pressed.connect(func(): _on_dev_level_selected(level_num))
			_wire_button_sounds(btn)
			dev_row.add_child(btn)

	# === OPTIONS ===
	_add_selectable_option("Options", _OPTION_FONT_SIZE, _on_guide_pressed)

	# === QUIT ===
	_add_selectable_option("Quit", _OPTION_FONT_SIZE, _on_quit_pressed)

	# === CONTROLLER RECOMMENDATION ===
	var controller_spacer := Control.new()
	controller_spacer.custom_minimum_size = Vector2(0, _CONTROLLER_LABEL_TOP_GAP)
	level_container.add_child(controller_spacer)

	var controller_label = Label.new()
	controller_label.text = "Game controller recommended"
	controller_label.add_theme_font_size_override("font_size", 10)
	controller_label.add_theme_color_override("font_color", _NORMAL_GOLD)
	controller_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_container.add_child(controller_label)

	# Focus the first Button child (skip Labels)
	if grab_focus:
		for child in _options_column.get_children():
			if child is Button:
				child.grab_focus()
				break


func _on_continue_pressed():
	if _sfx_select:
		_sfx_select.play()
	SaveManager.apply_save()
	LevelManager.attempt_count = 1
	LevelManager.load_level(LevelManager.current_level_number)


func _on_new_game_pressed():
	if _sfx_select:
		_sfx_select.play()
	if SaveManager.has_save():
		_confirm_overwrite_save()
	else:
		_start_new_game()


func _confirm_overwrite_save():
	var level = SaveManager.get_save_level()
	var dialog := TurtleConfirmDialog.new()
	add_child(dialog)
	# A multi-line lambda nested inside an array/dict literal confuses
	# GDScript's indentation parser ("unindent doesn't match" at the dict's
	# closing brace) — define it as a plain local first instead.
	var do_new_game := func():
		SaveManager.delete_save()
		_start_new_game()
	dialog.show_dialog(
		"Your saved progress at Level %d will be lost." % level,
		[
			{"text": "New Game", "callback": do_new_game},
			{"text": "Cancel", "is_cancel": true},
		],
		"Start New Game?"
	)


func _start_new_game():
	GameManager.reset_game()
	if game_info_screen and game_info_screen.has_method("show_screen"):
		visible = false
		game_info_screen.show_screen()
	else:
		LevelManager.load_level(1)


func _on_tutorial_pressed():
	if _sfx_select:
		_sfx_select.play()
	GameManager.reset_game()
	LevelManager.load_tutorial()


func _on_dev_level_selected(level_num: int):
	GameManager.clear_carried_pieces()
	LevelManager.load_level(level_num)


func _on_guide_pressed():
	if _sfx_select:
		_sfx_select.play()
	if guide_screen and guide_screen.has_method("show_guide"):
		visible = false
		guide_screen.show_guide(func(): show_menu())
	else:
		push_warning("MainMenu: Guide screen not found!")


func _on_quit_pressed():
	if _sfx_select:
		_sfx_select.play()
	get_tree().quit()


func _enable_nav_sound() -> void:
	_nav_sound_ready = true


func _wire_button_sounds(btn: Button) -> void:
	btn.focus_entered.connect(func(): if _nav_sound_ready: _sfx_nav.play())


func show_menu():
	"""Called by guide screen when returning to menu"""
	visible = true
	_refresh_colors()
	for child in _options_column.get_children():
		if child is Button:
			child.grab_focus()
			break


func rebuild_buttons():
	for child in level_container.get_children():
		child.queue_free()
	_build_buttons(false)
	_refresh_colors()


func _refresh_colors():
	"""Re-applies menu text colors to all existing elements (no rebuild needed)"""
	if title_label:
		title_label.add_theme_color_override("font_color", _TITLE_GREEN)
	if not level_container:
		return
	for child in level_container.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", _NORMAL_GOLD)
	if _options_column:
		for child in _options_column.get_children():
			if child is Button:
				child.add_theme_color_override("font_color", Color.WHITE)
