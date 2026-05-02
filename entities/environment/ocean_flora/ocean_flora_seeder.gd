extends Node2D
class_name OceanFloraSeeder

@export var flora_scene: PackedScene = null
@export var tech_piece_scene: PackedScene = null

@export_group("Seeding")
@export var total_flora_count: int = 5
@export var min_pieces_hidden: int = 1
@export var max_pieces_hidden: int = 3

func _ready():
	if not flora_scene:
		push_warning("OceanFloraSeeder: No flora_scene assigned!")
		return
	# Defer until after all _ready() calls complete so add_child and global_position
	# propagate correctly to the physics server.
	_seed_flora.call_deferred()

func _seed_flora():
	var spawn_points: Array[Node2D] = []
	for child in get_children():
		if child is Marker2D:
			spawn_points.append(child)

	if spawn_points.is_empty():
		push_warning("OceanFloraSeeder: No Marker2D children!")
		return

	var actual_count = min(total_flora_count, spawn_points.size())
	var budget = LevelManager.get_or_roll_flora_budget(min_pieces_hidden, max_pieces_hidden)
	var remaining_pieces = budget - LevelManager.alien_tech_pieces_collected
	var actual_pieces = min(max(remaining_pieces, 0), actual_count)

	spawn_points.shuffle()
	var chosen = spawn_points.slice(0, actual_count)

	var indices = range(actual_count)
	indices.shuffle()
	var piece_indices = indices.slice(0, actual_pieces)

	for i in actual_count:
		var flora = flora_scene.instantiate()
		get_parent().add_child(flora)
		flora.global_position = chosen[i].global_position
		flora.rotation = chosen[i].rotation
		flora.reveals_tech_piece = (i in piece_indices)
		if flora.reveals_tech_piece and tech_piece_scene:
			flora.tech_piece_scene = tech_piece_scene

	print("🌿 Seeded %d flora (%d hide tech pieces)" % [actual_count, actual_pieces])
