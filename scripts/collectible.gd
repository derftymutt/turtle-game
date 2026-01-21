extends RigidBody2D
class_name Collectible

# Collectible properties
@export var point_value: int = 10
@export var point_value_valuable: int = 100
@export var sink_speed: float = 100.0

# Visual feedback
@export var bob_amount: float = 3.0
@export var bob_speed: float = 2.0

# Sway properties
@export var sway_amount: float = 30.0
@export var sway_speed: float = 1.5

# Despawn properties
@export var floor_despawn_time: float = 10.0

# Internal variables
var ocean: Ocean = null
var collected: bool = false
var despawning: bool = false
var bob_offset: float = 0.0
var sway_offset: float = 0.0
var visual_node: Node2D = null
var on_floor: bool = false
var floor_timer: float = 0.0
var is_valuable: bool = false

func _ready():
	# Physics setup for underwater object
	gravity_scale = 0.2
	linear_damp = 7.0
	angular_damp = 3.0
	
	# Collision setup - physics with world only
	collision_layer = 2
	collision_mask = 1
	
	# Find ocean system
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	
	# Random starting offsets for variety
	bob_offset = randf() * TAU
	sway_offset = randf() * TAU
	
	# Store visual node reference
	if has_node("Sprite2D"):
		visual_node = $Sprite2D
	elif has_node("AnimatedSprite2D"):
		visual_node = $AnimatedSprite2D
	
	# Connect Area2D for player detection
	if has_node("Area2D"):
		$Area2D.body_entered.connect(_on_area_2d_body_entered)
		$Area2D.collision_layer = 0
		$Area2D.collision_mask = 1
	else:
		push_warning("Collectible has no Area2D child!")

func _physics_process(delta):
	if collected or despawning:
		return
	
	# Check if settled on floor
	var is_near_floor = global_position.y > 160
	var is_mostly_still = linear_velocity.length() < 50
	
	if is_near_floor and is_mostly_still:
		if not on_floor:
			on_floor = true
			is_valuable = true
			floor_timer = 0.0
		
		floor_timer += delta
		
		# Despawn after timeout
		if floor_timer >= floor_despawn_time:
			despawning = true
			start_despawn()
			return
	else:
		on_floor = false
		floor_timer = 0.0
	
	# Apply sinking and swaying forces
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0 and depth < 160:
			# Sink downward
			apply_central_force(Vector2(0, sink_speed))
			
			# Sway left/right
			sway_offset += sway_speed * delta
			var sway_force = sin(sway_offset) * sway_amount
			apply_central_force(Vector2(sway_force, 0))
	
	# Visual bobbing animation
	bob_offset += bob_speed * delta
	if visual_node:
		visual_node.position.y = sin(bob_offset) * bob_amount
		
	if is_valuable:
		var animated_sprite = $AnimatedSprite2D
		if animated_sprite and animated_sprite.animation != "valuable":
			animated_sprite.play("valuable")
		point_value = point_value_valuable
		

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not collected:
		collect(body)

func collect(collector):
	if collected:
		return
	
	collected = true
	freeze = true
	
	# Award score through player
	if collector.has_method("add_score"):
		collector.add_score(point_value)
	
	# Tween to turtle with satisfying animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(func():
		print("Collected! +", point_value, " points")
		queue_free()
	)

func start_despawn():
	collected = true
	freeze = true
	
	# Beautiful fade out effect
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade to transparent
	tween.tween_property(self, "modulate:a", 0.0, 1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Sink into the ocean floor
	tween.tween_property(self, "global_position:y", global_position.y + 30, 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Shrink slightly
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Delete when finished
	tween.finished.connect(queue_free)
