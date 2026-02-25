# military_plane_spawner.gd
extends Node
class_name MilitaryPlaneSpawner

## Triggers MilitaryPlane passes on a randomized timer.
## Place this node in your sky level scene alongside the MilitaryPlane node.
##
## SETUP:
##   1. Add MilitaryPlane node to the sky level scene.
##   2. Add MilitaryPlaneSpawner node to the same scene.
##   3. Assign the plane reference in the Inspector.

@export var plane: MilitaryPlane

@export_group("Timing")
## Minimum seconds between passes.
@export var interval_min: float = 6.0
## Maximum seconds between passes.
@export var interval_max: float = 12.0
## Delay before the very first pass (gives the player a moment to settle).
@export var first_pass_delay: float = 4.0

@export_group("Randomization")
## If true, side (left/right entry) is randomized each pass.
## If false, the plane always enters from the left.
@export var randomize_side: bool = true
## Weight toward MISSILE type. 0.0 = always spread, 1.0 = always missile.
## 0.5 = equal chance. Tweak to taste.
@export var missile_weight: float = 0.5

var _timer: float = 0.0
var _active: bool = false


func _ready() -> void:
	if not plane:
		push_warning("MilitaryPlaneSpawner: No MilitaryPlane assigned!")
		return

	plane.pass_completed.connect(_on_pass_completed)
	_timer = first_pass_delay
	_active = true


func _process(delta: float) -> void:
	if not _active or not plane:
		return

	_timer -= delta
	if _timer <= 0.0:
		_trigger_pass()


func _trigger_pass() -> void:
	if plane.active:
		# Plane is mid-pass; try again shortly
		_timer = 1.0
		return

	var type: MilitaryPlane.PlaneType = \
		MilitaryPlane.PlaneType.MISSILE if randf() < missile_weight \
		else MilitaryPlane.PlaneType.SPREAD

	var from_left: bool = true if not randomize_side else randf() > 0.5

	plane.launch(type, from_left)


func _on_pass_completed() -> void:
	_timer = randf_range(interval_min, interval_max)
