extends Node2D
class_name HealthPlant

## Health-restoring plant that grows on DeadWall surfaces
## Spawns at point thresholds and attaches to walls

# Health properties
@export var health_restore_amount: float = 30.0
@export var max_health_bonus: float = 0.0  # Optional max health increase

# Visual feedback
@export var pulse_amount: float = 0.15  # Scale pulsing
@export var pulse_speed: float = 1.5
@export var glow_intensity: float = 0.08  # Green glow effect

# Wall attachment
@export var wall_offset: float = 8.0  # Distance from wall surface
@export var attach_to_wall: bool = true

# Despawn properties
@export var lifetime: float = 20.0  # Despawn after this long if not collected
@export var warning_time: float = 5.0  # Start flashing this many seconds before despawn

# Internal state
var collected: bool = false
var despawning: bool = false
var age: float = 0.0
var pulse_offset: float = 0.0
var visual_node: Node2D = null
var attached_wall: Node2D = null

func _ready():
	add_to_group("health_plants")
	
	# Random starting pulse offset
	pulse_offset = randf() * TAU
	
	# Find visual node (Sprite2D or AnimatedSprite2D)
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")
	
	# Connect Area2D for player detection (must be set up in scene Inspector)
	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_collection_area_entered)
	else:
		push_warning("HealthPlant: No Area2D child found! Add one in the scene with collision layer 0, mask 1")
	
	print("🌿 Health plant spawned at ", global_position)

func _process(delta):
	if collected or despawning:
		return
	
	# Track age
	age += delta
	
	# Check for despawn
	if age >= lifetime:
		despawning = true
		start_despawn()
		return
	
	# Visual effects
	animate_plant(delta)
	
	# Warning flash when near despawn
	if age >= (lifetime - warning_time):
		flash_warning(delta)

func animate_plant(delta: float):
	"""Create gentle pulsing/breathing effect"""
	if not visual_node:
		return
	
	# Pulsing scale
	pulse_offset += pulse_speed * delta
	var pulse_scale = 1.0 + (sin(pulse_offset) * pulse_amount)
	visual_node.scale = Vector2(pulse_scale, pulse_scale)
	
	# Green glow effect
	var glow = 1.0 + (sin(pulse_offset) * glow_intensity)
	visual_node.modulate = Color(glow * 0.8, glow * 1.2, glow * 0.8, 1.0)

func flash_warning(delta: float):
	"""Flash to warn player it's about to despawn"""
	var flash_speed = 8.0
	var flash = abs(sin(age * flash_speed))
	
	if visual_node:
		visual_node.modulate.a = 0.4 + (flash * 0.6)

func _on_collection_area_entered(body: Node2D):
	if body.is_in_group("player") and not collected:
		collect(body)

func collect(collector):
	"""Restore health and apply bonuses"""
	if collected:
		return
	
	collected = true
	
	# Restore health through player
	if collector.has_method("restore_health"):
		collector.restore_health(health_restore_amount)
	elif collector.has_method("take_damage"):
		# Fallback: directly modify health
		collector.current_health = min(
			collector.max_health, 
			collector.current_health + health_restore_amount
		)
		
		# Update HUD
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.update_health(collector.current_health, collector.max_health)
	
	# Optional: increase max health permanently
	if max_health_bonus > 0 and collector.has_method("increase_max_health"):
		collector.increase_max_health(max_health_bonus)
	
	print("🌿 Health plant collected! Health restored: +", health_restore_amount)
	
	# Satisfying collection animation
	play_collect_animation()

func play_collect_animation():
	"""Beautiful collection effect"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Scale up and fade
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.tween_property(self, "modulate:a", 0.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Slight float upward
	tween.tween_property(self, "position:y", position.y - 20, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	tween.finished.connect(queue_free)

func start_despawn():
	"""Gentle fade when lifetime expires"""
	collected = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(self, "modulate:a", 0.0, 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)
	
	print("🌿 Health plant despawned (not collected)")

## Attach plant to a wall surface
func attach_to_wall_surface(wall: Node2D, spawn_position: Vector2, wall_normal: Vector2):
	"""Position plant on wall surface with proper offset and rotation"""
	attached_wall = wall
	
	# Position at wall surface with offset
	global_position = spawn_position + (wall_normal * wall_offset)
	
	# Rotate to face away from wall (normal direction)
	rotation = wall_normal.angle() - deg_to_rad(-90)
	
	print("🌿 Plant attached to wall at ", global_position, " with normal ", wall_normal)
