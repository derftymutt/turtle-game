extends Node
class_name HealthPlantSpawner

## Spawns health plants on DeadWalls when score thresholds are reached
## Automatically finds walls and picks random spawn locations

@export var health_plant_scene: PackedScene

@export_group("Spawn Thresholds")
@export var spawn_thresholds: Array[int] = [500, 1000, 1500, 2000]  # Score values that trigger spawns
@export var max_simultaneous_plants: int = 2  # Maximum plants that can exist at once

@export_group("Wall Selection")
@export var min_wall_length: float = 30.0  # Only spawn on walls this long or longer
@export var edge_margin: float = 20.0  # Stay this far from wall edges

# Internal state
var current_threshold_index: int = 0
var active_plants: Array[Node] = []
var hud: HUD = null
var last_known_score: int = 0

func _ready():
	# Find HUD to monitor score
	hud = get_tree().get_first_node_in_group("hud")
	
	if not hud:
		push_warning("HealthPlantSpawner: No HUD found! Cannot monitor score.")
		return
	
	if not health_plant_scene:
		push_error("HealthPlantSpawner: No health_plant_scene assigned!")
		return
	
	print("🌿 Health Plant Spawner ready. Thresholds: ", spawn_thresholds)

func _process(_delta):
	if not hud:
		return
	
	# Check for score threshold crossings
	var current_score = hud.current_score
	
	if current_score != last_known_score:
		_check_spawn_thresholds(current_score)
		last_known_score = current_score
	
	# Clean up destroyed plants from tracking
	active_plants = active_plants.filter(func(plant): return is_instance_valid(plant))

func _check_spawn_thresholds(score: int):
	"""Check if we've crossed any spawn thresholds"""
	# Check all thresholds we haven't processed yet
	while current_threshold_index < spawn_thresholds.size():
		var threshold = spawn_thresholds[current_threshold_index]
		
		if score >= threshold:
			print("🌿 Score threshold reached: ", threshold)
			_try_spawn_plant()
			current_threshold_index += 1
		else:
			break

func _try_spawn_plant():
	"""Attempt to spawn a health plant on a random wall"""
	# Check if we're at the simultaneous plant limit
	if active_plants.size() >= max_simultaneous_plants:
		print("🌿 Cannot spawn - at max simultaneous plants (", max_simultaneous_plants, ")")
		return
	
	# Find all eligible walls
	var walls = _find_eligible_walls()
	
	if walls.is_empty():
		push_warning("HealthPlantSpawner: No eligible walls found!")
		return
	
	# Pick a random wall
	var chosen_wall = walls.pick_random()
	
	# Spawn plant on this wall
	_spawn_plant_on_wall(chosen_wall)

func _find_eligible_walls() -> Array:
	"""Find all DeadWalls that meet spawning criteria"""
	var eligible_walls = []
	
	# Get all walls in the scene
	var all_walls = get_tree().get_nodes_in_group("walls")
	
	for wall in all_walls:
		# Only spawn on DeadWalls (not flippers or other wall types)
		if not wall is DeadWall:
			continue
		
		# Check minimum length
		if wall.wall_length < min_wall_length:
			continue
		
		# Check if wall already has a plant attached
		if _wall_has_plant(wall):
			continue
		
		eligible_walls.append(wall)
	
	return eligible_walls

func _wall_has_plant(wall: Node2D) -> bool:
	"""Check if a wall already has a plant on it"""
	for plant in active_plants:
		if plant.attached_wall == wall:
			return true
	return false

func _spawn_plant_on_wall(wall: DeadWall):
	"""Spawn a health plant on the specified wall"""
	if not health_plant_scene:
		return
	
	# Create plant instance
	var plant = health_plant_scene.instantiate()
	
	# Add to scene (parent of spawner)
	get_parent().add_child(plant)
	
	# Calculate spawn position along wall
	var spawn_info = _calculate_wall_spawn_position(wall)
	
	# Attach plant to wall
	plant.attach_to_wall_surface(wall, spawn_info.position, spawn_info.normal)
	
	# Track active plant
	active_plants.append(plant)
	
	print("🌿 Spawned health plant on wall: ", wall.name)

func _calculate_wall_spawn_position(wall: DeadWall) -> Dictionary:
	"""Calculate a random position along the wall surface"""
	# Wall is a rectangle, we want to spawn along one of its edges
	# For simplicity, we'll spawn along the top edge (before rotation)
	
	# Random position along wall length (with edge margins)
	var wall_half_length = wall.wall_length / 2.0
	
	# Use smart edge margin: minimum of specified margin or 25% of wall length
	# This prevents negative safe space on small walls
	var actual_margin = min(edge_margin, wall.wall_length * 0.25)
	var safe_length = wall_half_length - actual_margin
	
	# Clamp to ensure we always have some safe space
	safe_length = max(safe_length, 5.0)
	
	var random_offset = randf_range(-safe_length, safe_length)
	
	# Local position on wall (top edge in local space)
	var local_pos = Vector2(random_offset, -wall.wall_thickness / 2.0)
	
	# Transform to global position using wall's transform
	var global_pos = wall.global_position + local_pos.rotated(wall.global_rotation)
	
	# Normal direction (perpendicular to wall, pointing outward)
	# For top edge, normal points up in local space
	var local_normal = Vector2(0, -1)
	var global_normal = local_normal.rotated(wall.global_rotation)
	
	return {
		"position": global_pos,
		"normal": global_normal
	}

## Public method to manually trigger a spawn (useful for testing)
func spawn_plant_now():
	_try_spawn_plant()

## Public method to reset thresholds (e.g., on level restart)
func reset_thresholds():
	current_threshold_index = 0
	
	# Remove all active plants
	for plant in active_plants:
		if is_instance_valid(plant):
			plant.queue_free()
	
	active_plants.clear()
	print("🌿 Health plant spawner reset")
