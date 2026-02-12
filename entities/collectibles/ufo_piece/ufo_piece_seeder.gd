# ufo_piece_seeder.gd
extends Node2D
class_name UFOPieceSeeder

## Seeds the ocean floor with UFO pieces at level start
## Pieces must be delivered to workshop to count toward level completion

@export var ufo_piece_scene: PackedScene

@export_group("Seeding Settings")
@export var seed_on_ready: bool = true
@export var use_level_manager_count: bool = true  # Auto-use LevelManager's piece requirement
@export var seed_count_min: int = 3  # Used if use_level_manager_count = false
@export var seed_count_max: int = 5  # Used if use_level_manager_count = false

@export_group("Floor Position")
@export var use_fixed_points: bool = false
@export var floor_y: float = 165.0

@export_group("Random Floor Area")
@export var floor_min_x: float = -280.0
@export var floor_max_x: float = 280.0
@export var placement_spacing: float = 80.0

@export_group("Spawn Points")
@export var spawn_point_paths: Array[NodePath] = []

var spawn_points: Array[Node2D] = []
var placed_positions: Array[Vector2] = []

func _ready():
	if use_fixed_points:
		for path in spawn_point_paths:
			var node = get_node_or_null(path)
			if node and node is Node2D:
				spawn_points.append(node)
		
		if spawn_points.is_empty():
			push_warning("UFOPieceSeeder: No valid spawn points! Falling back to random.")
			use_fixed_points = false
	
	if seed_on_ready:
		await get_tree().create_timer(0.1).timeout
		seed_floor()

func seed_floor():
	"""Seed ocean floor with UFO pieces"""
	if not ufo_piece_scene:
		push_error("UFOPieceSeeder: No UFO piece scene assigned!")
		return
	
	# Determine how many pieces to spawn
	var count: int
	if use_level_manager_count:
		# Use LevelManager's requirement (for proper level progression)
		count = LevelManager.pieces_needed
		print("🔧 Using LevelManager count: %d pieces" % count)
	else:
		# Use manual min/max (for testing or special levels)
		count = randi_range(seed_count_min, seed_count_max)
		print("🔧 Using manual count: %d pieces (range: %d-%d)" % [count, seed_count_min, seed_count_max])
	
	placed_positions.clear()
	
	print("🔧 Seeding ocean floor with %d UFO pieces..." % count)
	
	for i in count:
		spawn_ufo_piece()
	
	print("✓ UFO piece seeding complete!")

func spawn_ufo_piece():
	"""Spawn a single UFO piece on the floor"""
	if not ufo_piece_scene:
		return
	
	var piece = ufo_piece_scene.instantiate()
	get_parent().add_child(piece)
	
	# Determine spawn position
	var spawn_pos: Vector2
	if use_fixed_points and not spawn_points.is_empty():
		var point = spawn_points.pick_random()
		spawn_pos = point.global_position
	else:
		spawn_pos = get_spaced_floor_position()
	
	piece.global_position = spawn_pos
	piece.z_index = 100
	
	# Make stationary on floor
	piece.freeze = false  # Allow physics initially
	piece.linear_velocity = Vector2.ZERO
	piece.angular_velocity = 0.0
	piece.linear_damp = 20.0
	piece.gravity_scale = 0.1  # Slight gravity to settle

func get_spaced_floor_position() -> Vector2:
	var max_attempts = 20
	var attempt = 0
	
	while attempt < max_attempts:
		var candidate = Vector2(
			randf_range(floor_min_x, floor_max_x),
			floor_y
		)
		
		if is_position_valid(candidate):
			placed_positions.append(candidate)
			return candidate
		
		attempt += 1
	
	var fallback = Vector2(randf_range(floor_min_x, floor_max_x), floor_y)
	placed_positions.append(fallback)
	return fallback

func is_position_valid(pos: Vector2) -> bool:
	for placed_pos in placed_positions:
		if pos.distance_to(placed_pos) < placement_spacing:
			return false
	return true

## Public method to reseed floor
func reseed():
	seed_floor()

## Debug helper to visualize floor area
func _draw():
	if Engine.is_editor_hint() and not use_fixed_points:
		var line_start = Vector2(floor_min_x, floor_y)
		var line_end = Vector2(floor_max_x, floor_y)
		
		# Orange color for UFO pieces
		draw_line(line_start, line_end, Color(1.0, 0.5, 0.0, 0.8), 3.0)
		
		# Draw spacing circles
		var x = floor_min_x
		while x <= floor_max_x:
			draw_circle(Vector2(x, floor_y), placement_spacing / 2, Color(1.0, 0.5, 0.0, 0.1))
			x += placement_spacing
