extends Node

@export var crab_scene: PackedScene
@export var spawn_area_min: Vector2 = Vector2(-280, 160)
@export var spawn_area_max: Vector2 = Vector2(280, 160)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Validation check
	if not crab_scene:
		push_error("CrabSpawner: crab_scene not assigned!")

	await get_tree().create_timer(0.1).timeout

	_spawn_crab()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var crabs = get_tree().get_nodes_in_group("crabs")
	
	for crab in crabs:
		if crab.markForReproduction == true and crab.hasReproduced == false:
			_reproduce_crab(crab)
			crab.markForReproduction = false
			crab.hasReproduced = true
	
	
func _spawn_crab():
	var pos = Vector2(
		randf_range(spawn_area_min.x, spawn_area_max.x),
		randf_range(spawn_area_min.y, spawn_area_max.y)
	)
	
	var crab = crab_scene.instantiate()
	get_parent().add_child(crab)
	crab.global_position = pos
	
func _reproduce_crab(crabParent: Crab):
	var crab = crab_scene.instantiate()
	get_parent().add_child(crab)
	crab.global_position = crabParent.global_position
	# TODO: make this work (I think!)
	#crab.current_state = Crab.State.RELOCATING
