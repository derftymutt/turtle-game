extends AlienTechEffect
class_name MagneticRepulsionEffect

## Magnetic Repulsion — keeps collectibles, trash pieces, and UFO parts
## hovering off the ocean floor and left/right/bottom boundaries instead of
## resting flush against them. Hot: always active, wider hover margin, no
## timer (see is_active_effect()). Cold: active for a fixed duration per
## activation.

const HOVER: float = 14.0        # px kept clear of the boundary
const HOVER_HOT: float = 30.0
const FORCE: float = 900.0

var active: bool = false
var _timer: float = 0.0

func activate(_player, _slot_index: int) -> void:
	# Hot is always active via is_active_effect() regardless of this timer,
	# so a press while hot (no cooldown gating it) is a harmless no-op.
	active = true
	_timer = AlienTechManager.MAGNETIC_REPULSION_ACTIVE_DURATION

func physics_process(player, delta: float) -> void:
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.MAGNETIC_REPULSION):
		_timer -= delta
		if _timer <= 0.0:
			active = false
	if is_active_effect():
		_push_nearby_bodies(player)

## True whenever the floor/wall repulsion should be running: the cold timed
## activation is running, or the tech is hot (always active). Public — read
## by BossSubmarine via TurtlePlayer.is_magnetic_repulsion_in_effect().
func is_active_effect() -> bool:
	return active or AlienTechManager.is_tech_hot(AlienTechRegistry.MAGNETIC_REPULSION)

## Magnetic Repulsion's active window is a plain countdown timer that has no
## idea the tech was unequipped mid-effect — stop it here so a swapped-out
## slot doesn't keep hovering nearby collectibles/UFO parts until that
## leftover timer happens to run out.
func on_slots_changed(_player) -> void:
	if not AlienTechManager.has_tech(AlienTechRegistry.MAGNETIC_REPULSION):
		active = false
		_timer = 0.0

## Pushes powerups, UFO parts, trash cluster pieces, and alien tech pieces
## away from the ocean floor and the left/right/bottom play-area walls so
## they hover a short distance clear of them instead of resting flush
## against the boundary. Reuses the same boundary geometry the turtle itself
## is clamped to (see TurtlePlayer._get_boundary_limits()).
func _push_nearby_bodies(player) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.MAGNETIC_REPULSION)
	var hover := HOVER_HOT if hot else HOVER
	var lim: Dictionary = player._get_boundary_limits()
	for group in ["collectibles", "trash_cluster_pieces"]:
		for node in player.get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if not node is RigidBody2D:
				continue
			var rb := node as RigidBody2D
			if rb.freeze:
				continue
			# A carried UFO piece isn't in the world for this purpose.
			if node is UFOPiece and (node as UFOPiece).is_carried:
				continue
			var push := Vector2.ZERO
			if lim.max_y < INF:
				var dist_floor: float = lim.max_y - rb.global_position.y
				if dist_floor < hover:
					push.y -= (hover - maxf(dist_floor, 0.0)) / hover * FORCE
			if lim.min_x > -INF:
				var dist_left: float = rb.global_position.x - lim.min_x
				if dist_left < hover:
					push.x += (hover - maxf(dist_left, 0.0)) / hover * FORCE
			if lim.max_x < INF:
				var dist_right: float = lim.max_x - rb.global_position.x
				if dist_right < hover:
					push.x -= (hover - maxf(dist_right, 0.0)) / hover * FORCE
			if push != Vector2.ZERO:
				# A body resting on the floor/wall falls asleep (Godot's default
				# RigidBody2D behavior), and apply_central_force() on a sleeping
				# body is silently dropped until something else wakes it — that's
				# why only some pieces (the ones still moving) were responding.
				rb.sleeping = false
				rb.apply_central_force(push)
