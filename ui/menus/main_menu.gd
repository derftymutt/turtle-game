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

# The turtle's bounce (see _BOUNCE_LEG_*_DURATION below) takes noticeably
# longer than the options' own fade-in, so kicking both off at the same
# moment leaves the turtle arriving well after the options have already
# settled. Starting the bounce this much earlier instead brings its landing
# in right after the options finish fading, so the whole entrance reads as
# one coordinated beat rather than two staggered ones.
const _BOUNCE_HEAD_START: float = 0.4

const _OPTIONS_FADE_DURATION: float = 0.5
const _INDICATOR_MOVE_DURATION: float = 0.15
const _INDICATOR_GAP: float = 6.0
const _OPTION_FONT_SIZE: int = 18

# First-reveal-only entrance: rather than the normal short focus-triggered
# slide (which starts right next to the option and is easy to miss), the
# turtle flies in from off the top-left corner and ricochets off the right
# wall and the bottom wall — like a pinball — before settling into place
# beside the first option. It travels far enough on its own to read clearly
# without needing to wait on the options' fade, so it starts immediately
# alongside it rather than delayed. See _bounce_indicator_in().
const _BOUNCE_LEG_1_DURATION: float = 0.34
const _BOUNCE_LEG_2_DURATION: float = 0.3
const _BOUNCE_LEG_3_DURATION: float = 0.38
const _BOUNCE_SQUASH_SCALE := Vector2(1.35, 0.65)

# Borrows the in-game super speed look (see TurtlePlayer._apply_super_speed_visuals
# / _spawn_motion_trail in entities/player/turtle_player.gd) for the bounce
# flight, so it reads as "the turtle going super speed" rather than a plain
# slide. _SUPER_SPEED_COLOR mirrors turtle_player.gd's super_speed_color
# export default — keep the two in sync if that's ever retuned.
#
# TurtlePlayer's trail spawns on a fixed *time* interval, which reads as
# continuous there because the player's speed per frame is small relative to
# its sprite. The bounce covers the whole screen in a fraction of a second,
# so a time interval leaves visible gaps — spawn on distance traveled
# instead (see _advance_bounce_trail()), which keeps spacing constant
# regardless of how fast a given leg is moving.
const _SUPER_SPEED_COLOR := Color(0.778, 1.504, 0.0)
const _BOUNCE_TRAIL_SPACING: float = 6.0
const _BOUNCE_TRAIL_FADE_DURATION: float = 0.25
const _BOUNCE_COLOR_FADE_DURATION: float = 0.25

# A trash bag drifts through the bottom third of the screen once the three
# intro beats (title, options, turtle bounce) have all landed, using the
# same drift speed and the same three-sine-wave "organic ocean current" path
# as TrashCluster's own ambient drift (see _physics_process() in
# entities/collectibles/trash_cluster/trash_cluster.gd) — just replayed on a
# plain TextureRect in _process() instead of a RigidBody2D, since the menu
# has no physics world of its own. Menu-only decoration: no hit detection,
# no breaking apart, it just floats across and frees itself off the far edge.
const _TRASHBAG_SPRITE = preload("res://entities/collectibles/trash_cluster/sprites/trash_cluster.png")
const _TRASHBAG_FRAME_SIZE := Vector2(24.0, 24.0)
const _TRASHBAG_FRAME_A_REGION := Rect2(0.0, 0.0, 24.0, 24.0)
const _TRASHBAG_FRAME_B_REGION := Rect2(24.0, 0.0, 24.0, 24.0)
const _TRASHBAG_FRAME_INTERVAL: float = 1.0 / 3.0  # matches trash_cluster.tscn's SpriteFrames (2 frames, speed 3.0)
const _TRASHBAG_DRIFT_SPEED: float = -38.0          # same value as TrashCluster.drift_speed's default
const _TRASHBAG_PAUSE_DELAY: float = 0.3            # beat of stillness once the intro lands, before it drifts through

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

