extends RigidBody2D
class_name TrashItem

## Individual piece of trash that floats through the scene
## Can be shot by player to contribute to sequence completion
## Does NOT collide with game elements - purely visual/shootable

signal trash_destroyed(trash_item)

# Score
@export var points: int = 5

# Movement properties
@export var drift_speed: Vector2 = Vector2(-80, 0)  # Default: drift left
@export var rotation_speed: float = 0.5  # Tumbling effect

# Wave motion (Gradius-style undulation)
@export_group("Wave Motion")
@export var use_wave_motion: bool = false
@export var wave_amplitude: float = 30.0  # Height of wave (reduced for gentler motion)
@export var wave_frequency: float = 1.0  # How many waves across screen
@export var wave_speed: float = 1.0  # Not used in position-based wave

# Visual feedback
@export var bob_amount: float = 3.0
@export var bob_speed: float = 2.0
@export var flash_duration: float = 0.15

# Lifetime
@export var max_lifetime: float = 15.0  # Despawn if not shot

# Internal state
var bob_offset: float = 0.0
var age: float = 0.0
var is_destroyed: bool = false
var visual_node: Node2D = null
var sequence_id: int = -1  # Which sequence does this belong to?

# Wave motion state
var wave_offset: float = 0.0  # Current position in wave cycle
var base_y: float = 0.0  # Starting Y position

# HUD reference
var hud: HUD = null

func _ready():
	# Physics setup - ghost-like, passes through everything
	gravity_scale = 0.0
	linear_damp = 0.5
	angular_damp = 1.0
	mass = 0.5
	
	# CRITICAL: Collision setup for "ghost" behavior
	# NOTE: Set in Inspector:
	# - Collision Layer: 8 (trash layer - doesn't collide with world)
	# - Collision Mask: 4 (bullets only)
	# This allows bullets to hit trash, but trash passes through walls/enemies/player
	
	# Z-index for visual layering (can be set per-instance)
	z_index = 50  # Above ocean, below UI
	
	add_to_group("trash_items")
	
	# Random starting offsets
	bob_offset = randf() * TAU
	
	# Store starting Y position for wave motion (will be center of wave path)
	base_y = global_position.y
	
	# Store visual node reference
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")
	
	# Connect Area2D for bullet detection
	# NOTE: Area2D collision MUST be set in Inspector:
	# - Collision Layer: 0 (nothing)
	# - Collision Mask: 4 (bullets)
	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("TrashItem: No Area2D child found! Cannot detect bullets.")
	
	# Apply initial drift velocity
	linear_velocity = drift_speed
	
	hud = get_tree().get_first_node_in_group("hud")

func _physics_process(delta):
	if is_destroyed:
		return
	
	# Track lifetime
	age += delta
	if age >= max_lifetime:
		despawn_quietly()
		return
	
	# Maintain horizontal drift speed
	linear_velocity.x = drift_speed.x
	
	# Apply wave motion if enabled
	if use_wave_motion:
		# Calculate Y position based on CURRENT X position
		# This makes all trash follow the same sine wave path
		var wave_progress = global_position.x / 100.0  # Adjust divisor to control wave "stretch"
		var wave_y = sin(wave_progress * wave_frequency) * wave_amplitude
		
		# Set Y position relative to base position
		global_position.y = base_y + wave_y
		
		# Calculate vertical velocity based on wave slope (derivative)
		# This ensures smooth physics along the curve
		var wave_slope = cos(wave_progress * wave_frequency) * wave_amplitude * wave_frequency / 100.0
		linear_velocity.y = wave_slope * drift_speed.x
	else:
		# No wave motion - maintain drift speed normally
		linear_velocity.y = drift_speed.y
	
	# Tumbling rotation
	angular_velocity = rotation_speed
	
	# Visual bobbing (separate from wave motion)
	bob_offset += bob_speed * delta
	if visual_node:
		visual_node.position.y = sin(bob_offset) * bob_amount

func _on_area_body_entered(body: Node2D):
	"""Detect bullet hits"""
	if is_destroyed:
		return
	
	# Check if it's a bullet (check by group or script)
	if body.is_in_group("bullets"):	
		add_score(points)	
		destroy_trash()
		return
	
	# Also check if body has bullet-like properties
	if body.has_method("set_velocity") and body.collision_layer == 4:
		add_score(points)
		destroy_trash()
		return

func destroy_trash():
	"""Called when successfully shot by player"""
	if is_destroyed:
		return
	
	is_destroyed = true
	freeze = true
	
	# Emit signal to notify sequence manager
	trash_destroyed.emit(self)
	
	# Satisfying destruction effect
	play_destruction_effect()

func play_destruction_effect():
	"""Visual feedback for successful trash cleanup"""
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Flash bright
	if visual_node:
		tween.tween_property(visual_node, "modulate", Color.WHITE * 2.0, 0.1)
	
	# Expand and spin
	tween.tween_property(self, "scale", Vector2.ONE * 1.5, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + TAU, 0.2)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(0.1)
	
	tween.finished.connect(queue_free)

func despawn_quietly():
	"""Remove trash that wasn't shot (timeout)"""
	if is_destroyed:
		return
	
	is_destroyed = true
	
	# Gentle fade
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.finished.connect(queue_free)

## Set which sequence this trash belongs to
func set_sequence_id(id: int):
	sequence_id = id

func add_score(points: int):
	if hud:
		hud.add_score(points)
	
