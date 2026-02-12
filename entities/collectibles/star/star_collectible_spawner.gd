extends Node2D
class_name CollectibleSpawner

## Spawns collectibles (stars, coins, etc.) periodically at specified locations
## Matches the pattern of AirBubbleSpawner and PiranhaSpawner

@export var collectible_scene: PackedScene

@export_group("Spawn Settings")
@export var spawn_interval: float = 5.0  # Seconds between spawns
@export var spawn_count_min: int = 2  # Minimum collectibles per spawn
@export var spawn_count_max: int = 2  # Maximum collectibles per spawn

@export_group("Spawn Position")
@export var use_fixed_points: bool = false  # Use spawn points vs random
@export var spawn_margin: float = 50.0  # Distance from screen edges for random spawns

@export_group("Random Spawn Area")
@export var random_spawn_min_x: float = -280.0
@export var random_spawn_max_x: float = 280.0
@export var random_spawn_min_y: float = -100.0  # Start above water
@export var random_spawn_max_y: float = -50.0   # Above surface

@export_group("Spawn Points")
@export var spawn_point_paths: Array[NodePath] = []  # Marker2D nodes for fixed spawning

var spawn_timer: float = 0.0
var spawn_points: Array[Node2D] = []

func _ready():
	# Collect spawn point references
	if use_fixed_points:
		for path in spawn_point_paths:
			var node = get_node_or_null(path)
			if node and node is Node2D:
				spawn_points.append(node)
			else:
				push_warning("Invalid spawn point: ", path)
		
		if spawn_points.is_empty():
			push_warning("No valid spawn points! Falling back to random spawning.")
			use_fixed_points = false
	
	# Start spawn timer with random offset to avoid all spawners syncing
	spawn_timer = randf_range(0, spawn_interval * 0.5)

func _process(delta):
	spawn_timer -= delta
	
	if spawn_timer <= 0:
		spawn_collectible_wave()
		spawn_timer = spawn_interval

func spawn_collectible_wave():
	"""Spawn a wave of collectibles"""
	if not collectible_scene:
		push_warning("No collectible scene assigned to spawner!")
		return
	
	var count = randi_range(spawn_count_min, spawn_count_max)
	
	for i in count:
		spawn_collectible()

func spawn_collectible():
	"""Spawn a single collectible"""
	var collectible = collectible_scene.instantiate()
	get_parent().add_child(collectible)
	
	# Determine spawn position
	var spawn_pos: Vector2
	
	if use_fixed_points and not spawn_points.is_empty():
		# Random from spawn points
		var point = spawn_points.pick_random()
		spawn_pos = point.global_position
	else:
		# Random within bounds
		spawn_pos = get_random_spawn_position()
	
	collectible.global_position = spawn_pos
	
	# Optional: Add slight random offset for variety
	collectible.global_position += Vector2(
		randf_range(-20, 20),
		randf_range(-10, 10)
	)

func get_random_spawn_position() -> Vector2:
	"""Get a random position within spawn bounds"""
	return Vector2(
		randf_range(random_spawn_min_x, random_spawn_max_x),
		randf_range(random_spawn_min_y, random_spawn_max_y)
	)

## Debug helper to visualize spawn area in editor
func _draw():
	if Engine.is_editor_hint() and not use_fixed_points:
		# Draw spawn area rectangle
		var rect_pos = Vector2(random_spawn_min_x, random_spawn_min_y)
		var rect_size = Vector2(
			random_spawn_max_x - random_spawn_min_x,
			random_spawn_max_y - random_spawn_min_y
		)
		
		# Semi-transparent yellow for collectibles
		draw_rect(Rect2(rect_pos, rect_size), Color(1.0, 0.9, 0.2, 0.2))
		draw_rect(Rect2(rect_pos, rect_size), Color(1.0, 0.9, 0.2, 0.8), false, 2.0)