# Drives the super-speed trail spawning during the entrance bounce — see
# _bounce_indicator_in() and _advance_bounce_trail().
var _bounce_active: bool = false
var _bounce_trail_last_pos: Vector2

# Drives the post-intro trash bag drift — see _spawn_trashbag() and
# _advance_trashbag().
var _trashbag: TextureRect = null
var _trashbag_age: float = 0.0
var _trashbag_wave_phase: float = 0.0
var _trashbag_base_y: float = 0.0
var _trashbag_flap_timer: float = 0.0
var _trashbag_flap_on_a: bool = true
var _trashbag_frame_a: Texture2D
var _trashbag_frame_b: Texture2D

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
	# Centers the squash/stretch pulse used on each wall bounce (see
	# _squash_indicator()) on the sprite instead of its top-left corner.
	turtle_indicator.pivot_offset = turtle_indicator.size * 0.5

	guide_screen = get_tree().get_first_node_in_group("guide_screen")
	game_info_screen = get_tree().get_first_node_in_group("game_info_screen")
	_build_buttons(false)
	if title_label:
		title_label.add_theme_color_override("font_color", _TITLE_GREEN)
	# Enable nav sound next frame so the automatic grab_focus() in _reveal_options()
	# doesn't trigger it on load before the player has touched anything.
	call_deferred("_enable_nav_sound")
	_animate_title_intro()


func _process(delta: float) -> void:
	if _shine_target and is_instance_valid(_shine_target):
		_update_option_shine(_shine_target)
	if _bounce_active:
		_advance_bounce_trail()
	if _trashbag and is_instance_valid(_trashbag):
		_advance_trashbag(delta)


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
		_start_indicator_bounce()
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

	get_tree().create_timer(_OPTIONS_REVEAL_DELAY - _BOUNCE_HEAD_START).timeout.connect(_start_indicator_bounce)
	get_tree().create_timer(_OPTIONS_REVEAL_DELAY).timeout.connect(_reveal_options)


## Gets the turtle moving toward its resting spot ahead of the options' own
## fade-in — see _BOUNCE_HEAD_START. Makes button_center visible early (still
## at modulate:a = 0, so nothing is shown yet) purely so its layout — and the
## first option's rect the bounce targets — is actually computed; the real
## reveal still happens on its own timing in _reveal_options().
func _start_indicator_bounce() -> void:
	button_center.visible = true
	turtle_indicator.visible = true

	# ButtonCenter was hidden (zero size / uncomputed layout) up to this
	# point, so its children's get_global_rect() is still stale the instant
	# it becomes visible — wait one frame for the container to actually lay
	# itself out before reading a rect to place the indicator against.
	await get_tree().process_frame

	var first_option := _first_option()
	if first_option:
		# Grab focus (arms nav/shine) without letting it trigger the normal
		# instant slide — _bounce_indicator_in drives the first-reveal motion
		# on its own timing instead, see its comment for why.
		_suppress_indicator_slide = true
		first_option.grab_focus()
		_suppress_indicator_slide = false
		_bounce_indicator_in(first_option)


func _first_option() -> Button:
	for child in _options_column.get_children():
		if child is Button:
			return child
	return null


## Fades in the selectable options once the title has settled, then brings in
## the subtle water ripple overlay behind them.
func _reveal_options() -> void:
	create_tween().tween_property(button_center, "modulate:a", 1.0, _OPTIONS_FADE_DURATION)

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


