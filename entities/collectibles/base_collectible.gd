# base_collectible.gd
extends RigidBody2D
class_name BaseCollectible

## Base class for all collectibles (stars, UFO pieces, etc.)

@export var point_value: int = 10
@export var can_be_collected: bool = true

# Physics properties
@export var sink_speed: float = 100.0
@export var bob_amount: float = 3.0
@export var bob_speed: float = 2.0
@export var sway_amount: float = 30.0
@export var sway_speed: float = 1.5

# Internal variables
var ocean: Ocean = null
var collected: bool = false
var bob_offset: float = 0.0
var sway_offset: float = 0.0
var visual_node: Node2D = null

func _ready():
	# Physics setup
	gravity_scale = 0.2
	linear_damp = 7.0
	angular_damp = 3.0
	
	collision_layer = 2
	collision_mask = 1
	
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	
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
		push_warning("%s has no Area2D child!" % name)
	
	# Call child class setup
	_collectible_ready()

func _collectible_ready():
	"""Override in child classes for custom initialization"""
	pass

func _physics_process(delta):
	# Only run physics if not collected (but allow child classes to override)
	if collected:
		return
	
	# Call child class physics
	_collectible_physics_process(delta)
	
	# Visual bobbing animation (always runs unless child disables)
	bob_offset += bob_speed * delta
	if visual_node:
		visual_node.position.y = sin(bob_offset) * bob_amount

func _collectible_physics_process(_delta: float):
	"""Override in child classes for custom physics behavior"""
	pass

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not collected and can_be_collected:
		collect(body)

func collect(collector):
	"""Main collection entry point"""
	if collected:
		return
	
	collected = true
	freeze = true
	
	# Call child implementation
	_on_collected(collector)

func _on_collected(_collector):
	"""Override in child classes - this is where the magic happens"""
	pass
