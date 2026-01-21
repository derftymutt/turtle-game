extends Node2D
class_name FloorSeeder

## Seeds the ocean floor with valuable collectibles at game start
## Places collectibles directly on floor so they're immediately valuable

@export var collectible_scene: PackedScene

@export_group("Seeding Settings")
@export var seed_count_min: int = 3  # Minimum collectibles to spawn
@export var seed_count_max: int = 5  # Maximum collectibles to spawn
@export var seed_on_ready: bool = true  # Spawn immediately on level start

@export_group("Floor Position")
@export var use_fixed_points: bool = false  # Use spawn points vs random placement
@export var floor_y: float = 165.0  # Y position of ocean floor (slightly above 160 threshold)

@export_group("Random Floor Area")
@export var floor_min_x: float = -280.0
@export var floor_max_x: float = 280.0
@export var placement_spacing: float = 80.0  # Minimum distance between collectibles

@export_group("Spawn Points")
@export var spawn_point_paths: Array[NodePath] = []  # Marker2D nodes for fixed placement

var spawn_points: Array[Node2D] = []
var placed_positions: Array[Vector2] = []  # Track placements for spacing

func _ready():
	# Collect spawn point references
	if use_fixed_points:
		for path in spawn_point_paths:
			var node = get_node_or_null(path)
			if node and node is Node2D:
				spawn_points.append(node)
			else:
				push_warning("FloorSeeder: Invalid spawn point: ", path)
		
		if spawn_points.is_empty():
			push_warning("FloorSeeder: No valid spawn points! Falling back to random placement.")
			use_fixed_points = false
	
	# Seed the floor (with delay to ensure scene is fully initialized)
	if seed_on_ready:
		# Wait for scene to fully initialize (ocean, camera, etc.)
		# This delay is important - spawning too early causes collectibles to be invisible
		await get_tree().create_timer(0.1).timeout
		seed_floor()

func seed_floor():
	"""Seed the ocean floor with valuable collectibles"""
	if not collectible_scene:
		push_warning("FloorSeeder: No collectible scene assigned!")
		return
	
	var count = randi_range(seed_count_min, seed_count_max)
	placed_positions.clear()
	
	print("🌟 Seeding ocean floor with ", count, " valuable collectibles...")
	
	for i in count:
		spawn_floor_collectible()
	
	print("✓ Floor seeding complete!")

func spawn_floor_collectible():
	"""Spawn a single collectible on the floor"""
	if not collectible_scene:
		push_error("FloorSeeder: No collectible scene assigned!")
		return
	
	var collectible = collectible_scene.instantiate()
	get_parent().add_child(collectible)
	
	# Determine spawn position
	var spawn_pos: Vector2
	
	if use_fixed_points and not spawn_points.is_empty():
		# Use fixed spawn points
		var point = spawn_points.pick_random()
		spawn_pos = point.global_position
	else:
		# Random placement with spacing
		spawn_pos = get_spaced_floor_position()
	
	collectible.global_position = spawn_pos
	
	# Make it immediately valuable (high z_index to ensure visibility)
	collectible.z_index = 100
	
	if collectible.has_method("make_valuable_immediately"):
		collectible.make_valuable_immediately()
	else:
		# Fallback: directly set the collectible as valuable
		collectible.is_valuable = true
		collectible.on_floor = true
		collectible.point_value = collectible.point_value_valuable
		collectible.disable_floor_despawn = true
		
		# Make mostly stationary
		collectible.linear_velocity = Vector2.ZERO
		collectible.angular_velocity = 0.0
		collectible.linear_damp = 20.0
		collectible.gravity_scale = 0.0

func get_spaced_floor_position() -> Vector2:
	"""Get a random floor position that's spaced away from other collectibles"""
	var max_attempts = 20
	var attempt = 0
	
	while attempt < max_attempts:
		var candidate = Vector2(
			randf_range(floor_min_x, floor_max_x),
			floor_y
		)
		
		# Check if far enough from existing collectibles
		if is_position_valid(candidate):
			placed_positions.append(candidate)
			return candidate
		
		attempt += 1
	
	# Fallback: just return a random position if we couldn't find spaced one
	var fallback = Vector2(
		randf_range(floor_min_x, floor_max_x),
		floor_y
	)
	placed_positions.append(fallback)
	return fallback

func is_position_valid(pos: Vector2) -> bool:
	"""Check if position is far enough from other placed collectibles"""
	for placed_pos in placed_positions:
		if pos.distance_to(placed_pos) < placement_spacing:
			return false
	return true

## Public method to reseed floor (e.g., after collecting all)
func reseed():
	seed_floor()

## Debug helper to visualize floor area
func _draw():
	if Engine.is_editor_hint() and not use_fixed_points:
		# Draw floor line
		var line_start = Vector2(floor_min_x, floor_y)
		var line_end = Vector2(floor_max_x, floor_y)
		
		# Gold color for valuable collectibles
		draw_line(line_start, line_end, Color(1.0, 0.84, 0.0, 0.8), 3.0)
		
		# Draw spacing circles to show coverage
		var x = floor_min_x
		while x <= floor_max_x:
			draw_circle(Vector2(x, floor_y), placement_spacing / 2, Color(1.0, 0.84, 0.0, 0.1))
			x += placement_spacing
