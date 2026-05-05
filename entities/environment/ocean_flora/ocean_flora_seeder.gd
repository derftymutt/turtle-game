extends Node2D
class_name OceanFloraSeeder

@export var flora_scene: PackedScene = null

@export_group("Seeding")
@export var total_flora_count: int = 5

func _ready():
	if not flora_scene:
		push_warning("OceanFloraSeeder: No flora_scene assigned!")
		return
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
	spawn_points.shuffle()
	var chosen = spawn_points.slice(0, actual_count)

	for i in actual_count:
		var flora = flora_scene.instantiate()
		get_parent().add_child(flora)
		flora.global_position = chosen[i].global_position
		flora.rotation = chosen[i].rotation

	print("🌿 Seeded %d flora" % actual_count)