## First-reveal-only entrance: sends the turtle in from off the top-left
## corner of the screen and lets it ricochet off the right wall and then the
## bottom wall — like a pinball — before rising into its resting spot beside
## `target`. Fully opaque and visible for the whole flight (unlike the old
## fade-in-place scoot) since it now travels far enough to read on its own.
func _bounce_indicator_in(target: Control) -> void:
	var target_pos := _indicator_target_pos(target)
	var vp_size := get_viewport().get_visible_rect().size
	var right_wall_x: float = vp_size.x - turtle_indicator.size.x
	var bottom_wall_y: float = vp_size.y - turtle_indicator.size.y

	var start_pos := Vector2(-turtle_indicator.size.x, -turtle_indicator.size.y)
	var bounce_1 := Vector2(right_wall_x, vp_size.y * 0.12)   # off the right wall, high up
	var bounce_2 := Vector2(vp_size.x * 0.25, bottom_wall_y)  # off the bottom wall, back toward center

	turtle_indicator.position = start_pos
	turtle_indicator.rotation = 0.0
	turtle_indicator.scale = Vector2.ONE
	turtle_indicator.modulate = _SUPER_SPEED_COLOR
	turtle_indicator.texture = _turtle_shoot_texture

	_bounce_active = true
	_bounce_trail_last_pos = start_pos

	if _indicator_tween:
		_indicator_tween.kill()
	_indicator_tween = create_tween()
	_indicator_tween.tween_property(turtle_indicator, "position", bounce_1, _BOUNCE_LEG_1_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_indicator_tween.tween_callback(_squash_indicator)
	_indicator_tween.tween_property(turtle_indicator, "position", bounce_2, _BOUNCE_LEG_2_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_indicator_tween.tween_callback(_squash_indicator)
	_indicator_tween.tween_property(turtle_indicator, "position", target_pos, _BOUNCE_LEG_3_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_indicator_tween.tween_callback(func():
		turtle_indicator.texture = _turtle_idle_texture
		_bounce_active = false)
	_indicator_tween.tween_property(turtle_indicator, "modulate", Color.WHITE, _BOUNCE_COLOR_FADE_DURATION)
	_indicator_tween.tween_callback(_schedule_trashbag_drift)


## Quick squash-and-stretch pulse played at each wall bounce for a bit of
## pinball impact "juice." Runs on its own tween in parallel with
## _bounce_indicator_in's position sequence rather than inside it, since it
## shouldn't hold up the next leg starting.
func _squash_indicator() -> void:
	var squash := create_tween()
	squash.tween_property(turtle_indicator, "scale", _BOUNCE_SQUASH_SCALE, 0.06)
	squash.tween_property(turtle_indicator, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Leaves a fading afterimage behind the indicator each trail tick during the
## entrance bounce — the same "motion trail" technique TurtlePlayer uses for
## its super speed dash (see _spawn_motion_trail() in turtle_player.gd),
## adapted to a UI TextureRect. z_index keeps trails behind the live sprite
## without needing to fuss with sibling order.
## Fills in the gap between last frame's indicator position and this frame's
## with evenly-spaced afterimages (_BOUNCE_TRAIL_SPACING apart) instead of
## spawning one per frame — see the constant's comment for why a fixed time
## interval leaves gaps at this speed.
func _advance_bounce_trail() -> void:
	var current_pos := turtle_indicator.position
	var dist := current_pos.distance_to(_bounce_trail_last_pos)
	if dist > 0.0:
		var steps := maxi(1, int(ceil(dist / _BOUNCE_TRAIL_SPACING)))
		for i in range(1, steps + 1):
			_spawn_indicator_trail(_bounce_trail_last_pos.lerp(current_pos, float(i) / steps))
	_bounce_trail_last_pos = current_pos


func _spawn_indicator_trail(pos: Vector2) -> void:
	var trail := TextureRect.new()
	trail.texture = turtle_indicator.texture
	trail.size = turtle_indicator.size
	trail.pivot_offset = turtle_indicator.pivot_offset
	trail.expand_mode = turtle_indicator.expand_mode
	trail.stretch_mode = turtle_indicator.stretch_mode
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.position = pos
	trail.scale = turtle_indicator.scale
	trail.rotation = turtle_indicator.rotation
	var trail_color := _SUPER_SPEED_COLOR
	trail_color.a = 0.8
	trail.modulate = trail_color

	# A negative z_index would tuck it behind the ColorRect background too
	# (z_index compares across the whole CanvasLayer, not just siblings) —
	# insert it as Control's child right below TurtleIndicator instead, so it
	# stays behind the live sprite while still painting above the background.
	var parent := turtle_indicator.get_parent()
	parent.add_child(trail)
	parent.move_child(trail, turtle_indicator.get_index())

	var tween := create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, _BOUNCE_TRAIL_FADE_DURATION)
	tween.tween_callback(trail.queue_free)


# ─── Post-intro trash bag drift ────────────────────────────────────────────────

## Called once the turtle bounce (and its color fade) has fully landed —
## waits one more beat of stillness before the trash bag drifts through, so
## the three intro beats and this fourth one read as separate moments rather
## than piling on top of each other.
func _schedule_trashbag_drift() -> void:
	get_tree().create_timer(_TRASHBAG_PAUSE_DELAY).timeout.connect(_spawn_trashbag)


## Sends a trash bag drifting through the bottom third of the screen, using
## the same drift speed and per-frame "organic ocean current" wave math as
## TrashCluster's own ambient drift (see _physics_process() in
## entities/collectibles/trash_cluster/trash_cluster.gd) — just applied to a
## plain TextureRect's position each frame (via _advance_trashbag()) instead
## of a RigidBody2D's linear_velocity, since the menu has no physics world.
func _spawn_trashbag() -> void:
	_trashbag_frame_a = AtlasTexture.new()
	_trashbag_frame_a.atlas = _TRASHBAG_SPRITE
	_trashbag_frame_a.region = _TRASHBAG_FRAME_A_REGION
	_trashbag_frame_b = AtlasTexture.new()
	_trashbag_frame_b.atlas = _TRASHBAG_SPRITE
	_trashbag_frame_b.region = _TRASHBAG_FRAME_B_REGION

	var bag := TextureRect.new()
	bag.texture = _trashbag_frame_a
	bag.size = _TRASHBAG_FRAME_SIZE
	bag.expand_mode = 1     # EXPAND_IGNORE_SIZE
	bag.stretch_mode = 5    # STRETCH_KEEP_ASPECT_CENTERED
	bag.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp_size := get_viewport().get_visible_rect().size
	# Drift speed is negative (see TrashCluster.drift_speed) so it enters
	# from the right and travels left; the wave adds at most ~±31px of its
	# own on top of this baseline.
	_trashbag_base_y = vp_size.y - 120.0
	_trashbag_age = 0.0
	_trashbag_wave_phase = randf() * TAU
	_trashbag_flap_timer = 0.0
	_trashbag_flap_on_a = true
	bag.position = Vector2(vp_size.x + _TRASHBAG_FRAME_SIZE.x, _trashbag_base_y)

	# The bottom third overlaps the lower menu text (Quit, the controller
	# hint) — insert as Control's very first child so it drifts behind the
	# title/options/turtle instead of drawing over them.
	var parent := turtle_indicator.get_parent()
	parent.add_child(bag)
	parent.move_child(bag, 0)
	_trashbag = bag


## Advances the trash bag's drift by one frame — see _spawn_trashbag() for
## why this mirrors TrashCluster._physics_process()'s wave math exactly.
func _advance_trashbag(delta: float) -> void:
	_trashbag_age += delta
	var t := _trashbag_age + _trashbag_wave_phase

	var wave_y := sin(t * 0.35) * 18.0 + sin(t * 1.05) * 9.0 + sin(t * 2.6) * 4.0
	var wave_x := sin(t * 0.55 + 1.2) * 4.0 + sin(t * 1.7) * 2.0

	_trashbag.position.x += (_TRASHBAG_DRIFT_SPEED + wave_x) * delta
	_trashbag.position.y = _trashbag_base_y + wave_y

	_trashbag_flap_timer += delta
	if _trashbag_flap_timer >= _TRASHBAG_FRAME_INTERVAL:
		_trashbag_flap_timer = 0.0
		_trashbag_flap_on_a = not _trashbag_flap_on_a
		_trashbag.texture = _trashbag_frame_a if _trashbag_flap_on_a else _trashbag_frame_b

	if _trashbag.position.x < -_TRASHBAG_FRAME_SIZE.x:
		_trashbag.queue_free()
		_trashbag = null


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
	controller_label.add_theme_font_size_override("font_size", 12)
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
