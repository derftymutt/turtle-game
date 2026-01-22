extends RigidBody2D
class_name AirBubble

## Air bubble collectible that floats upward and restores breath
## Integrates with existing HUD breath system

# Bubble properties
@export var breath_restore_amount: float = 20.0  # Full restore by default (matches HUD max_breath)
@export var rise_speed: float = 80.0  # Upward force
@export var wobble_amount: float = 20.0  # Side-to-side wobble
@export var wobble_speed: float = 2.0

# Visual feedback
@export var bob_amount: float = 2.0
@export var bob_speed: float = 3.0
@export var pulse_amount: float = 0.15  # Scale pulsing (0.85 to 1.15)
@export var pulse_speed: float = 2.5

# Despawn properties
@export var surface_despawn_time: float = 8.0  # Despawn after reaching surface
@export var lifetime: float = 15.0  # Max lifetime regardless of position

# Internal variables
var ocean: Ocean = null
var collected: bool = false
var despawning: bool = false
var bob_offset: float = 0.0
var wobble_offset: float = 0.0
var pulse_offset: float = 0.0
var visual_node: Node2D = null
var at_surface: bool = false
var surface_timer: float = 0.0
var age: float = 0.0

func _ready():
	# Physics setup for rising bubble
	gravity_scale = 0.0  # No gravity
	linear_damp = 5.0  # More drag than regular collectibles
	angular_damp = 3.0
	
	# Collision setup - physics with world only
	# NOTE: Set in Inspector:
	# - Collision Layer: 2 (collectibles)
	# - Collision Mask: 1 (world)
	
	# Find ocean system
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	add_to_group("air_bubbles")
	
	# Random starting offsets for variety
	bob_offset = randf() * TAU
	wobble_offset = randf() * TAU
	pulse_offset = randf() * TAU
	
	# Store visual node reference
	if has_node("Sprite2D"):
		visual_node = $Sprite2D
	elif has_node("AnimatedSprite2D"):
		visual_node = $AnimatedSprite2D
	
	# Connect Area2D for player detection
	if has_node("Area2D"):
		$Area2D.body_entered.connect(_on_area_2d_body_entered)
		$Area2D.collision_layer = 0
		$Area2D.collision_mask = 1  # Detect player only
	else:
		push_warning("AirBubble has no Area2D child!")

func _physics_process(delta):
	if collected or despawning:
		return
	
	# Track age for maximum lifetime
	age += delta
	if age >= lifetime:
		despawning = true
		start_despawn()
		return
	
	# Check if at surface
	if ocean:
		var depth = ocean.get_depth(global_position)
		
		if depth <= 0:  # At or above surface
			if not at_surface:
				at_surface = true
				surface_timer = 0.0
			
			surface_timer += delta
			
			# Pop at surface after timeout
			if surface_timer >= surface_despawn_time:
				despawning = true
				pop_at_surface()
				return
		else:
			at_surface = false
			surface_timer = 0.0
		
		# Apply rising force (opposite of sinking collectibles)
		if depth > 0:
			apply_central_force(Vector2(0, -rise_speed))
			
			# Wobble side to side as it rises
			wobble_offset += wobble_speed * delta
			var wobble_force = sin(wobble_offset) * wobble_amount
			apply_central_force(Vector2(wobble_force, 0))
	
	# Visual animations
	animate_bubble(delta)

func animate_bubble(delta: float):
	"""Create bubble-like visual effects"""
	if not visual_node:
		return
	
	# Bobbing (small vertical oscillation)
	bob_offset += bob_speed * delta
	visual_node.position.y = sin(bob_offset) * bob_amount
	
	# Pulsing scale (breathe in and out)
	pulse_offset += pulse_speed * delta
	var pulse_scale = 1.0 + (sin(pulse_offset) * pulse_amount)
	visual_node.scale = Vector2(pulse_scale, pulse_scale)

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not collected:
		collect(body)

func collect(collector):
	"""Collect bubble and restore breath via HUD"""
	if collected:
		return
	
	collected = true
	freeze = true
	
	# Find HUD and restore breath
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("refill_breath_instant"):
		# Use instant refill method if available
		hud.refill_breath_instant(breath_restore_amount)
		print("💨 Air bubble collected! Breath restored: +", breath_restore_amount)
	elif hud:
		# Fallback: directly set breath (works with current HUD)
		var new_breath = min(hud.max_breath, hud.current_breath + breath_restore_amount)
		hud.update_breath(new_breath, hud.max_breath)
		hud.current_breath = new_breath
		print("💨 Air bubble collected! Breath restored: +", breath_restore_amount)
	else:
		push_warning("No HUD found! Cannot restore breath.")
	
	# Satisfying collection animation - bubble pops!
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Scale up quickly then disappear (pop effect)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.15)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)

func pop_at_surface():
	"""Bubble pops when it reaches the surface"""
	collected = true
	freeze = true
	
	# Pop effect - quick expand and fade
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Expand dramatically
	tween.tween_property(self, "scale", Vector2(2.0, 2.0), 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Fade to transparent
	tween.tween_property(self, "modulate:a", 0.0, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)
	
## Pop when hit by bullet
func pop_from_bullet():
	#"""Called when shot by a bullet - immediate pop without breath restore"""
	if collected or despawning:
		return
	
	collected = true
	despawning = true
	freeze = true
	
	# Same satisfying pop animation as surface pop
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Expand dramatically
	tween.tween_property(self, "scale", Vector2(2.0, 2.0), 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Fade to transparent
	tween.tween_property(self, "modulate:a", 0.0, 0.2)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)

func start_despawn():
	"""Gentle fade for lifetime expiration"""
	collected = true
	freeze = true
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(queue_free)
