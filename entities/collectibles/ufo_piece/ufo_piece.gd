# Extend Collectible for UFO pieces
extends Collectible
class_name UFOPiece

#@export var piece_id: int = 0  # Which piece (1-5, etc)
var is_carried: bool = false
var carrier: Node2D = null
var can_be_collected := true

func _process(_delta):
	if not is_carried or carrier == null:
		return

	var carry_point := carrier.get_node("CarryPoint")
	global_position = carry_point.global_position



func collect(collector):
	if GameManager.is_carrying_piece:
		return

	collected = true
	is_carried = true
	carrier = collector   # ✅ THIS is the missing piece

	GameManager.carried_piece = self
	GameManager.is_carrying_piece = true

	if collector.has_method("add_score"):
		collector.add_score(point_value)

	# Remove from physics, but KEEP IN WORLD
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	collision_layer = 0
	collision_mask = 0

	set_process(true)

func dropPiece():
	if not is_carried:
		return

	is_carried = false
	collected = false

	GameManager.carried_piece = null
	GameManager.is_carrying_piece = false

	# 🔴 IMPORTANT
	carrier = null

	# Restore physics
	freeze = false
	collision_layer = 2
	collision_mask = 1

	set_process(false)

	apply_impulse(Vector2(randf_range(-100, 100), -200))
