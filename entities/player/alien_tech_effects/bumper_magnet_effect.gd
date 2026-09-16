extends AlienTechEffect
class_name BumperMagnetEffect

## Bumper Magnet — seeks the nearest CircularBumper, attaches and lets the
## player orbit it (stick input revolves around the bumper), then launches
## on button-release or when the duration runs out. `active` and `attached`
## are read directly by TurtlePlayer for its super-speed suppression, ocean
## suppression, energy-recovery gate, input handling, and sprite-modulate
## priority chain — they stay public flags rather than query methods so
## those call sites don't need to change shape.

const DURATION: float = 2.0
const RADIUS: float = 30.0       # seek range beyond bumper surface
const PULL_SPEED: float = 280.0  # approach speed while seeking
const ORBIT_SPEED: float = 5.5   # radians/sec while orbiting
const PLAYER_RADIUS: float = 7.0 # must match CircleShape2D radius

var active: bool = false
var attached: bool = false
var _timer: float = 0.0
var _slot: int = -1
var _target: Node2D = null
var _angle: float = 0.0
var _attach_speed: float = 0.0

func activate(player, slot_index: int) -> void:
	active = true
	_timer = DURATION
	_slot = slot_index
	attached = false
	_target = null
	_attach_speed = player.linear_velocity.length()

func physics_process(player, delta: float) -> void:
	if not active:
		return
	_timer -= delta
	AlienTechManager.set_passive_bar(AlienTechRegistry.BUMPER_MAGNET, _timer / DURATION)
	if _timer <= 0.0:
		_launch(player)
		return
	if attached:
		_orbit(player, delta)
	else:
		_seek(player)

## Bumper magnet: release button → launch. Called from TurtlePlayer's input
## handling (not physics_process()) so it stays at the same point in the
## frame as the original inline check.
func check_release_launch(player) -> void:
	if not active:
		return
	var magnet_action := "tech_slot_left" if _slot == 0 else "tech_slot_right"
	if Input.is_action_just_released(magnet_action):
		_launch(player)

func _seek(player) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.BUMPER_MAGNET)
	var seek_radius := RADIUS * (3.0 if hot else 1.0)
	# Hot's pull speed is deliberately pushed past super_speed_threshold — the
	# existing super-speed system (is_super_speed check + SuperSpeedArea) then
	# damages any enemy the player collides with while seeking, for free.
	var pull_speed := PULL_SPEED * (2.0 if hot else 1.0)

	var nearest: CircularBumper = null
	var nearest_dist: float = INF
	for node in player.get_tree().get_nodes_in_group("bumpers"):
		if not node is CircularBumper:
			continue
		var bumper := node as CircularBumper
		# Distance from player surface to bumper surface
		var dist_to_surface: float = player.global_position.distance_to(bumper.global_position) - bumper.radius - PLAYER_RADIUS
		if dist_to_surface < seek_radius and dist_to_surface < nearest_dist:
			nearest = bumper
			nearest_dist = dist_to_surface

	if nearest == null:
		return

	var dir_outward: Vector2 = player.global_position - nearest.global_position
	if dir_outward == Vector2.ZERO:
		dir_outward = Vector2.RIGHT
	else:
		dir_outward = dir_outward.normalized()
	var contact_point := nearest.global_position + dir_outward * (nearest.radius + PLAYER_RADIUS)

	if nearest_dist <= 2.0:
		_attach(player, nearest)
	else:
		player.linear_velocity = (contact_point - player.global_position).normalized() * pull_speed

func _attach(player, bumper: CircularBumper) -> void:
	_target = bumper
	attached = true
	_angle = (player.global_position - bumper.global_position).angle()
	player.linear_velocity = Vector2.ZERO
	player.global_position = bumper.global_position + Vector2(cos(_angle), sin(_angle)) * (bumper.radius + PLAYER_RADIUS)

func _orbit(player, delta: float) -> void:
	if not is_instance_valid(_target):
		_cancel()
		return
	var bumper := _target as CircularBumper
	var stick := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if GameSettings.thrust_inverted:
		stick = -stick
	# Clockwise tangent at current angle: project stick onto it so "right stick"
	# always feels like moving right on screen regardless of attachment position.
	var tangent_cw := Vector2(-sin(_angle), cos(_angle))
	_angle += stick.dot(tangent_cw) * ORBIT_SPEED * delta
	player.global_position = bumper.global_position + Vector2(cos(_angle), sin(_angle)) * (bumper.radius + PLAYER_RADIUS)
	player.linear_velocity = Vector2.ZERO

func _launch(player) -> void:
	if attached and is_instance_valid(_target) and _target is CircularBumper:
		(_target as CircularBumper).apply_launch_force(player, _attach_speed)
	_cancel()

func _cancel() -> void:
	active = false
	attached = false
	_target = null
	_slot = -1
	AlienTechManager.clear_passive_bar(AlienTechRegistry.BUMPER_MAGNET)

func cancel_on_damage(_player) -> void:
	if active:
		_cancel()

## True when the player is currently attached to `bumper` specifically —
## used by CircularBumper to suppress its normal hit response while the
## player is magnetically orbiting it (see TurtlePlayer.is_magnet_attached_to()).
func is_attached_to(bumper) -> bool:
	return attached and _target == bumper
