extends BaseEnemy
class_name SubmarineDrone

## ============================================================
## SUBMARINE DRONE
## Deployed from the sub's top hatch. Slowly and imprecisely
## pursues the turtle. The player can destroy them with normal
## bullets.
##
## "Not very well" means: movement is slow, the drone only
## recalculates direction periodically rather than every frame,
## and there's angular jitter on its heading.
##
## Collision layers (set in Inspector):
##   Layer: 4  (enemies)
##   Mask:  1  (world) + 2 (player)
## ============================================================

@export_group("Movement")
## Top speed toward the player
@export var chase_speed: float = 150.0
## How much random angular noise (degrees) is added to the heading each update
@export var wander_jitter_deg: float = 30.0
## Seconds between recalculating the heading toward the player
@export var heading_update_interval: float = 1.2
## How quickly the drone actually accelerates toward its target heading
@export var turn_speed: float = 5.0

@export_group("Lifetime")
## Drone auto-destructs after this many seconds even if alive
@export var max_lifetime: float = 30.0

# Internal
var _player: Node2D = null
var _heading: Vector2 = Vector2.UP
var _heading_timer: float = 0.0
var _age: float = 0.0

func _enemy_ready() -> void:
	max_health = 15.0
	current_health = max_health
	contact_damage = 12.0
	gravity_scale = 0.0
	linear_damp = 3.0
	angular_damp = 5.0
	lock_rotation = false

	_player = get_tree().get_first_node_in_group("player")
	add_to_group("submarine_drones")

	# Stagger the first heading recalculation per drone to avoid sync
	_heading_timer = randf_range(0.0, heading_update_interval)

	# Random initial ejection velocity out of the hatch
	var eject_angle := randf_range(-PI * 0.3, PI * 0.3) - PI * 0.5  # roughly upward
	linear_velocity = Vector2(cos(eject_angle), sin(eject_angle)) * 80.0

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		die()
		return

	_update_heading(delta)
	_apply_movement(delta)
	_face_heading()

func _update_heading(delta: float) -> void:
	_heading_timer += delta
	if _heading_timer < heading_update_interval:
		return
	_heading_timer = 0.0

	if not _player or not is_instance_valid(_player):
		return

	# Base direction toward player
	var to_player := (_player.global_position - global_position).normalized()

	# Add angular jitter for the "not very well" feel
	var jitter := randf_range(
		-deg_to_rad(wander_jitter_deg),
		 deg_to_rad(wander_jitter_deg)
	)
	_heading = to_player.rotated(jitter)

func _apply_movement(delta: float) -> void:
	# Blend current velocity toward heading * chase_speed
	var target_vel := _heading * chase_speed
	linear_velocity = linear_velocity.lerp(target_vel, turn_speed * delta)

func _face_heading() -> void:
	## Rotate the sprite to face the direction of travel.
	## We counter-rotate the sprite node to cancel the RigidBody's
	## own rotation (same pattern as the turtle player).
	if linear_velocity.length() > 5.0:
		rotation = linear_velocity.angle()

## Override die() for a small pop effect
func die() -> void:
	collision_layer = 0
	collision_mask = 0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color(2.0, 1.0, 0.2, 0.0), 0.3)

	tween.finished.connect(queue_free)
