extends Node2D

@export var collectible_scene: PackedScene


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(spawn_star_wave)
	timer.wait_time = 5.0  # Every 5 seconds
	timer.start()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
# Spawn function
func spawn_collectible(pos: Vector2):
	if collectible_scene == null:
		push_warning("No collectible scene assigned!")
		return
	
	var collectible = collectible_scene.instantiate()
	add_child(collectible)
	collectible.global_position = pos  # This should work but let's verify
	
	print("Spawned collectible at intended pos: ", pos, " actual global_pos: ", collectible.global_position)

# Spawn at random positions
func spawn_random_stars(count: int):
	for i in count:
		var random_x = randf_range(-280, 280)  # Within screen width
		var random_y = randf_range(-100, -50)  # Start above water
		spawn_collectible(Vector2(random_x, random_y))


func spawn_star_wave():
	spawn_random_stars(2)  
