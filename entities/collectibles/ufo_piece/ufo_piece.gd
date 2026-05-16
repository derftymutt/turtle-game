# ufo_piece.gd
extends BaseCollectible
class_name UFOPiece

## UFO piece collectible - NO points on pickup, only on delivery
## Can be picked up, carried, and dropped

const _MAX_SPEED := 200.0

var is_carried: bool = false
var carrier: Node2D = null
var _drop_grace_timer: float = 0.0
var _cached_limits: Dictionary = {}

func _collectible_ready():
	sink_speed = 0.0
	sway_amount = 0.0
	mass = 1.5

	# Continuous collision detection stops the piece from tunnelling through
	# thin wall geometry if it builds up speed from enemy collisions.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE

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

	if _drop_grace_timer > 0.0:
		_drop_grace_timer -= delta

	# Slight downward force to settle on floor
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0:
			apply_central_force(Vector2(0, 20))

	# Keep piece inside the play area every frame, not just on intentional drop.
	_enforce_horizontal_bounds()

func _integrate_forces(state: PhysicsDirectBodyState2D):
	# Cap speed at physics-engine level so crab collisions cannot accelerate
	# the piece past a safe threshold, even across multiple frames.
	if is_carried:
		return
	if state.linear_velocity.length_squared() > _MAX_SPEED * _MAX_SPEED:
		state.linear_velocity = state.linear_velocity.normalized() * _MAX_SPEED

func _on_collected(collector):
	"""Override base class - pickup behavior (NO points!)"""
	# Intentional-drop grace period: ignore pickup for 2 seconds after player dropped it
	if _drop_grace_timer > 0.0:
		collected = false
		return

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
	$SfxPickup.play()

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

func drop_piece(intentional: bool = false):
	"""Drop the piece. Pass intentional=true when the player chooses to drop it
	   so a 2-second grace period prevents immediately picking it up again."""
	if not is_carried:
		return

	is_carried = false
	collected = false  # Allow re-collection
	GameManager.carried_piece = null
	GameManager.is_carrying_piece = false
	carrier = null

	if intentional:
		_drop_grace_timer = 2.0

	# Restore physics
	freeze = false
	collision_layer = 2
	collision_mask = 1

	# Disable manual _process() following
	set_process(false)

	# Keep the piece inside the play area and push it away from any nearby wall
	_clamp_to_play_area()
	apply_impulse(_safe_drop_impulse())

	print("🔧 Dropped UFO piece")

func _get_play_area_limits() -> Dictionary:
	# Small margin — just enough to keep the piece inside the wall geometry
	const MARGIN := 6.0
	var limits := {min_x = -INF, max_x = INF}
	var root = get_tree().current_scene
	if not root:
		return limits
	var wb = root.get_node_or_null("WorldSafetyBoundaries")
	if not wb:
		return limits
	for bname in ["BoundaryLeft", "BoundaryRight"]:
		var node = wb.get_node_or_null(bname)
		if not node:
			continue
		for child in node.get_children():
			if not child is CollisionShape2D:
				continue
			var col := child as CollisionShape2D
			var cx := col.global_position.x
			var hw := 0.0
			if col.shape is RectangleShape2D:
				hw = (col.shape as RectangleShape2D).size.x * 0.5
			match bname:
				"BoundaryLeft":  limits.min_x = cx + hw + MARGIN
				"BoundaryRight": limits.max_x = cx - hw - MARGIN
			break
	return limits

func _clamp_to_play_area():
	var lim := _get_play_area_limits()
	if lim.min_x > -INF and lim.max_x < INF:
		global_position.x = clamp(global_position.x, lim.min_x, lim.max_x)

func _enforce_horizontal_bounds():
	if _cached_limits.is_empty():
		_cached_limits = _get_play_area_limits()
	var lim := _cached_limits
	if lim.min_x > -INF and global_position.x < lim.min_x:
		global_position.x = lim.min_x
		linear_velocity.x = maxf(linear_velocity.x, 0.0)
	elif lim.max_x < INF and global_position.x > lim.max_x:
		global_position.x = lim.max_x
		linear_velocity.x = minf(linear_velocity.x, 0.0)

func _safe_drop_impulse() -> Vector2:
	return Vector2(randf_range(-100.0, 100.0), -200.0)

func award_delivery_points():
	"""Called by UFOWorkshop when successfully delivered"""
	if carrier and carrier.has_method("add_score"):
		carrier.add_score(point_value)
		print("🛠️ UFO piece delivered! +%d points" % point_value)
