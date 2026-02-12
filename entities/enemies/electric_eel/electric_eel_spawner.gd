extends Node2D
class_name EelSpawner

## Spawns electric eels with visual warning effects
## Similar to piranha spawner but with electric-themed visuals

@export var eel_scene: PackedScene

@export_group("Spawn Settings")
@export var spawn_interval: float = 8.0  # Slower than piranhas - eels are more dangerous
@export var spawn_area_min: Vector2 = Vector2(-250, 60)  # Mid-depth spawning
@export var spawn_area_max: Vector2 = Vector2(250, 140)

@export_group("Visual Settings")
@export var warning_color: Color = Color(0.0, 1.0, 1.0, 0.7)  # Cyan electric color
@export var warning_ripple_count: int = 3
@export var warning_duration: float = 0.6

func _ready():
	# Validation
	if not eel_scene:
		push_error("EelSpawner: eel_scene not assigned!")
		return
	
	# Setup spawn timer
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(spawn_with_animation)
	timer.wait_time = spawn_interval
	timer.start()

func spawn_with_animation():
	"""Spawn an eel with electric warning animation"""
	var pos = Vector2(
		randf_range(spawn_area_min.x, spawn_area_max.x),
		randf_range(spawn_area_min.y, spawn_area_max.y)
	)
	
	# === PHASE 1: Electric ripples ===
	for i in range(warning_ripple_count):
		await get_tree().create_timer(0.2 * i).timeout
		_create_electric_ripple(pos, i)
	
	# === PHASE 2: Eel silhouette with electric crackling ===
	await get_tree().create_timer(0.4).timeout
	
	var approach_sprite = _create_approach_sprite()
	if not approach_sprite:
		return
	
	get_parent().add_child(approach_sprite)
	approach_sprite.global_position = pos
	approach_sprite.scale = Vector2(0.1, 0.1)
	approach_sprite.modulate = Color(0.0, 0.3, 0.3, 0.5)  # Cyan tint
	approach_sprite.rotation = randf_range(-0.3, 0.3)
	
	# Add crackling effect during approach
	_create_crackling_effect(approach_sprite)
	
	# Animate: scale up + fade in + slight rotation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(approach_sprite, "scale", Vector2(1.2, 1.2), warning_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(approach_sprite, "modulate", Color(0.5, 1.5, 1.5, 1.0), warning_duration)
	tween.tween_property(approach_sprite, "rotation", 0.0, warning_duration)
	
	await tween.finished
	
	# === PHASE 3: Electric flash and spawn real eel ===
	var flash = _create_electric_flash(pos)
	
	var pop_tween = create_tween()
	pop_tween.tween_property(approach_sprite, "scale", Vector2(1.4, 1.4), 0.1)
	await pop_tween.finished
	
	# Spawn real eel
	var eel = eel_scene.instantiate()
	get_parent().add_child(eel)
	eel.global_position = pos
	
	# Cleanup
	approach_sprite.queue_free()
	if flash:
		flash.queue_free()

func _create_electric_ripple(pos: Vector2, delay_index: int):
	"""Create an expanding electric ripple effect"""
	var ripple = Node2D.new()
	get_parent().add_child(ripple)
	ripple.global_position = pos
	ripple.z_index = 50
	
	# Create ripple visual - use Line2D for zigzag electric effect
	var circle_points = 16
	var radius = 8.0
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = warning_color
	
	# Create zigzag circle
	for i in range(circle_points + 1):
		var angle = (i / float(circle_points)) * TAU
		var point_radius = radius + randf_range(-2, 2)  # Add jitter for electric effect
		var point = Vector2(cos(angle), sin(angle)) * point_radius
		line.add_point(point)
	
	ripple.add_child(line)
	
	# Animate: expand and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Expand ripple
	var target_scale = 1.0 + (delay_index * 0.5)
	tween.tween_property(ripple, "scale", Vector2(target_scale * 8, target_scale * 8), 1.0)
	
	# Fade out
	tween.tween_property(line, "default_color:a", 0.0, 1.0)
	
	tween.finished.connect(ripple.queue_free)

