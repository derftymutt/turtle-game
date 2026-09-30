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


func _ready() -> void:
	_apply()


func _apply() -> void:
	var gradient := get_node_or_null("OceanGradient") as Sprite2D
	if gradient == null:
		return
	var tex := full_width_texture if use_full_width else strip_texture
	if tex != null:
		gradient.texture = tex
