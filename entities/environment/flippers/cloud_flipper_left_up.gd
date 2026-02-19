extends FlipperBase
class_name CloudFlipperLeftUp

## Cloud Flipper - Left Side, Upward Launch
## Identical angles to FlipperLeftUp, with layer-based pass-through
## so the turtle can rise upward through the flipper from below.
##
## INSPECTOR SETUP:
##   Root StaticBody2D →  Collision Layer: 5   Collision Mask: 1
##   Area2D            →  Collision Layer: 0   Collision Mask: 1
##   TurtlePlayer      →  add bit 5 to its Collision Mask
##
## Rest position:  angled down-left
## Flip position:  rotates clockwise to launch ball up/right

@export var rest_angle_degrees: float = 30.0
@export var flip_angle_degrees: float = 60.0

## Upward Y velocity threshold to trigger pass-through.
## Negative = moving up in Godot's coordinate system.
## Tune this down toward 0.0 to make pass-through more permissive.
@export var pass_through_velocity_threshold: float = -50.0

## Physics layer bit for cloud flippers (layer 5, zero-indexed = 4).
const CLOUD_FLIPPER_LAYER_BIT: int = 4

var _passing_bodies: Dictionary = {}
var _player: RigidBody2D = null


func _ready():
	super._ready()
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta):
	super._physics_process(delta)
	_update_pass_through()


func get_rest_angle() -> float:
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	return deg_to_rad(rest_angle_degrees - flip_angle_degrees)


func _update_pass_through():
	if not is_instance_valid(_player):
		return
	
	# Pass through whenever the turtle is moving upward fast enough.
	# No position check — velocity alone is the gate.
	# When the turtle slows, stops, or falls back down (positive Y velocity),
	# the mask is restored and the flipper becomes solid again.
	if _player.linear_velocity.y <= pass_through_velocity_threshold:
		_enable_pass_through(_player)
	else:
		_disable_pass_through(_player)


func _enable_pass_through(body: RigidBody2D):
	var id = body.get_instance_id()
	if _passing_bodies.has(id):
		return
	_passing_bodies[id] = true
	body.set_deferred("collision_mask", body.collision_mask &~ (1 << CLOUD_FLIPPER_LAYER_BIT))


func _disable_pass_through(body: RigidBody2D):
	var id = body.get_instance_id()
	if not _passing_bodies.has(id):
		return
	_passing_bodies.erase(id)
	body.set_deferred("collision_mask", body.collision_mask | (1 << CLOUD_FLIPPER_LAYER_BIT))
