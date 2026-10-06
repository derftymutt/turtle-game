extends Node2D
class_name SquidSpawner

## Places squid_count squids when the level starts, each already hidden in a
## wall (any DeadWall face or collidable TileMapLayer — see
## Squid.find_hide_spots). Spots are picked from rays cast out of random
## points in the spawn area, kept apart from each other and from the turtle.

@export var squid_scene: PackedScene
@export var squid_count: int = 3

@export_group("Placement")
## World-space rectangle the search rays start from. Squids hide on whatever
## walls those rays reach, which can be a little outside it.
@export var spawn_area_min: Vector2 = Vector2(-300, -90)
@export var spawn_area_max: Vector2 = Vector2(300, 150)
## How far each search ray reaches
@export var search_range: float = 250.0
## Minimum distance between two squids' hiding spots
@export var min_spacing: float = 80.0
## Minimum distance from the turtle, so it doesn't start next to one
@export var min_player_distance: float = 120.0

const _PLACEMENT_ATTEMPTS: int = 30

func _ready() -> void:
	if not squid_scene:
		push_error("SquidSpawner: squid_scene not assigned!")
		return
	_spawn_all.call_deferred()

func _spawn_all() -> void:
	# Hide spots are found by raycasting, so the level's walls must be in the
	# physics space first.
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	var ocean := get_tree().get_first_node_in_group("ocean") as Ocean
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var taken: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("squids"):
		taken.append((node as Node2D).global_position)

	for i in squid_count:
		var squid := squid_scene.instantiate() as Squid
		var min_y: float = (ocean.surface_y if ocean else -INF) + squid.min_depth
		var spot := _find_spot(taken, player, min_y)
		if spot.is_empty():
			squid.free()
			push_warning("SquidSpawner: no free wall spot for squid %d of %d" % [i + 1, squid_count])
			continue
		get_parent().add_child(squid)
		squid.hide_at(spot.position, spot.normal)
		taken.append(squid.claimed_spot)

		squid.modulate.a = 0.0
		# Fades in even while the level is held by the start prompt
		squid.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)\
			.tween_property(squid, "modulate:a", 1.0, 0.4)

func _find_spot(taken: Array[Vector2], player: Node2D, min_y: float) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var point := PhysicsPointQueryParameters2D.new()
	point.collision_mask = 1

	for attempt in _PLACEMENT_ATTEMPTS:
		var origin := Vector2(
			randf_range(spawn_area_min.x, spawn_area_max.x),
			randf_range(maxf(spawn_area_min.y, min_y), spawn_area_max.y))
		point.position = origin
		if not space.intersect_point(point, 1).is_empty():
			continue  # started inside a wall

		var spots := Squid.find_hide_spots(get_world_2d(), origin, search_range, 12, min_y)
		spots.shuffle()
		for spot in spots:
			var pos: Vector2 = spot.position
			if player and pos.distance_to(player.global_position) < min_player_distance:
				continue
			var crowded := false
			for other in taken:
				if pos.distance_to(other) < min_spacing:
					crowded = true
					break
			if not crowded:
				return spot
	return {}
