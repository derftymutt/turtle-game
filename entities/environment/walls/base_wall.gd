@tool
extends StaticBody2D
class_name BaseWall

## BASE WALL - Pixel-perfect foundation for all wall types.
##
## PIXEL-PERFECT RULE (same as FlipperBase):
##   - StaticBody2D NEVER rotates (stays at 0°)
##   - CollisionShape2D.rotation_degrees is set to match the angle preset
##   - Sprite2D will swap textures per angle+length combo (when art arrives)
##   - Mirroring is handled via flip_h on the sprite + negating collision rotation
##
## GRID SYSTEM:
##   - Tile size: 8px  (TILE_SIZE constant)
##   - Segment size: 32px = 4 tiles  (SEGMENT_SIZE constant)
##   - length_units drives how many segments long the wall is
##   - Final pixel length = length_units * SEGMENT_SIZE

## --- Constants ---

const TILE_SIZE: int = 8       ## Smallest pixel unit
const SEGMENT_SIZE: int = 32   ## 4 tiles — base length unit for wall segments

## Pixel-perfect angles derived from clean pixel ratios.
## These are exact — do not round them. The sprites in Aseprite should be
## drawn using the matching rise:run ratio for each preset:
##   VERTICAL   → vertical line            (no ratio)
##   STEEP      → 2 pixels down : 1 right  → atan2(2,1) = 63.43°
##   DIAGONAL   → 1 pixel down  : 1 right  → 45°
##   SHALLOW    → 1 pixel down  : 2 right  → atan2(1,2) = 26.57°
##   HORIZONTAL → horizontal line          (no ratio)
const ANGLE_ROTATIONS: Dictionary = {
	0: 0.0,    ## VERTICAL
	1: 63.43,  ## STEEP
	2: 45.0,   ## DIAGONAL
	3: 26.57,  ## SHALLOW
	4: 90.0,   ## HORIZONTAL
}

## --- Enums ---

enum AnglePreset {
	VERTICAL   = 0,
	STEEP      = 1,
	DIAGONAL   = 2,
	SHALLOW    = 3,
	HORIZONTAL = 4,
}

## --- Exports ---

@export_group("Shape")

@export var angle_preset: AnglePreset = AnglePreset.VERTICAL:
	set(value):
		angle_preset = value
		_update_wall()

## Number of 32px segments. 1 = 32px, 2 = 64px, 3 = 96px, 4 = 128px, etc.
@export_range(1, 16, 1) var length_units: int = 2:
	set(value):
		length_units = value
		_update_wall()

## Flips the wall horizontally — mirrors angle and sprite without a separate scene.
@export var mirrored: bool = false:
	set(value):
		mirrored = value
		_update_wall()

## --- Internal State ---

## Cached child references — found once in _ready(), never recreated.
var _collision_shape: CollisionShape2D
var _polygon: Polygon2D
var _sprite: Sprite2D  ## nil until art is added — safe to leave empty

## --- Lifecycle ---

func _ready() -> void:
	_find_children()
	_ensure_unique_shapes()
	_update_wall()

func _find_children() -> void:
	## Cache node references by type. Using typed iteration is safer than get_node()
	## because it works regardless of child order or name changes.
	## Subclasses call super._find_children() then locate their own Area2D children.
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
		elif child is Polygon2D:
			_polygon = child
		elif child is Sprite2D:
			_sprite = child

func _ensure_unique_shapes() -> void:
	## CRITICAL: Duplicate shared resources so each instance is independent.
	## Without this, editing one wall's CollisionShape2D size in the editor
	## changes ALL walls that were instantiated from the same .tscn, because
	## they share the same RectangleShape2D sub-resource by default.
	if _collision_shape and _collision_shape.shape:
		_collision_shape.shape = _collision_shape.shape.duplicate()

## --- Core Update ---

func _update_wall() -> void:
	## Guard: node must be in the tree before touching child nodes.
	## Export setters fire during scene loading before _ready() runs —
	## this check prevents null-reference crashes during that window.
	if not is_inside_tree():
		return

	_apply_collision_shape()
	_apply_visual()
	_apply_sprite()
	_on_wall_updated()  ## Hook for subclasses to resize their own Area2D shapes

func _apply_collision_shape() -> void:
	if not _collision_shape:
		return

	## Size: always TILE_SIZE thick, length_units * SEGMENT_SIZE long.
	## RectangleShape2D.size is the FULL extent (not half-extent).
	var pixel_length: float = float(length_units * SEGMENT_SIZE)
	var pixel_thickness: float = float(TILE_SIZE)

	if not _collision_shape.shape:
		_collision_shape.shape = RectangleShape2D.new()
	_collision_shape.shape.size = Vector2(pixel_length, pixel_thickness)

	## Rotate the CollisionShape2D child — never the StaticBody2D root.
	## Negating the angle for mirrored flips the wall to the opposite diagonal.
	_collision_shape.rotation_degrees = get_collision_rotation_degrees()
	_collision_shape.position = Vector2.ZERO  ## Always centered on parent origin

func _apply_visual() -> void:
	## Placeholder polygon that matches the collision shape exactly.
	## Rotated the same way so the visual always lines up with physics.
	## Removed and replaced by _apply_sprite() once sprite art arrives.
	if not _polygon:
		return

	var pixel_length: float = float(length_units * SEGMENT_SIZE)
	var pixel_thickness: float = float(TILE_SIZE)
	var half_l: float = pixel_length * 0.5
	var half_t: float = pixel_thickness * 0.5

	_polygon.rotation_degrees = get_collision_rotation_degrees()
	_polygon.position = Vector2.ZERO

	_polygon.polygon = PackedVector2Array([
		Vector2(-half_l, -half_t),
		Vector2( half_l, -half_t),
		Vector2( half_l,  half_t),
		Vector2(-half_l,  half_t),
	])

func _apply_sprite() -> void:
	## Called every update. Safe no-op if no Sprite2D exists in the scene yet.
	## When art arrives: add a Sprite2D child to the scene, then implement
	## _get_texture_for_preset() to return the correct texture per angle+length.
	if not _sprite:
		return
	_sprite.flip_h = mirrored
	## TODO: _sprite.texture = _get_texture_for_preset(angle_preset, length_units)

## --- Subclass Hook ---

func _on_wall_updated() -> void:
	## Override in subclasses to react when shape/angle/length/mirror changes.
	## Called at the END of _update_wall(), after collision and visual are applied.
	pass

## --- Public Helpers ---

func get_pixel_length() -> float:
	return float(length_units * SEGMENT_SIZE)

func get_pixel_thickness() -> float:
	return float(TILE_SIZE)

func get_collision_rotation_degrees() -> float:
	## Single source of truth for the wall's rotation.
	## Always use this — never read ANGLE_ROTATIONS directly in subclasses.
	var degrees: float = ANGLE_ROTATIONS.get(int(angle_preset), 0.0)
	return -degrees if mirrored else degrees
