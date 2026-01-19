extends Node2D

@export var piranha_scene: PackedScene
@export var spawn_interval: float = 5.0
@export var spawn_area_min: Vector2 = Vector2(-250, 40)
@export var spawn_area_max: Vector2 = Vector2(250, 140)

func _ready():
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(spawn_with_animation)
	timer.wait_time = spawn_interval
	timer.start()

func spawn_with_animation():
	var pos = Vector2(
		randf_range(spawn_area_min.x, spawn_area_max.x),
		randf_range(spawn_area_min.y, spawn_area_max.y)
	)
	
	# === PHASE 1: Warning circles (ripples) ===
	for i in range(3):
		await get_tree().create_timer(0.2 * i).timeout
		create_warning_ripple(pos, i)
	
	# === PHASE 2: Piranha silhouette grows ===
	await get_tree().create_timer(0.4).timeout
	
	if not piranha_scene:
		return
	
	# Create a temporary sprite that looks like the piranha
	var approach_sprite = Sprite2D.new()
	
	# Get piranha's sprite to copy it
	var temp_piranha = piranha_scene.instantiate()
	var piranha_sprite = temp_piranha.get_node_or_null("AnimatedSprite2D")
	if not piranha_sprite:
		piranha_sprite = temp_piranha.get_node_or_null("Sprite2D")
	
	if piranha_sprite:
		if piranha_sprite is AnimatedSprite2D:
			approach_sprite.texture = piranha_sprite.sprite_frames.get_frame_texture("default", 0)
		else:
			approach_sprite.texture = piranha_sprite.texture
	
	temp_piranha.queue_free()
	
	# Set up approach sprite
	get_parent().add_child(approach_sprite)
	approach_sprite.global_position = pos
	approach_sprite.scale = Vector2(0.1, 0.1)  # Start tiny
	approach_sprite.modulate = Color(0.2, 0.2, 0.3, 0.5)  # Dark, semi-transparent
	approach_sprite.rotation = randf_range(-0.3, 0.3)
	
	# Animate: scale up + fade in + slight rotation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(approach_sprite, "scale", Vector2(1.2, 1.2), 0.6)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(approach_sprite, "modulate", Color(1, 1, 1, 1), 0.6)
	tween.tween_property(approach_sprite, "rotation", 0.0, 0.6)
	
	await tween.finished
	
	# === PHASE 3: Pop effect and spawn real piranha ===
	# Quick scale burst
	var pop_tween = create_tween()
	pop_tween.tween_property(approach_sprite, "scale", Vector2(1.3, 1.3), 0.1)
	await pop_tween.finished
	
	# Spawn real piranha
	var piranha = piranha_scene.instantiate()
	get_parent().add_child(piranha)
	piranha.global_position = pos
	
	# Clean up approach sprite
	approach_sprite.queue_free()

func create_warning_ripple(pos: Vector2, delay_index: int):
	"""Create an expanding circle ripple effect"""
	var ripple = Node2D.new()
	get_parent().add_child(ripple)
	ripple.global_position = pos
	
	# Draw a circle using a simple colored square (you can replace with actual circle texture)
	var circle = ColorRect.new()
	circle.color = Color(1, 0.3, 0.3, 0.7)  # Red warning color
	circle.size = Vector2(10, 10)
	circle.position = Vector2(-5, -5)  # Center it
	ripple.add_child(circle)
	
	# Animate: expand and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(circle, "size", Vector2(60, 60), 1.0)
	tween.tween_property(circle, "position", Vector2(-30, -30), 1.0)
	tween.tween_property(circle, "color:a", 0.0, 1.0)
	
	tween.finished.connect(ripple.queue_free)
