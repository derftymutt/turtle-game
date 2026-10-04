extends AlienTechEffect
class_name CradleScopeEffect

## Cradle Scope — passive, no button. Cradling (resting on a flipper held in
## its flipped position, FlipperBase.is_cradling()) switches the scope on, and
## it stays on for as long as the turtle keeps touching that flipper: through
## the release and the slow roll down the arm. The line shows where a press
## would launch the turtle from where it is right now.
##
## The swinging arm shoves the turtle before its hit registers, which would
## make the real launch drift off the line — so the aim point freezes at the
## press and FlipperBase.hit_body() launches from it (launch_origin()). What
## the scope showed is what the flipper does.
##
## The line is straight (the launch heading), like Dilation Scope's — it does
## not bend for gravity or drag.
##
## Cold: a short line. Hot: the line runs on to the first thing in its way.

const COLD_LENGTH: float = 48.0
const HOT_LENGTH: float = 4000.0    # "no matter how far" — longer than any level
const HOT_MASK: int = 1 | (1 << 2)  # World_Player + Enemies
# Contact flickers while the turtle rolls and bounces lightly on the arm; the
# scope only drops once it has been off the flipper this long.
const CONTACT_GRACE: float = 0.15
# Releasing the cradle drops the arm out from under the turtle, which then has
# to sink back onto it — a much longer gap, allowed once per release.
const RELEASE_GRACE: float = 0.75
const LINE_COLOR := Color(1.0, 0.8, 0.35, 0.9)

var active: bool = false  # scope showing — read by TechAura

var _flipper: FlipperBase = null
var _aim_origin: Vector2 = Vector2.ZERO
var _off_contact_time: float = 0.0
var _grace: float = CONTACT_GRACE
var _was_flipping: bool = false
var _line: Line2D = null

func setup(player) -> void:
	_line = Line2D.new()
	_line.name = "CradleScopeLine"
	_line.top_level = true  # points are in global space, unaffected by the body's spin
	_line.default_color = LINE_COLOR
	_line.width = 1.0
	_line.z_as_relative = false
	_line.z_index = 24
	_line.visible = false
	player.add_child(_line)

func physics_process(player, delta: float) -> void:
	if not AlienTechManager.has_tech(AlienTechRegistry.CRADLE_SCOPE):
		_disengage()
		return
	if not active:
		_flipper = _find_cradling_flipper(player)
		if _flipper == null:
			return
		active = true
		_off_contact_time = 0.0
		_grace = CONTACT_GRACE
		_was_flipping = true
		_line.visible = true
	elif not is_instance_valid(_flipper) or player.captor_puffer:
		_disengage()
		return

	if _was_flipping and not _flipper.is_flipping:
		_grace = RELEASE_GRACE
		_off_contact_time = 0.0
	_was_flipping = _flipper.is_flipping

	if _flipper.is_touching(player) or player.touching_walls.has(_flipper):
		# Landed back on the arm — only while it's down, since the turtle can
		# still read as touching for a tick after the release.
		if _off_contact_time > 0.0 and not _flipper.is_flipping:
			_grace = CONTACT_GRACE
		_off_contact_time = 0.0
	else:
		_off_contact_time += delta
		if _off_contact_time >= _grace:
			_disengage()
			return

	# Flipper Velcro launches by its own rules, so the line would lie.
	_line.visible = not player._flipper_velcro_latched
	# Frozen during the press swing: this is the spot the launch is taken from.
	if not _flipper.is_press_swinging():
		_aim_origin = player.global_position
		_update_line(player)

## Called from TurtlePlayer.notify_launch() — any launch ends the scope.
func on_launch() -> void:
	_disengage()

## The frozen aim point if the scope is on `flipper`, else null (see
## FlipperBase.hit_body()).
func launch_origin(flipper: FlipperBase):
	if active and flipper == _flipper:
		return _aim_origin
	return null

func on_slots_changed(_player) -> void:
	if not AlienTechManager.has_tech(AlienTechRegistry.CRADLE_SCOPE):
		_disengage()

func _disengage() -> void:
	active = false
	_flipper = null
	if _line:
		_line.visible = false

func _find_cradling_flipper(player) -> FlipperBase:
	for node in player.get_tree().get_nodes_in_group("flippers"):
		var flipper := node as FlipperBase
		if flipper and flipper.is_cradling(player):
			return flipper
	return null

func _update_line(player) -> void:
	var velocity: Vector2 = player.linear_velocity + _flipper.predict_press_launch(_aim_origin, player)
	var dir: Vector2 = velocity.normalized()
	var to: Vector2 = _aim_origin + dir * COLD_LENGTH
	if AlienTechManager.is_tech_hot(AlienTechRegistry.CRADLE_SCOPE):
		to = _aim_origin + dir * HOT_LENGTH
		var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(_aim_origin, to, HOT_MASK, [player.get_rid(), _flipper.get_rid()])
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			to = hit["position"]
	_line.points = PackedVector2Array([_aim_origin, to])
