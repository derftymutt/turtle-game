# military_plane_spawner.gd
extends Node
class_name MilitaryPlaneSpawner

## Triggers MilitaryPlane passes on a randomized timer.
## Passes only occur while the player is in the sky (above the ocean surface).
## If the player drops back to the ocean mid-countdown, the timer pauses
## and resumes when they return to the sky.
##
## SETUP:
##   1. Add MilitaryPlane node to your sky level scene.
##   2. Add MilitaryPlaneSpawner alongside it.
##   3. Assign the plane reference in the Inspector.

@export var plane: MilitaryPlane

@export_group("Timing")
@export var interval_min: float = 6.0
@export var interval_max: float = 12.0
## Delay before the very first pass (gives the player a moment to settle in).
@export var first_pass_delay: float = 4.0

@export_group("Randomization")
@export var randomize_side: bool = true
## Weight toward MISSILE type. 0.0 = always spread, 1.0 = always missile.
@export var missile_weight: float = 0.5

@export_group("Sky Detection")
## Should match ocean_surface_y on your Ocean / Camera node.
@export var ocean_surface_y: float = -126.0

var _timer: float = 0.0
var _player: Node2D = null


func _ready() -> void:
	if not plane:
		push_warning("MilitaryPlaneSpawner: No MilitaryPlane assigned!")
		return

	plane.pass_completed.connect(_on_pass_completed)
	_timer = first_pass_delay
	_player = get_tree().get_first_node_in_group("player")


func _process(delta: float) -> void:
	if not plane:
		return

	# Only tick the timer while the player is in the sky
	if not _player_is_in_sky():
		return

	_timer -= delta
	if _timer <= 0.0:
		_trigger_pass()


func _trigger_pass() -> void:
	if plane.active:
		# Plane is mid-pass — try again shortly
		_timer = 1.0
		return

	var type: MilitaryPlane.PlaneType = \
		MilitaryPlane.PlaneType.MISSILE if randf() < missile_weight \
		else MilitaryPlane.PlaneType.SPREAD

	var from_left: bool = true if not randomize_side else randf() > 0.5

	plane.launch(type, from_left)


func _on_pass_completed() -> void:
	_timer = randf_range(interval_min, interval_max)


func _player_is_in_sky() -> bool:
	if not _player or not is_instance_valid(_player):
		# Re-search in case player spawned after this node
		_player = get_tree().get_first_node_in_group("player")
		return false
	return _player.global_position.y < ocean_surface_y
