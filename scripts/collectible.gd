extends Area2D
class_name Collectible

# Collectible properties
@export var point_value: int = 10
@export var sink_speed: float = 50.0

# Visual feedback
@export var bob_amount: float = 3.0
@export var bob_speed: float = 2.0

# Internal variables
var ocean: Ocean = null
var collected: bool = false
var bob_offset: float = 0.0

func _ready():
	# Find ocean system
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	bob_offset = randf() * TAU
	
	# Set collision layers
	collision_layer = 1
	collision_mask = 1
	
	# Connect signal
	body_entered.connect(_on_body_entered)

func _process(delta):
	if collected:
		return
	
	# Sinking
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0:
			global_position.y += sink_speed * delta
	
	# Visual bobbing
	bob_offset += bob_speed * delta
	if has_node("Sprite2D"):
		$Sprite2D.position.y = sin(bob_offset) * bob_amount
	elif has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.position.y = sin(bob_offset) * bob_amount

func _on_body_entered(body):
	if body.is_in_group("player"):
		collect(body)

func collect(collector):
	if collected:
		return
	
	collected = true
	
	# Tween to turtle
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	await tween.finished
	
	print("Collected! +", point_value, " points")
	queue_free()
