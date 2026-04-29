extends Node2D
class_name Dolphin

# ============================================================
# MOVEMENT
# ============================================================
@export_group("Movement")
## Horizontal swim speed in pixels/sec
@export var swim_speed: float = 90.0
## 1 = left-to-right, -1 = right-to-left (set by spawner)
@export var swim_direction: int = 1
## Vertical oscillation amplitude (pixels)
@export var swim_amplitude: float = 9.0
## Oscillation cycles per second
@export var swim_frequency: float = 1.6

# ============================================================
# UFO DROP
# ============================================================
@export_group("UFO Drop")
@export var community_ufo_scene: PackedScene
## World X position at which to drop the UFO (set by spawner before _ready)
@export var drop_x: float = 0.0
## World X at which the dolphin leaves the scene
@export var exit_x: float = 9999.0
## Vertical offset applied to the UFO's position when it is released
@export var ufo_drop_offset: Vector2 = Vector2(0.0, 10.0)
## How fast the dolphin accelerates away after dropping (pixels/sec added)
@export var post_drop_speed_boost: float = 40.0

# ============================================================
# INTERNAL STATE
# ============================================================

var _has_dropped: bool = false
var _swim_time: float = 0.0
var _current_speed: float = 0.0
var _carried_ufo: Node2D = null

func _ready():
	_current_speed = swim_speed
	add_to_group("dolphins")

	# Sprite faces LEFT by default.
	# direction = 1 (going right) → flip_h so it faces right.
	# direction = -1 (going left) → no flip, natural orientation.
	var sprite = get_node_or_null("AnimatedSprite2D")
	if sprite:
		sprite.flip_h = (swim_direction == 1)

	_spawn_carried_ufo()

func _process(delta: float):
	_swim_time += delta

	global_position.x += _current_speed * swim_direction * delta
	global_position.y += cos(_swim_time * swim_frequency * TAU) * swim_amplitude * delta

	# Keep carried UFO anchored to CarryPoint
	if _carried_ufo and is_instance_valid(_carried_ufo) and not _has_dropped:
		var carry_point = get_node_or_null("CarryPoint")
		if carry_point:
			_carried_ufo.global_position = carry_point.global_position

	if not _has_dropped and _should_drop():
		_drop_ufo()

	if _past_exit():
		queue_free()

func _should_drop() -> bool:
	return global_position.x >= drop_x if swim_direction > 0 else global_position.x <= drop_x

func _past_exit() -> bool:
	return global_position.x >= exit_x if swim_direction > 0 else global_position.x <= exit_x

# ──────────────────────────────────────────────────────────────────────────────
# UFO CARRY / DROP
# ──────────────────────────────────────────────────────────────────────────────

func _spawn_carried_ufo():
	if not community_ufo_scene:
		push_warning("Dolphin: community_ufo_scene not assigned!")
		return

	var ufo = community_ufo_scene.instantiate() as Node2D

	# Flag must be set BEFORE add_child so _ready() builds the PickupArea disabled.
	# Also hide so there is zero chance of a render frame showing the UFO at (0,0).
	ufo.set("being_carried", true)
	ufo.hide()

	get_parent().add_child(ufo)
	_carried_ufo = ufo

	# Let the UFO know who is carrying it so it can call us back if the
	# turtle enters the UFO while we're still mid-swim.
	if ufo.has_method("set_carrying_dolphin"):
		ufo.set_carrying_dolphin(self)

	# Freeze physics so it doesn't sink while being carried
	if ufo is RigidBody2D:
		ufo.freeze = true
		ufo.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC

	# Position at carry point and reveal
	var carry_point = get_node_or_null("CarryPoint")
	if carry_point:
		ufo.global_position = carry_point.global_position
	ufo.show()

## Called by the UFO when the turtle enters it while we're still carrying it.
## We stop tracking the UFO without applying a drop impulse (the UFO is now
## frozen in AIMING phase under the turtle's control).
func on_ufo_entered_by_player():
	if _has_dropped:
		return
	_has_dropped = true
	_carried_ufo = null
	_current_speed += post_drop_speed_boost

func _drop_ufo():
	_has_dropped = true
	_current_speed += post_drop_speed_boost

	if not _carried_ufo or not is_instance_valid(_carried_ufo):
		return

	var ufo = _carried_ufo
	_carried_ufo = null

	# Restore UFO to normal sinking behavior
	if ufo is RigidBody2D:
		ufo.freeze = false

	# Tell the UFO to open its pickup area.
	# Using a public method avoids the duplicate-node naming collision that
	# would occur if we called get_node("PickupArea") here directly.
	if ufo.has_method("release_from_carry"):
		ufo.release_from_carry()

	# Nudge downward so it starts sinking away from the dolphin
	ufo.global_position += ufo_drop_offset
	if ufo is RigidBody2D:
		ufo.apply_central_impulse(Vector2(0.0, 40.0))
