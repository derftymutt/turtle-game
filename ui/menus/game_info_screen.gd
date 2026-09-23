extends CanvasLayer
class_name GameInfoScreen

const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")
var _sfx_select: AudioStreamPlayer

@onready var content_container: VBoxContainer = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ContentContainer
@onready var start_button: Button = $Control/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/OptionsColumn/StartButton
@onready var _control: Control = $Control

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

# Any click anywhere (or Space / Enter / A) starts the game — the Plunge button
# alone wasn't obvious enough, and nothing on this screen needs a choice.
# Input is ignored briefly after showing so the press that opened the screen
# can't skip straight past it.
const _INPUT_ARM_DELAY_MSEC: int = 300
var _shown_msec: int = 0
var _started: bool = false

func _ready():
	visible = false
	add_to_group("game_info_screen")

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = -10.0
	add_child(_sfx_select)

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
		_option_list.wire_option(start_button)
		# wire_option() defaults every option to white — override back to
		# yellow after it, so the green shine still ripples on top via the
		# shader's own color mix, just over a yellow base instead of white.
		var yellow := Color(1.0, 0.85, 0.0)
		start_button.add_theme_color_override("font_color", yellow)
		start_button.add_theme_color_override("font_focus_color", yellow)
		start_button.add_theme_color_override("font_hover_color", yellow)
		start_button.add_theme_color_override("font_pressed_color", yellow)
	_build_content()

func show_screen():
	visible = true
	_started = false
	_shown_msec = Time.get_ticks_msec()
	# This CanvasLayer's Control subtree doesn't get a real layout pass while
	# hidden, so the button's get_global_rect() is still stale for a frame or
	# two after it's shown — wait for layout to actually settle before
	# positioning the turtle indicator against it (same fix as
	# pause_menu.gd's _open()).
	await get_tree().process_frame
	await get_tree().process_frame
	if start_button:
		start_button.grab_focus()

func hide_screen():
	visible = false

func _build_content():
	if not content_container:
		return

	var ufo_tex     = load("res://entities/collectibles/ufo_piece/sprites/ufo_piece_grey.png")
	var workshop_tex = load("res://entities/environment/ufo_workshop/sprites/ufo_workshop2.png")
	var trash_tex   = load("res://systems/trash_cleanup/sprites/trash.png")
	var powerup_tex = load("res://entities/collectibles/powerup/sprites/powerup.png")
	var cluster_tex = load("res://entities/collectibles/trash_cluster/sprites/trash_cluster.png")
	var alien_tex   = load("res://entities/collectibles/alien_tech_piece/sprites/alien_tech_piece.png")
	var air_tex     = load("res://ui/hud/sprites/air_meter_icon.png")
	var energy_tex  = load("res://ui/hud/sprites/energy_meter_icon.png")

	# "You are Flip..."
	content_container.add_child(_label("You are Flip, UFO repair turtle and pinball aficionado."))
	_spacer(8)

	# UFO parts + workshop
	var row_ufo := _row()
	row_ufo.add_child(_label_inline("Pick up UFO parts "))
	row_ufo.add_child(_anim_sprite(ufo_tex, Vector2(12, 12), [
		Rect2(0, 0, 12, 12), Rect2(12, 0, 12, 12), Rect2(24, 0, 12, 12),
		Rect2(36, 0, 12, 12), Rect2(48, 0, 12, 12), Rect2(60, 0, 12, 12)
	], Vector2(30, 30), 4.0))
	row_ufo.add_child(_label_inline(" and deliver them to your workshop "))
	# ufo_workshop2.png: 120x24, 5 frames of 24x24 — show first frame
	row_ufo.add_child(_static(workshop_tex, Rect2(0, 0, 24, 24), Vector2(30, 30)))
	content_container.add_child(row_ufo)
	content_container.add_child(_label("Deliver enough to assemble the UFO for a test flight!"))
	_spacer(8)

	# Trash + powerup
	var row_trash := _row()
	row_trash.add_child(_label_inline("Clean up trash "))
	# trash.png: 32x8, 4 frames of 8x8
	row_trash.add_child(_anim_sprite(trash_tex, Vector2(8, 8), [
		Rect2(0, 0, 8, 8), Rect2(8, 0, 8, 8), Rect2(16, 0, 8, 8), Rect2(24, 0, 8, 8)
	], Vector2(24, 24), 3.0))
	row_trash.add_child(_label_inline(" for powerups "))
	# powerup.png "random" animation: frames at x=128 and x=144
	row_trash.add_child(_anim_sprite(powerup_tex, Vector2(16, 16), [
		Rect2(128, 0, 16, 16), Rect2(144, 0, 16, 16)
	], Vector2(26, 26), 5.0))
	row_trash.add_child(_label_inline(" and points"))
	content_container.add_child(row_trash)

	# Trash cluster + alien tech
	var row_cluster := _row()
	row_cluster.add_child(_label_inline("Trash bags "))
	# trash_cluster.png: 48x24, 2 frames of 24x24
	row_cluster.add_child(_anim_sprite(cluster_tex, Vector2(24, 24), [
		Rect2(0, 0, 24, 24), Rect2(24, 0, 24, 24)
	], Vector2(26, 26), 3.0))
	row_cluster.add_child(_label_inline(" hide alien technologies "))
	# alien_tech_piece.png: 24x12, 2 frames of 12x12
	row_cluster.add_child(_anim_sprite(alien_tex, Vector2(12, 12), [
		Rect2(0, 0, 12, 12), Rect2(12, 0, 12, 12)
	], Vector2(26, 26), 5.0))
	content_container.add_child(row_cluster)
	_spacer(8)

	# Air + energy
	var row_meters := _row()
	row_meters.add_child(_label_inline("Keep an eye on your air "))
	row_meters.add_child(_static(air_tex, Rect2(0, 0, 16, 16), Vector2(20, 20)))
	row_meters.add_child(_label_inline(" and energy "))
	row_meters.add_child(_static(energy_tex, Rect2(0, 0, 15, 14), Vector2(20, 18)))
	content_container.add_child(row_meters)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var is_click: bool = event is InputEventMouseButton and event.pressed
	var is_accept: bool = event.is_action_pressed("ui_accept") and not event.is_echo()
	if not (is_click or is_accept):
		return
	# Handled either way, so the focused Plunge button can't fire a second time.
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() - _shown_msec >= _INPUT_ARM_DELAY_MSEC:
		_on_start_pressed()


func _on_start_pressed():
	if _started:
		return
	_started = true
	if _sfx_select:
		_sfx_select.play()
	LevelManager.load_level(1)


# ── layout helpers ──────────────────────────────────────────────────────────

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _label_inline(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 2)
	return r


func _spacer(height: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	content_container.add_child(s)


func _static(tex: Texture2D, region: Rect2, display_size: Vector2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	var rect := TextureRect.new()
	rect.texture = atlas
	rect.custom_minimum_size = display_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


func _anim_sprite(tex: Texture2D, frame_size: Vector2, rects: Array, display_size: Vector2, speed: float) -> Control:
	var sf := SpriteFrames.new()
	sf.clear("default")
	sf.set_animation_speed("default", speed)
	sf.set_animation_loop("default", true)
	for rect: Rect2 in rects:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = rect
		sf.add_frame("default", atlas)

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = sf
	sprite.centered = true
	sprite.position = display_size / 2.0
	sprite.scale = display_size / frame_size

	var container := Control.new()
	container.custom_minimum_size = display_size
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	container.add_child(sprite)
	sprite.play("default")
	return container
