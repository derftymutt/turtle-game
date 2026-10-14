extends Node2D
class_name HdTileLayerArt

## High-res stand-in for a TileMapLayer's drawing (see HdArt). A TileSet can't
## scale its textures, so this sibling node paints every used cell from an HD
## copy of the atlas (same layout, HdArt.SCALE x larger) and the layer itself is
## hidden while HD is on — its collision is unaffected by visibility.
##
## HD_ATLASES maps a pixel atlas texture to its HD copy; any layer whose tiles
## come from one of them gets an overlay from attach_all().

const HD_ATLASES: Dictionary = {
	"res://entities/environment/ocean_boundaries/ocean_wall.png": "res://entities/environment/ocean_boundaries/hd/ocean_wall.svg",
	"res://entities/environment/ocean_boundaries/ocean_floor.png": "res://entities/environment/ocean_boundaries/hd/ocean_floor.svg",
}
const _FLIP_H: int = TileSetAtlasSource.TRANSFORM_FLIP_H
const _FLIP_V: int = TileSetAtlasSource.TRANSFORM_FLIP_V
const _TRANSPOSE: int = TileSetAtlasSource.TRANSFORM_TRANSPOSE

var layer: TileMapLayer
var _hd_textures: Dictionary = {}  ## source id -> HD Texture2D

## Adds an overlay beside every TileMapLayer under `root` that uses an HD-mapped atlas.
static func attach_all(root: Node) -> void:
	for node in root.find_children("*", "TileMapLayer", true, false):
		var hd_textures: Dictionary = _hd_textures_for(node)
		if hd_textures.is_empty():
			continue
		var art := HdTileLayerArt.new()
		art.layer = node
		art._hd_textures = hd_textures
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.add_sibling(art)
		node.changed.connect(art.queue_redraw)
		art.add_to_group(HdArt.GROUP_ENVIRONMENT)
		art.refresh_hd_art()

static func _hd_textures_for(tile_layer: TileMapLayer) -> Dictionary:
	var result: Dictionary = {}
	var tile_set: TileSet = tile_layer.tile_set
	if tile_set == null:
		return result
	for i in tile_set.get_source_count():
		var id: int = tile_set.get_source_id(i)
		var source := tile_set.get_source(id) as TileSetAtlasSource
		if source and source.texture and HD_ATLASES.has(source.texture.resource_path):
			result[id] = load(HD_ATLASES[source.texture.resource_path])
	return result

## HdArt: the environment category was toggled.
func refresh_hd_art() -> void:
	var hd: bool = HdArt.environment_on()
	visible = hd
	layer.visible = not hd
	transform = layer.transform
	z_index = layer.z_index
	modulate = layer.modulate
	queue_redraw()

func _draw() -> void:
	var tile_set: TileSet = layer.tile_set
	for cell in layer.get_used_cells():
		var id: int = layer.get_cell_source_id(cell)
		if not _hd_textures.has(id):
			continue
		var source := tile_set.get_source(id) as TileSetAtlasSource
		var region_size := Vector2(source.texture_region_size)
		var atlas := Vector2(layer.get_cell_atlas_coords(cell))
		var src := Rect2(atlas * region_size * HdArt.SCALE, region_size * HdArt.SCALE)
		var alt: int = layer.get_cell_alternative_tile(cell)
		var flip := Vector2(-1.0 if alt & _FLIP_H else 1.0, -1.0 if alt & _FLIP_V else 1.0)
		draw_set_transform(layer.map_to_local(cell), 0.0, flip)
		draw_texture_rect_region(_hd_textures[id], Rect2(-region_size * 0.5, region_size), src,
				Color.WHITE, alt & _TRANSPOSE != 0)
	draw_set_transform(Vector2.ZERO)
