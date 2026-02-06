extends RigidBody2D
class_name Powerup

## Powerup that spawns when trash sequence is completed
## Sinks gradually to ocean floor, can be collected by player

signal powerup_collected(powerup_type)

# Powerup type enum
enum PowerupType {
	SHIELD,          # Temporary invincibility
	AIR_RESERVE,     # Extra breath capacity
	STAMINA_FREEZE,  # Pause stamina drain
	# Future powerups can be added here
	# SPEED_BOOST,
	# RAPID_FIRE,
	# MAGNET,
}

# Properties
@export var powerup_type: PowerupType = PowerupType.SHIELD
@export var sink_speed: float = 60.0
@export var sway_amount: float = 20.0
@export var sway_speed: float = 1.2

# Visual feedback
@export var glow_amount: float = 0.3  # Brightness pulsing
@export var glow_speed: float = 2.0
@export var rotation_speed: float = 1.5  # Gentle spin

# Lifetime
@export var floor_lifetime: float = 12.0  # How long it stays on floor before despawning
@export var disable_floor_despawn: bool = false

# Internal state
var ocean: Ocean = null
var collected: bool = false
var despawning: bool = false
var glow_offset: float = 0.0
var sway_offset: float = 0.0
var visual_node: Node2D = null
var on_floor: bool = false
var floor_timer: float = 0.0

func _ready():
	# Physics setup - sinks like valuable collectibles
	gravity_scale = 0.2
	linear_damp = 5.0
	angular_damp = 3.0
	mass = 0.5
	
	# Collision setup
	# NOTE: Set in Inspector:
	# - Collision Layer: 2 (collectibles)
	# - Collision Mask: 1 (world)
	
	# High z-index for visibility
	z_index = 100
	
	# Find ocean system
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	add_to_group("powerups")
	
	# Random starting offsets
	glow_offset = randf() * TAU
	sway_offset = randf() * TAU
	
	# Store visual node
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")
	
	# Connect Area2D for player detection
	# NOTE: Area2D collision MUST be set in Inspector:
	# - Collision Layer: 0 (nothing)
	# - Collision Mask: 1 (player)
	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("Powerup: No Area2D child found!")

func _physics_process(delta):
	if collected or despawning:
		return
	
	# Check if on floor
	var is_near_floor = global_position.y > 160
	var is_mostly_still = linear_velocity.length() < 50
	
	if is_near_floor and is_mostly_still:
		if not on_floor:
			on_floor = true
			floor_timer = 0.0
		
		if not disable_floor_despawn:
			floor_timer += delta
			if floor_timer >= floor_lifetime:
				despawning = true
				start_despawn()
				return
	else:
		on_floor = false
		floor_timer = 0.0
	
	# Apply sinking and swaying
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0 and depth < 160:
			# Sink downward
			apply_central_force(Vector2(0, sink_speed))
			
			# Sway side to side
			sway_offset += sway_speed * delta
			var sway_force = sin(sway_offset) * sway_amount
			apply_central_force(Vector2(sway_force, 0))
	
	# Visual effects
	animate_powerup(delta)

func animate_powerup(delta: float):
	"""Create attractive glowing/spinning effect"""
	if not visual_node:
		return
	
	# Pulsing glow
	glow_offset += glow_speed * delta
	var glow = 1.0 + (sin(glow_offset) * glow_amount)
	visual_node.modulate = Color(glow, glow, glow, 1.0)
	
	# Gentle rotation
	rotation += rotation_speed * delta

func _on_area_body_entered(body: Node2D):
	if body.is_in_group("player") and not collected:
		collect(body)

func collect(collector):
	"""Collect powerup and apply effect to player"""
	if collected:
		return
	
	collected = true
	freeze = true
	
	# GIANT FLASH for visibility
	print("💥💥💥 POWERUP COLLECTED: ", PowerupType.keys()[powerup_type], " 💥💥💥")
	
	# Emit signal with powerup type
	powerup_collected.emit(powerup_type)
	
	# Apply powerup effect to player
	if collector.has_method("apply_powerup"):
		collector.apply_powerup(powerup_type)
	else:
		push_error("⚠️ Player doesn't have apply_powerup method! Powerup NOT applied!")
	
	# SUPER OBVIOUS collection animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Zoom to player FAST
	tween.tween_property(self, "global_position", collector.global_position, 0.15)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	# MEGA BRIGHT flash (5x brightness!)
	if visual_node:
		visual_node.modulate = Color.WHITE * 5.0
		tween.tween_property(visual_node, "modulate", Color.WHITE * 10.0, 0.1)
	
	# Explode scale up then down
	tween.tween_property(self, "scale", Vector2.ONE * 3.0, 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2).set_delay(0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)

func start_despawn():
	"""Despawn powerup after timeout"""
	collected = true
	freeze = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Sink into floor
	tween.tween_property(self, "global_position:y", global_position.y + 30, 1.5)
	
	# Shrink
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), 1.5)
	
	tween.finished.connect(queue_free)

## Get powerup type name for display
func get_powerup_name() -> String:
	match powerup_type:
		PowerupType.SHIELD:
			return "Shield"
		PowerupType.AIR_RESERVE:
			return "Air Reserve"
		PowerupType.STAMINA_FREEZE:
			return "Stamina Freeze"
		_:
			return "Unknown"