func _create_approach_sprite() -> Sprite2D:
	"""Create the approaching eel silhouette sprite"""
	if not eel_scene:
		return null
	
	# Instantiate temporary eel to get its sprite
	var temp_eel = eel_scene.instantiate()
	var eel_sprite = temp_eel.get_node_or_null("AnimatedSprite2D")
	if not eel_sprite:
		eel_sprite = temp_eel.get_node_or_null("Sprite2D")
	
	var approach_sprite = Sprite2D.new()
	
	if eel_sprite:
		if eel_sprite is AnimatedSprite2D:
			approach_sprite.texture = eel_sprite.sprite_frames.get_frame_texture("default", 0)
		else:
			approach_sprite.texture = eel_sprite.texture
	
	temp_eel.queue_free()
	return approach_sprite

func _create_crackling_effect(parent: Node2D):
	"""Add small electric sparks around the approaching sprite"""
	var spark_count = 4
	
	for i in range(spark_count):
		var spark_line = Line2D.new()
		spark_line.width = 1.0
		spark_line.default_color = warning_color
		spark_line.z_index = 1
		
		# Random position around parent
		var angle = (i / float(spark_count)) * TAU
		var offset = Vector2(cos(angle), sin(angle)) * 15
		
		spark_line.add_point(offset)
		spark_line.add_point(offset + Vector2(randf_range(-5, 5), randf_range(-5, 5)))
		
		parent.add_child(spark_line)
		
		# Animate sparks
		var tween = create_tween().set_loops()
		tween.tween_property(spark_line, "modulate:a", 0.0, 0.2)
		tween.tween_property(spark_line, "modulate:a", 1.0, 0.2)

func _create_electric_flash(pos: Vector2) -> Node2D:
	"""Create a bright electric flash effect"""
	var flash = Node2D.new()
	get_parent().add_child(flash)
	flash.global_position = pos
	flash.z_index = 100
	
	# Create expanding flash circles
	for i in range(3):
		var circle = ColorRect.new()
		circle.color = Color(0.0, 1.5, 1.5, 0.8)
		circle.size = Vector2(20 + i * 10, 20 + i * 10)
		circle.position = Vector2(-(10 + i * 5), -(10 + i * 5))
		flash.add_child(circle)
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(circle, "size", circle.size * 3, 0.3)
		tween.tween_property(circle, "position", circle.position - circle.size, 0.3)
		tween.tween_property(circle, "color:a", 0.0, 0.3)
	
	# Auto cleanup
	var cleanup_timer = get_tree().create_timer(0.4)
	cleanup_timer.timeout.connect(flash.queue_free)
	
	return flash

## Public method to manually trigger a spawn (for testing or events)
func spawn_eel_at_position(pos: Vector2):
	"""Spawn an eel at a specific position with full animation"""
	if not eel_scene:
		push_error("EelSpawner: Cannot spawn - eel_scene not assigned!")
		return
	
	# Use the same animation sequence
	_spawn_at_specific_position(pos)

func _spawn_at_specific_position(pos: Vector2):
	"""Internal method for spawning at a specific position"""
	# Phase 1: Electric ripples
	for i in range(warning_ripple_count):
		await get_tree().create_timer(0.2 * i).timeout
		_create_electric_ripple(pos, i)
	
	# Phase 2: Approach sprite
	await get_tree().create_timer(0.4).timeout
	
	var approach_sprite = _create_approach_sprite()
	if not approach_sprite:
		return
	
	get_parent().add_child(approach_sprite)
	approach_sprite.global_position = pos
	approach_sprite.scale = Vector2(0.1, 0.1)
	approach_sprite.modulate = Color(0.0, 0.3, 0.3, 0.5)
	approach_sprite.rotation = randf_range(-0.3, 0.3)
	
	_create_crackling_effect(approach_sprite)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(approach_sprite, "scale", Vector2(1.2, 1.2), warning_duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(approach_sprite, "modulate", Color(0.5, 1.5, 1.5, 1.0), warning_duration)
	tween.tween_property(approach_sprite, "rotation", 0.0, warning_duration)
	
	await tween.finished
	
	# Phase 3: Flash and spawn
	var flash = _create_electric_flash(pos)
	
	var pop_tween = create_tween()
	pop_tween.tween_property(approach_sprite, "scale", Vector2(1.4, 1.4), 0.1)
	await pop_tween.finished
	
	var eel = eel_scene.instantiate()
	get_parent().add_child(eel)
	eel.global_position = pos
	
	approach_sprite.queue_free()
	if flash:
		flash.queue_free()
