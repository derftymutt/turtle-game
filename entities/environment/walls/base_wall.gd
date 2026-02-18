@tool
extends StaticBody2D
class_name BaseWall

## BASE WALL - Pixel-perfect foundation for all wall types.
##
## PIXEL-PERFECT RULE (same as FlipperBase):
##   - StaticBody2D NEVER rotates (stays at 0°)
##   - CollisionShape2D.rotation_degrees is set to match the angle preset
##   - Sprite2D swaps textures per angle+length combo
##   - Polygon2D is the placeholder — hidden automatically when a sprite loads
##   - Mirroring is handled via flip_h on the sprite + negating collision rotation
##
## GRID SYSTEM:
##   - Tile size: 8px  (TILE_SIZE constant)
##   - Segment size: 32px = 4 tiles  (SEGMENT_SIZE constant)
##   - length_units drives how many segments long the wall is
##   - Final pixel length = length_units * SEGMENT_SIZE
##
## ADDING SPRITES:
##   1. Export PNGs from Aseprite named: wall_<angle>_<length>u.png
##      e.g. wall_vertical_1u.png, wall_shallow_2u.png
##   2. Place all PNGs in: res://assets/sprites/walls/
##   3. Set each texture's filter to Nearest in the Import tab
##   4. Add a Sprite2D child to your wall scene
##   5. The script handles everything else automatically

## --- Constants ---

const TILE_SIZE: int = 8       ## Smallest pixel unit
const SEGMENT_SIZE: int = 32   ## 4 tiles — base length unit for wall segments

## Sprite folder — change this if you move your wall art
const SPRITE_PATH: String = "res://entities/environment/walls/dead_wall/sprites/"

## Angle name strings — must match your PNG filenames exactly
const ANGLE_NAMES: Dictionary = {
	0: "vertical",
	1: "steep",
	2: "diagonal",
	3: "shallow",
	4: "horizontal",
}

## Pixel-perfect angles derived from clean pixel ratios:
##   VERTICAL   → 0°      (straight up)
##   STEEP      → 63.43°  (2:1 rise:run)
##   DIAGONAL   → 45°     (1:1 rise:run)
##   SHALLOW    → 26.57°  (1:2 rise:run)
##   HORIZONTAL → 90°     (straight across)
const ANGLE_ROTATIONS: Dictionary = {
	0: 0.0,
	1: 63.43,
	2: 45.0,
	3: 26.57,
	4: 90.0,
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

var _collision_shape: CollisionShape2D
var _polygon: Polygon2D
var _sprite: Sprite2D

## Cache loaded textures so we only hit disk once per unique combination.
## This is a class-level (static) cache shared across all wall instances.
static var _texture_cache: Dictionary = {}

## --- Lifecycle ---

func _ready() -> void:
	_find_children()
	_ensure_unique_shapes()
	_update_wall()

func _find_children() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
		elif child is Polygon2D:
			_polygon = child
		elif child is Sprite2D:
			_sprite = child

func _ensure_unique_shapes() -> void:
	if _collision_shape and _collision_shape.shape:
		_collision_shape.shape = _collision_shape.shape.duplicate()

## --- Core Update ---

func _update_wall() -> void:
	if not is_inside_tree():
		return
	_apply_collision_shape()
	_apply_visual()
	_apply_sprite()
	_on_wall_updated()

func _apply_collision_shape() -> void:
	if not _collision_shape:
		return

	var pixel_length: float = float(length_units * SEGMENT_SIZE)
	var pixel_thickness: float = float(TILE_SIZE)

	if not _collision_shape.shape:
		_collision_shape.shape = RectangleShape2D.new()
	_collision_shape.shape.size = Vector2(pixel_length, pixel_thickness)
	_collision_shape.rotation_degrees = get_collision_rotation_degrees()
	_collision_shape.position = Vector2.ZERO

func _apply_visual() -> void:
	## Polygon2D placeholder — only visible when no sprite texture is loaded.
	## Hidden automatically in _apply_sprite() once art is available.
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
	if not _sprite:
		return

	var texture := _load_wall_texture(angle_preset, length_units)

	if texture:
		_sprite.texture = texture
		_sprite.flip_h = mirrored
		_sprite.visible = true
		## Hide the placeholder polygon — sprite has taken over
		if _polygon:
			_polygon.visible = false
	else:
		## No sprite found — fall back to polygon placeholder
		_sprite.visible = false
		if _polygon:
			_polygon.visible = true

func _load_wall_texture(preset: AnglePreset, units: int) -> Texture2D:
	## Build the cache key and return immediately if already loaded.
	var cache_key: String = "%d_%d" % [int(preset), units]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]

	## Build the expected file path from the naming convention.
	## e.g. res://assets/sprites/walls/wall_shallow_2u.png
	var angle_name: String = ANGLE_NAMES.get(int(preset), "unknown")
	var path: String = "%swall_%s_%du.png" % [SPRITE_PATH, angle_name, units]
	
	print("Wall texture path: ", path, " | exists: ", ResourceLoader.exists(path))

	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		## Not a crash — just means this combo has no art yet.
		## Polygon2D placeholder will show instead.
		pass

	## Cache the result (even if null) so we don't retry on every update.
	_texture_cache[cache_key] = texture
	return texture

## --- Subclass Hook ---

func _on_wall_updated() -> void:
	pass

## --- Public Helpers ---

func get_pixel_length() -> float:
	return float(length_units * SEGMENT_SIZE)

func get_pixel_thickness() -> float:
	return float(TILE_SIZE)

func get_collision_rotation_degrees() -> float:
	var degrees: float = ANGLE_ROTATIONS.get(int(angle_preset), 0.0)
	return -degrees if mirrored else degrees
