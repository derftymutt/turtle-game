extends Node2D

## Main scene script
## Spawning is now handled by dedicated spawner nodes:
## - CollectibleSpawner for stars/coins
## - AirBubbleSpawner for breath bubbles
## - PiranhaSpawner (or EnemySpawner) for enemies

func _ready() -> void:
	await get_tree().create_timer(2.0).timeout
	test_collectible_spawn()

func test_collectible_spawn():
	var test_collectible = $FloorSeeder.collectible_scene.instantiate()
	add_child(test_collectible)
	test_collectible.global_position = Vector2(0, 165)
	test_collectible.z_index = 100
	test_collectible.modulate = Color.RED  # Make it red for visibility
	print("TEST: Spawned red collectible at (0, 165)")

func _process(_delta: float) -> void:
	# Main game loop logic
	pass
