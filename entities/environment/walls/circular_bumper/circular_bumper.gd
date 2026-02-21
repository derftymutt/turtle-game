@tool
extends StaticBody2D
class_name CircularBumper

## CIRCULAR BUMPER — Classic pinball-style bumper that reflects the turtle with added force.
##
## PIXEL-PERFECT RULE:
##   StaticBody2D never rotates. All sizing is driven by the radius on the CircleShape2D.
##   AnimatedSprite2D handles visuals. Polygon2D is a hidden fallback when no sprite is loaded.
##
## SPRITE NAMING CONVENTION:
##   Animation names in the SpriteFrames resource must follow this pattern:
##     <size>_<variant>_idle    e.g.  small_1_idle, medium_2_idle
##     <size>_<variant>_hit     e.g.  small_1_hit,  large_1_hit
##   Where <size> matches SIZE_NAMES values and <variant> matches your @export_enum string.
##
## SCENE SETUP REQUIRED:
##   Add these child nodes to the scene (Inspector, not code):
##     - CollisionShape2D     (CircleShape2D, layers/masks set in Inspector)
##     - Polygon2D            (fallback visual, shown when no sprite is found)
##     - AnimatedSprite2D     (main visual, must have SpriteFrames assigned)
##     - HitArea (Area2D)     (layers/masks set in Inspector — detects player contact)
##       └─ CollisionShape2D  (CircleShape2D, sized to match bumper radius)
##   Physics material: set bounce/friction in Inspector on the StaticBody2D.
##   Collision layers and masks: NEVER set in code — always in the Inspector.

## --- Constants ---

## Maps SizePreset to a suggested radius in pixels (1 pixel = 1 unit in Godot 2D).
## These are suggestions — the designer can override radius freely.
const SIZE_RADII: Dictionary = {
	0: 12.0,   ## Small  → 24px diameter
	1: 16.0,   ## Medium → 36px diameter
	2: 28.0,   ## Large  → 56px diameter
}

## Maps SizePreset index to the size name string used in animation names.
const SIZE_NAMES: Dictionary = {
	0: "small",
	1: "medium",
	2: "large",
}

## --- Enums ---

enum SizePreset {
	SMALL  = 0,
	MEDIUM = 1,
	LARGE  = 2,
}

## --- Exports ---

@export_group("Shape")

@export var size_preset: SizePreset = SizePreset.SMALL:
	set(value):
		size_preset = value
		## Suggest a radius when the preset changes, but don't lock it.
		radius = SIZE_RADII.get(int(value), 12.0)
		## radius setter calls _update_bumper(), so no extra call needed here.

## Radius in pixels. Freely overridable after choosing a preset.
@export var radius: float = 12.0:
	set(value):
		radius = value
		_update_bumper()

@export_group("Sprite")

## Selects which sprite variant to use for this bumper instance.
## Must match the variant portion of your animation names (e.g. "1", "2", "3").
## Add new options here as a comma-separated string to expose them in the Inspector.
@export_enum("1", "2", "3") var variant: String = "1":
	set(value):
		variant = value
		_update_bumper()

@export_group("Bumper Physics")
@export var bounce_multiplier: float = 1.5
@export var min_bounce_force: float = 400.0
@export var max_bounce_force: float = 800.0

## --- Internal ---

var _collision_shape: CollisionShape2D
var _polygon: Polygon2D
var _animated_sprite: AnimatedSprite2D
var _hit_area: Area2D
var _is_playing_hit: bool = false

## --- Lifecycle ---

func _ready() -> void:
	add_to_group("walls")
	add_to_group("bumpers")

	_find_children()
	_ensure_unique_shapes()
	_update_bumper()

	## Wire up signals only during gameplay, not in the editor.
	if not Engine.is_editor_hint():
		if _hit_area:
			_hit_area.body_entered.connect(_on_body_hit)
		if _animated_sprite:
			_animated_sprite.animation_finished.connect(_on_animation_finished)

