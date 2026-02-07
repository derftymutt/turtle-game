extends Node
class_name CrabSpawner

@export var crab_scene: PackedScene

@export_group("Spawn Area")
@export var floor_y: float = 165.0
@export var spawn_area_min_x: float = -280.0
@export var spawn_area_max_x: float = 280.0

@export_group("Initial Population")
@export var initial_crab_count: int = 1

func _ready() -> void:
	# Validation check
	if not crab_scene:
		push_error("CrabSpawner: crab_scene not assigned!")
		return
	
	# Wait for scene to initialize
	await get_tree().create_timer(0.1).timeout
	
	# Spawn initial crabs
	for i in initial_crab_count:
		spawn_crab()

func spawn_crab(at_position: Vector2 = Vector2.ZERO) -> Crab:
	"""Spawn a new crab at the specified position, or random if Vector2.ZERO"""
	var crab = crab_scene.instantiate() as Crab
	
	if not crab:
		push_error("CrabSpawner: Failed to instantiate crab scene!")
		return null
	
	get_parent().add_child(crab)
	
	# Set position
	if at_position == Vector2.ZERO:
		# Random position
		crab.global_position = Vector2(
			randf_range(spawn_area_min_x, spawn_area_max_x),
			floor_y
		)
	else:
		# Specific position (for reproduction)
		crab.global_position = at_position
	
	# Connect to reproduction signal
	crab.ready_to_reproduce.connect(_on_crab_ready_to_reproduce)
	
	return crab

func _on_crab_ready_to_reproduce(parent_crab: Crab):
	"""Handle crab reproduction via signal"""
	if not parent_crab or not is_instance_valid(parent_crab):
		return
	
	# Spawn baby crab at parent's location
	var baby_crab = spawn_crab(parent_crab.global_position)
	
	if baby_crab:
		# Tell baby to relocate away from parent
		baby_crab.relocate_from_parent()
		print("🦀 Crab reproduced! Baby crab relocating...")
