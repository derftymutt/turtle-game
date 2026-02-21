extends Node
class_name HealthPlantSpawner

## Spawns health plants on DeadWalls when score thresholds are reached.
## Updated to work with BaseWall's dynamic length system:
##   - wall.get_pixel_length()    replaces wall.wall_length
##   - wall.get_pixel_thickness() replaces wall.wall_thickness
##   - wall.get_collision_rotation_degrees() replaces wall.global_rotation
##     (StaticBody2D no longer rotates — only the CollisionShape2D child does)

@export var health_plant_scene: PackedScene

@export_group("Spawn Thresholds")
@export var spawn_thresholds: Array[int] = [400, 800, 1200, 1600]
@export var max_simultaneous_plants: int = 2

@export_group("Wall Selection")
## Minimum wall pixel length to be eligible. 1 length_unit = 32px, so all
## walls (minimum 32px) are eligible by default.
@export var min_wall_length: float = 30.0
@export var edge_margin: float = 20.0

## --- Internal State ---

var current_threshold_index: int = 0
var active_plants: Array[Node] = []
var hud: HUD = null
var last_known_score: int = 0

func _ready() -> void:
	hud = get_tree().get_first_node_in_group("hud")

	if not hud:
		push_warning("HealthPlantSpawner: No HUD found! Cannot monitor score.")
		return

	if not health_plant_scene:
		push_error("HealthPlantSpawner: No health_plant_scene assigned!")
		return

	print("🌿 Health Plant Spawner ready. Thresholds: ", spawn_thresholds)

func _process(_delta: float) -> void:
	if not hud:
		return

	var current_score: int = hud.current_score

	if current_score != last_known_score:
		_check_spawn_thresholds(current_score)
		last_known_score = current_score

	## Clean up any plants that have been destroyed
	active_plants = active_plants.filter(func(plant): return is_instance_valid(plant))

func _check_spawn_thresholds(score: int) -> void:
	while current_threshold_index < spawn_thresholds.size():
		var threshold: int = spawn_thresholds[current_threshold_index]
		if score >= threshold:
			print("🌿 Score threshold reached: ", threshold)
			_try_spawn_plant()
			current_threshold_index += 1
		else:
			break

func _try_spawn_plant() -> void:
	if active_plants.size() >= max_simultaneous_plants:
		print("🌿 Cannot spawn - at max simultaneous plants (", max_simultaneous_plants, ")")
		return

	var walls := _find_eligible_walls()

	if walls.is_empty():
		push_warning("HealthPlantSpawner: No eligible walls found!")
		return

	_spawn_plant_on_wall(walls.pick_random())

func _find_eligible_walls() -> Array:
	var eligible: Array = []

	for wall in get_tree().get_nodes_in_group("walls"):
		if not wall is DeadWall:
			continue

		## Use BaseWall's helper — no more direct wall_length property
		if wall.get_pixel_length() < min_wall_length:
			continue

		if _wall_has_plant(wall):
			continue

		eligible.append(wall)

	return eligible

func _wall_has_plant(wall: Node2D) -> bool:
	for plant in active_plants:
		if is_instance_valid(plant) and plant.attached_wall == wall:
			return true
	return false

func _spawn_plant_on_wall(wall: DeadWall) -> void:
	if not health_plant_scene:
		return

	var plant := health_plant_scene.instantiate()
	get_parent().add_child(plant)

	var spawn_info := _calculate_wall_spawn_position(wall)
	plant.attach_to_wall_surface(wall, spawn_info.position, spawn_info.normal)

	active_plants.append(plant)
	print("🌿 Spawned health plant on wall: ", wall.name)

func _calculate_wall_spawn_position(wall: DeadWall) -> Dictionary:
	## BaseWall exposes get_pixel_length() and get_pixel_thickness() for this.
	## The StaticBody2D no longer carries the wall rotation — that lives on the
	## CollisionShape2D child. We retrieve it via get_collision_rotation_degrees()
	## and convert to radians for Vector2.rotated().
	var pixel_length: float = wall.get_pixel_length()
	var pixel_thickness: float = wall.get_pixel_thickness()
	var wall_rotation_rad: float = deg_to_rad(wall.get_collision_rotation_degrees())

	## Calculate safe spawn range along the wall length
	var half_length: float = pixel_length * 0.5
	var actual_margin: float = min(edge_margin, pixel_length * 0.25)
	var safe_length: float = max(half_length - actual_margin, 5.0)
	var random_offset: float = randf_range(-safe_length, safe_length)

	## Local position: along wall centerline, offset to top surface.
	## CollisionShape2D is centered at the wall's origin, so local space
	## still has the wall centered at (0,0) — same as before.
	var local_pos := Vector2(random_offset, -pixel_thickness * 0.5)

	## Rotate into global space using the wall's collision rotation.
	## wall.global_position is still valid — the StaticBody2D root is
	## placed in the world normally, only its child shape is rotated.
	var global_pos: Vector2 = wall.global_position + local_pos.rotated(wall_rotation_rad)

	## Surface normal: perpendicular to wall, pointing away from wall face.
	## In local space this is straight up (0, -1), rotated into world space.
	var global_normal: Vector2 = Vector2(0.0, -1.0).rotated(wall_rotation_rad)

	return {
		"position": global_pos,
		"normal": global_normal,
	}

## --- Public API ---

func spawn_plant_now() -> void:
	_try_spawn_plant()

func reset_thresholds() -> void:
	current_threshold_index = 0
	for plant in active_plants:
		if is_instance_valid(plant):
			plant.queue_free()
	active_plants.clear()
	print("🌿 Health plant spawner reset")
