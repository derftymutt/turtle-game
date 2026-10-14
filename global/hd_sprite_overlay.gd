extends AnimatedSprite2D
class_name HdSpriteOverlay

## HD stand-in for a pixel AnimatedSprite2D whose scale/modulate other code
## animates (pulses, flashes, fades). It sits as a child of the pixel sprite,
## mirrors its animation frame, and inherits whatever is done to the parent; the
## parent's own drawing is hidden with self_modulate while HD is on. Frames must
## use the same animation names as the pixel SpriteFrames, drawn at HdArt.SCALE.

var _parent_sprite: AnimatedSprite2D

static func attach(pixel_sprite: AnimatedSprite2D, frames: SpriteFrames) -> HdSpriteOverlay:
	var overlay := HdSpriteOverlay.new()
	overlay._parent_sprite = pixel_sprite
	overlay.sprite_frames = frames
	overlay.scale = Vector2.ONE / HdArt.SCALE
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pixel_sprite.add_child(overlay)
	return overlay

## Shows the overlay (hiding the pixel drawing) or the pixel art.
func set_hd(hd: bool) -> void:
	visible = hd
	_parent_sprite.self_modulate.a = 0.0 if hd else 1.0

func _process(_delta: float) -> void:
	if not visible:
		return
	var p := _parent_sprite
	if sprite_frames.has_animation(p.animation) and animation != p.animation:
		animation = p.animation
	frame = mini(p.frame, sprite_frames.get_frame_count(animation) - 1)
	flip_h = p.flip_h
	flip_v = p.flip_v
	centered = p.centered
	offset = p.offset * HdArt.SCALE
