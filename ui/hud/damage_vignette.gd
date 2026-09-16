extends RefCounted
class_name DamageVignette

## Full-screen radial vignette shown briefly when the player takes damage —
## corners darken then fade back out. Owns its ColorRect/shader/tween for its
## entire lifetime once built via build().

const DAMAGE_VIGNETTE_SHADER := preload("res://ui/hud/shaders/damage_vignette.gdshader")

var rect: ColorRect = null
var _material: ShaderMaterial = null
var _tween: Tween = null

## Builds the ColorRect and inserts it into `parent`'s children, just after
## `after` (typically DangerOverlay) so it sits below the HUD text/icons
## (drawn later in child order) but above the gameplay view underneath.
func build(parent: Node, after: Node = null) -> void:
	rect = ColorRect.new()
	rect.name = "DamageVignette"
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE  # unused — the shader fully overrides COLOR
	_material = ShaderMaterial.new()
	_material.shader = DAMAGE_VIGNETTE_SHADER
	rect.material = _material
	parent.add_child(rect)
	if after:
		parent.move_child(rect, after.get_index() + 1)

## Trigger the vignette: corners snap to `peak` darkness, then fade back to
## fully transparent over `fade_time` seconds. Re-triggering while a fade is
## in progress (rapid hits) restarts from the peak.
func flash(peak: float = 0.85, fade_time: float = 0.85) -> void:
	if not _material:
		return
	if _tween:
		_tween.kill()
	_material.set_shader_parameter("intensity", peak)
	_tween = rect.create_tween()
	_tween.tween_method(
		func(v): _material.set_shader_parameter("intensity", v),
		peak, 0.0, fade_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
