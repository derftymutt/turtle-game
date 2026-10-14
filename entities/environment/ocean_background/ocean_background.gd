@tool
extends Node2D

## Swaps OceanGradient between the tiled 64px strip and a single 640px-wide
## image. Both keep the same repeating 1920px region centred on x = 0, so the
## full-width image lines up exactly with the 640px viewport (tile seams land
## at ±320, just off-screen) and still tiles if the camera ever zooms out.

@export var strip_texture: Texture2D:
	set(value):
		strip_texture = value
		_apply()

@export var full_width_texture: Texture2D:
	set(value):
		full_width_texture = value
		_apply()

@export var use_full_width: bool = false:
	set(value):
		use_full_width = value
		_apply()


var _hd_wave: HdWaveArt


func _ready() -> void:
	_apply()
	var wave := get_node_or_null("WaveSurface") as CanvasItem
	if wave and not Engine.is_editor_hint():
		_hd_wave = HdWaveArt.new()
		wave.add_sibling(_hd_wave)
		_hd_wave.position = wave.position
		add_to_group(HdArt.GROUP_ENVIRONMENT)
		refresh_hd_art()


## HdArt: the environment category was toggled.
func refresh_hd_art() -> void:
	var hd: bool = HdArt.environment_on()
	_hd_wave.visible = hd
	_hd_wave.set_process(hd)
	$WaveSurface.visible = not hd


func _apply() -> void:
	var gradient := get_node_or_null("OceanGradient") as Sprite2D
	if gradient == null:
		return
	var tex := full_width_texture if use_full_width else strip_texture
	if tex != null:
		gradient.texture = tex
