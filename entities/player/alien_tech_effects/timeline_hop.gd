extends RefCounted
class_name TimelineHop

## The Timeline Alternator's "hop" look, shared by everything the tech moves
## (UFO Workshop, sea urchins): a lateral shake that settles out while the node
## fades out of this timeline, or back into the new one.

const FADE_TIME: float = 0.3
const SHAKE_AMPLITUDE: float = 4.0
const SHAKE_CYCLES: float = 5.0

## Appends one shake + fade of `target` to `tween`. The fade is a normal
## tweener (a new step in a sequential tween, or joining the current step in a
## parallel one); the shake always runs alongside it. Only `sprite`'s x is
## shaken, so a bob on y (sea urchin) keeps working underneath it.
static func shake_fade(tween: Tween, target: CanvasItem, sprite: Node2D, fade_in: bool) -> void:
	var from_alpha: float = 0.0 if fade_in else target.modulate.a
	tween.tween_property(target, "modulate:a", 1.0 if fade_in else 0.0, FADE_TIME).from(from_alpha)
	if sprite:
		tween.parallel().tween_method(func(strength: float) -> void: _shake(sprite, strength),
				1.0, 0.0, FADE_TIME)

## `strength` runs 1 → 0 over the fade, so the shake ends exactly at x = 0.
static func _shake(sprite: Node2D, strength: float) -> void:
	if not is_instance_valid(sprite):
		return
	var t := 1.0 - strength
	sprite.position.x = sin(t * TAU * SHAKE_CYCLES) * SHAKE_AMPLITUDE * strength