func _find_children() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
		elif child is Polygon2D:
			_polygon = child
		elif child is AnimatedSprite2D:
			_animated_sprite = child
		elif child is Area2D and child.name == "HitArea":
			_hit_area = child

func _ensure_unique_shapes() -> void:
	## Each instance must own its shape resource — avoids the shared-resource mutation bug
	## where changing one bumper's radius silently changes all bumpers using the same scene.
	if _collision_shape and _collision_shape.shape:
		_collision_shape.shape = _collision_shape.shape.duplicate()

	if _hit_area:
		for child in _hit_area.get_children():
			if child is CollisionShape2D and child.shape:
				child.shape = child.shape.duplicate()

## --- Core Update ---

func _update_bumper() -> void:
	if not is_inside_tree():
		return
	_apply_collision_shape()
	_apply_hit_area_shape()
	_apply_sprite()

func _apply_collision_shape() -> void:
	if not _collision_shape:
		return
	if not _collision_shape.shape:
		_collision_shape.shape = CircleShape2D.new()
	_collision_shape.shape.radius = radius

func _apply_hit_area_shape() -> void:
	## Keep the HitArea's CollisionShape2D in sync with the bumper radius.
	if not _hit_area:
		return
	for child in _hit_area.get_children():
		if child is CollisionShape2D:
			## Always create a fresh shape to avoid shared-resource issues.
			var new_circle := CircleShape2D.new()
			new_circle.radius = radius
			child.shape = new_circle

func _apply_sprite() -> void:
	if not _animated_sprite:
		return

	## Build the idle animation name from current size and variant.
	## e.g. size=SMALL, variant="2" → "small_2_idle"
	var size_name: String = SIZE_NAMES.get(int(size_preset), "small")
	var idle_anim: String = "%s_%s_idle" % [size_name, variant]

	var frames: SpriteFrames = _animated_sprite.sprite_frames
	if frames and frames.has_animation(idle_anim):
		_animated_sprite.visible = true
		if _polygon:
			_polygon.visible = false
		## Only restart idle if not currently mid-hit (don't interrupt hit animation).
		if not _is_playing_hit:
			_animated_sprite.play(idle_anim)
	else:
		## No matching animation found — fall back to Polygon2D placeholder.
		_animated_sprite.visible = false
		if _polygon:
			_polygon.visible = true

## --- Hit Response ---

func _on_body_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body is RigidBody2D:
		_apply_bumper_force(body)
		_play_hit_animation()

func _apply_bumper_force(body: RigidBody2D) -> void:
	var collision_normal := (body.global_position - global_position).normalized()
	var current_speed := body.linear_velocity.length()
	var bounce_force: float = clamp(current_speed * bounce_multiplier, min_bounce_force, max_bounce_force)
	body.linear_velocity = collision_normal * bounce_force
	## Small random angle variation keeps repeated hits from feeling mechanical.
	body.linear_velocity = body.linear_velocity.rotated(randf_range(-0.1, 0.1))

func _play_hit_animation() -> void:
	if not _animated_sprite:
		return

	var size_name: String = SIZE_NAMES.get(int(size_preset), "small")
	var hit_anim: String = "%s_%s_hit" % [size_name, variant]
	var frames: SpriteFrames = _animated_sprite.sprite_frames

	if frames and frames.has_animation(hit_anim):
		_is_playing_hit = true
		## loop = false must be set on the hit animation in the SpriteFrames resource.
		_animated_sprite.play(hit_anim)
	## If no hit animation exists for this variant, we just do nothing —
	## the bumper still bounces correctly, it just won't play a visual effect.

func _on_animation_finished() -> void:
	## Only fires for non-looping animations (i.e. the hit animation).
	## Return to idle automatically.
	_is_playing_hit = false
	_apply_sprite()

## --- Public Helpers ---

func get_suggested_radius() -> float:
	return SIZE_RADII.get(int(size_preset), 12.0)

func get_pixel_diameter() -> float:
	return radius * 2.0
