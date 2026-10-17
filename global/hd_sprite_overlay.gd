extends AnimatedSprite2D
class_name HdSpriteOverlay

## HD stand-in for a pixel AnimatedSprite2D whose scale/modulate other code
## animates (pulses, flashes, fades). It sits as a child of the pixel sprite,
## mirrors its animation frame, and inherits whatever is done to the parent; the
## parent's own drawing is hidden with self_modulate while HD is on. Frames must
## use the same animation names as the pixel SpriteFrames, drawn at HdArt.SCALE.

## Free rotation (HD only): instead of the parent's directional animation
## ("kick_ne"), show "<kind>_free" — art facing north — turned smoothly to
## target_angle (radians, 0 = north, clockwise). Purely visual.
var free_rotation: bool = false
var target_angle: float = 0.0
## How fast the art turns toward target_angle (higher = snappier).
var turn_speed: float = 18.0

var _parent_sprite: AnimatedSprite2D
var _angle: float = 0.0  ## shown angle, kept here since the body underneath spins freely

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
	if hd and free_rotation:
		_angle = target_angle  # appear already facing the right way
		global_rotation = _angle

func _process(delta: float) -> void:
	if not visible:
		return
	var p := _parent_sprite
	var anim: StringName = p.animation
	if free_rotation:
		anim = StringName(String(p.animation).get_slice("_", 0) + "_free")
		_angle = lerp_angle(_angle, target_angle, 1.0 - exp(-turn_speed * delta))
		global_rotation = _angle
	if sprite_frames.has_animation(anim) and animation != anim:
		animation = anim
	frame = mini(p.frame, sprite_frames.get_frame_count(animation) - 1)
	flip_h = p.flip_h
	flip_v = p.flip_v
	centered = p.centered
	offset = p.offset * HdArt.SCALE
