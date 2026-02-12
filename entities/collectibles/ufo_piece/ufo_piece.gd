# ufo_piece.gd
extends BaseCollectible
class_name UFOPiece

## UFO piece collectible - NO points on pickup, only on delivery
## Can be picked up, carried, and dropped

var is_carried: bool = false
var carrier: Node2D = null

func _collectible_ready():
	# UFO pieces don't sink/sway like stars
	sink_speed = 0.0
	sway_amount = 0.0
	
	# Heavier than stars
	mass = 1.5
	
	# Disable the base class physics processing (we handle our own)
	# But keep visual bobbing when not carried
	pass

func _process(_delta):
	"""Follow carrier while being carried"""
	if not is_carried or carrier == null:
		return
	
	var carry_point = carrier.get_node_or_null("CarryPoint")
	if carry_point:
		global_position = carry_point.global_position

func _collectible_physics_process(delta):
	"""Custom physics - only run when NOT carried"""
	if is_carried:
		return
	
	# UFO pieces don't sink/sway - they're heavy mechanical parts
	# Just apply slight gravity to settle on floor
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0:
			apply_central_force(Vector2(0, 20))  # Slight downward force

func _on_collected(collector):
	"""Override base class - pickup behavior (NO points!)"""
	# Check if player is already carrying something
	if GameManager.is_carrying_piece:
		# Don't collect - player already has one
		collected = false  # Reset so we can try again
		return
	
	# Pick up the piece
	is_carried = true
	carrier = collector
	GameManager.carried_piece = self
	GameManager.is_carrying_piece = true
	
	# 🚫 NO POINTS AWARDED HERE!
	print("🔧 Picked up UFO piece (no points yet - deliver it!)")
	
	# Remove from physics, but KEEP IN WORLD
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	collision_layer = 0
	collision_mask = 0
	
	# Enable _process() for following carrier
	set_process(true)

func drop_piece():
	"""Drop the piece (e.g., when taking damage)"""
	if not is_carried:
		return
	
	is_carried = false
	collected = false  # Allow re-collection
	GameManager.carried_piece = null
	GameManager.is_carrying_piece = false
	carrier = null
	
	# Restore physics
	freeze = false
	collision_layer = 2
	collision_mask = 1
	
	# Disable manual _process() following
	set_process(false)
	
	# Give it a little bounce
	apply_impulse(Vector2(randf_range(-100, 100), -200))
	
	print("🔧 Dropped UFO piece")

func award_delivery_points():
	"""Called by UFOWorkshop when successfully delivered"""
	if carrier and carrier.has_method("add_score"):
		carrier.add_score(point_value)
		print("🛠️ UFO piece delivered! +%d points" % point_value)
