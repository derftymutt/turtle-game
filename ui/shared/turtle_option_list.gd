extends Node
class_name TurtleOptionList

## Reusable "plain-text menu option marked by a turtle indicator + green
## text shine" component — the look introduced on the main menu
## (see ui/menus/main_menu.gd). Attach one instance per menu: call attach()
## once to create the turtle indicator, then either create_option() for a
## dynamically-built list or wire_option() for buttons already placed in a
## scene, and this handles the focus-triggered indicator slide and shine
## sweep for whichever option currently has focus.
##
## Menu-specific concerns — nav/select sound, what each option actually does,
## grabbing initial focus, entrance choreography — stay owned by the calling
## menu. This class only owns the shared visual mechanics.

const _TEXT_SHINE_SHADER = preload("res://ui/alien_tech/shaders/text_shine.gdshader")
const _TURTLE_IDLE_SPRITE = preload("res://entities/player/sprites/turtle_idle.png")
const _TURTLE_SHOOT_SPRITE = preload("res://entities/player/sprites/turtle_shoot.png")
const _TURTLE_REGION := Rect2(48.0, 0.0, 24.0, 24.0) # east-facing frame; same layout on both sheets

const _SHINE_GREEN := Color(0.4, 1.0, 0.45, 1.0)

const _INDICATOR_SIZE := Vector2(26.0, 26.0)
const _INDICATOR_GAP: float = 6.0
const _INDICATOR_MOVE_DURATION: float = 0.15

var _turtle_indicator: TextureRect
var _idle_texture: Texture2D
var _shoot_texture: Texture2D

var _shine_material: ShaderMaterial
var _shine_target: Button = null
var _shine_start_msec: int = 0

var _indicator_tween: Tween


func _process(_delta: float) -> void:
	if _shine_target and is_instance_valid(_shine_target):
		_update_option_shine(_shine_target)


## Creates the turtle indicator as a freely-positioned child of
## parent_control. parent_control must not itself be a layout Container
## (VBoxContainer, etc.) or its own layout pass will fight the indicator's
## position tween — add a plain Control for it to live in, same as
## main_menu.tscn's top-level "Control" node. Call once per menu, before
## create_option()/wire_option().
func attach(parent_control: Control) -> void:
	_idle_texture = AtlasTexture.new()
	_idle_texture.atlas = _TURTLE_IDLE_SPRITE
	_idle_texture.region = _TURTLE_REGION
	_shoot_texture = AtlasTexture.new()
	_shoot_texture.atlas = _TURTLE_SHOOT_SPRITE
	_shoot_texture.region = _TURTLE_REGION

	_turtle_indicator = TextureRect.new()
	_turtle_indicator.texture = _idle_texture
	_turtle_indicator.size = _INDICATOR_SIZE
	_turtle_indicator.expand_mode = 1 # EXPAND_IGNORE_SIZE
	_turtle_indicator.stretch_mode = 5 # STRETCH_KEEP_ASPECT_CENTERED
	_turtle_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent_control.add_child(_turtle_indicator)

	_shine_material = ShaderMaterial.new()
	_shine_material.shader = _TEXT_SHINE_SHADER
	_shine_material.set_shader_parameter("shine_color", Vector3(_SHINE_GREEN.r, _SHINE_GREEN.g, _SHINE_GREEN.b))


## For menus where a wired option isn't always the thing with focus (e.g.
## alien_tech_selection_screen.gd's Skip button, alongside its two
## separately-focus-managed tech slot panels) — hides the indicator when
## focus is on something outside this list entirely, instead of it sitting
## at its last position looking like a stray sprite.
func set_indicator_visible(v: bool) -> void:
	if _turtle_indicator:
		_turtle_indicator.visible = v


## Builds a new flat, borderless Button styled as a plain-text option and
## adds it to `container`. For menus that build their option list in script
## (see main_menu.gd's _add_selectable_option).
func create_option(container: Node, text: String, font_size: int, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, maxi(28, font_size + 14))
	btn.add_theme_font_size_override("font_size", font_size)
	container.add_child(btn)
	_style_option(btn)
	btn.pressed.connect(callback)
	return btn


## Strips a button already placed in a scene down to plain text and wires it
## into the shared indicator/shine system, without touching its existing
## `pressed` connection, size, or font size. For menus with hand-authored
## option buttons in their .tscn (see pause_menu.tscn).
func wire_option(btn: Button) -> void:
	_style_option(btn)


func _style_option(btn: Button) -> void:
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
	btn.focus_entered.connect(_on_option_focused.bind(btn))
	btn.focus_exited.connect(_on_option_unfocused.bind(btn))


func _on_option_focused(btn: Button) -> void:
	_shine_target = btn
	_shine_start_msec = Time.get_ticks_msec()
	btn.material = _shine_material
	_move_indicator_to(btn)


func _on_option_unfocused(btn: Button) -> void:
	btn.material = null
	if _shine_target == btn:
		_shine_target = null


func _indicator_target_pos(target: Control) -> Vector2:
	var rect := target.get_global_rect()
	return Vector2(
		rect.position.x - _INDICATOR_GAP - _turtle_indicator.size.x,
		rect.position.y + (rect.size.y - _turtle_indicator.size.y) * 0.5
	)


## Pokes the turtle's head out to the right (the shoot_e pose) for the
## duration of the slide, then relaxes back to idle once it settles.
func _move_indicator_to(target: Control) -> void:
	var target_pos := _indicator_target_pos(target)
	if _indicator_tween:
		_indicator_tween.kill()
	_indicator_tween = create_tween()
	_indicator_tween.tween_callback(func(): _turtle_indicator.texture = _shoot_texture)
	_indicator_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_indicator_tween.tween_property(_turtle_indicator, "position", target_pos, _INDICATOR_MOVE_DURATION)
	_indicator_tween.tween_callback(func(): _turtle_indicator.texture = _idle_texture)


## Feeds text_shine.gdshader the focused option's actual on-screen text
## bounds and its own reset-on-focus clock — see the shader's own comment
## for why a per-caller clock (rather than the builtin TIME) is needed so
## the sweep restarts at the left edge every time focus moves.
func _update_option_shine(btn: Button) -> void:
	var font := btn.get_theme_font("font")
	var font_size := btn.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var rect := btn.get_global_rect()
	var vp_width := _turtle_indicator.get_viewport().get_visible_rect().size.x
	_shine_material.set_shader_parameter("band_left_uv", rect.position.x / vp_width)
	_shine_material.set_shader_parameter("band_right_uv", (rect.position.x + text_width) / vp_width)
	_shine_material.set_shader_parameter("shine_time", (Time.get_ticks_msec() - _shine_start_msec) / 1000.0)
