@tool
extends BaseWall
class_name DeadWall

## DEAD WALL — Non-bouncy wall that absorbs the turtle's momentum.
## Extends BaseWall for pixel-perfect angle/length/mirror configuration.
##
## Special properties:
##   - Zero bounce physics (PhysicsMaterial set in Inspector)
##   - Oil slick mode: applies tangential force in the direction of net physics
##     forces (gravity + buoyancy), making the turtle slide "downhill" along the wall
##   - Electrified mode: TODO — stuns/damages the turtle on contact
##
## SCENE SETUP REQUIRED:
##   The SlipperyArea (Area2D) must exist as a child node in the scene.
##   Its collision layer and mask MUST be set in the Inspector — never in code.
##   The script finds it by name and keeps its shape in sync automatically.

@export_group("Oil Slick")
@export var slippery_mode: bool = true
## Force applied along wall surface when the turtle is sliding "with" physics
@export var slippery_acceleration: float = 150.0

@export_group("Visual")
@export var wall_color: Color = Color(0.3, 0.3, 0.4, 1.0):
	set(value):
		wall_color = value
		if _polygon:
			_polygon.color = value

## --- Charge Animation ---
## Sprite sheets are horizontal strips: frame 0 is the static wall, frames
## 1..N-1 loop while the turtle is fast-charging energy against this wall.
## Frame size can't be inferred from the PNG (a 64x8 wall strip is ambiguous),
## so each animated sheet lists its total frame count here. Sheets not listed
## are treated as a single static frame.
const CHARGE_FRAME_COUNTS: Dictionary = {
	"wall_diagonal_1u": 5,
	"wall_diagonal_2u": 7,
	"wall_steep_2u": 6,
	"wall_shallow_1u": 5,
	"wall_shallow_2u": 6,
	"wall_horizontal_1u": 6,
}
@export var charge_anim_fps: float = 12.0

## --- Internal ---

var _slippery_area: Area2D
var _charge_frames: int = 1
var _charge_anim_time: float = 0.0
var _player: Node

## --- Lifecycle ---

var _is_phased: bool = false

func _ready() -> void:
	add_to_group("walls")
	add_to_group("dead_walls")
	add_to_group("eel_targetable")
	super._ready()  ## BaseWall: _find_children() → _ensure_unique_shapes() → _update_wall()

	## Physics material must be set in the Inspector.
	## This fallback only fires if it was accidentally removed from the scene.
	if not physics_material_override:
		push_warning("DeadWall: No PhysicsMaterial found — creating fallback. Set this in the Inspector.")
		var mat := PhysicsMaterial.new()
		mat.bounce = 0.0
		mat.friction = 0.0
		physics_material_override = mat

	_sync_color()

func _find_children() -> void:
	## BaseWall finds CollisionShape2D, Polygon2D, Sprite2D.
	## We then look for the SlipperyArea by name.
	super._find_children()
	for child in get_children():
		if child is Area2D and child.name == "SlipperyArea":
			_slippery_area = child

## Called by BaseWall._update_wall() after collision/visual are refreshed.
func _on_wall_updated() -> void:
	_resize_slippery_area()
	_sync_color()
	_setup_charge_frames()

## --- Charge Animation ---

func _setup_charge_frames() -> void:
	if not _sprite:
		return
	var key: String = "%s_%s_%du" % [get_sprite_prefix(), ANGLE_NAMES.get(int(angle_preset), "unknown"), length_units]
	_charge_frames = CHARGE_FRAME_COUNTS.get(key, 1)
	_sprite.hframes = _charge_frames
	_sprite.frame = 0
	_charge_anim_time = 0.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _charge_frames <= 1 or not _sprite:
		return

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	var charging: bool = _player != null and _player.is_fast_charging() and self in _player.touching_walls
	if charging:
		_charge_anim_time += delta
		var anim_frames: int = _charge_frames - 1
		_sprite.frame = 1 + int(_charge_anim_time * charge_anim_fps) % anim_frames
	elif _sprite.frame != 0:
		_sprite.frame = 0
		_charge_anim_time = 0.0

## Plays the charge animation with no turtle charging against the wall. The
## Academy points the mechanic out this way while the level is paused (so
## _process() isn't running): call it every frame, then end_charge_demo().
func step_charge_demo(delta: float) -> void:
	if _charge_frames <= 1 or not _sprite:
		return
	_charge_anim_time += delta
	_sprite.frame = 1 + int(_charge_anim_time * charge_anim_fps) % (_charge_frames - 1)

func end_charge_demo() -> void:
	if _sprite:
		_sprite.frame = 0
	_charge_anim_time = 0.0

## --- Oil Slick ---

func _physics_process(_delta: float) -> void:
	if not slippery_mode or not _slippery_area:
		return

	for body in _slippery_area.get_overlapping_bodies():
		if body is RigidBody2D:
			_apply_slippery_force(body)

func _resize_slippery_area() -> void:
	## Keeps the SlipperyArea's CollisionShape2D in sync with the wall's
	## current length_units and angle_preset whenever either changes.
	if not _slippery_area:
		return

	for child in _slippery_area.get_children():
		if child is CollisionShape2D:
			## Always create a fresh shape — avoids shared-resource mutation bugs.
			var new_rect := RectangleShape2D.new()
			new_rect.size = Vector2(get_pixel_length(), get_pixel_thickness())
			child.shape = new_rect
			child.rotation_degrees = get_collision_rotation_degrees()

func _apply_slippery_force(body: RigidBody2D) -> void:
	## Applies tangential acceleration ONLY when the turtle is moving in the same
	## direction as net physics forces (gravity minus buoyancy).
	## This prevents the wall from accelerating the turtle "uphill".

	var wall_angle := deg_to_rad(get_collision_rotation_degrees())
	var wall_tangent := Vector2(cos(wall_angle), sin(wall_angle))
	var velocity_along_wall := body.linear_velocity.dot(wall_tangent)

	if abs(velocity_along_wall) > 10.0:
		var net_physics_force := _calculate_net_physics_force(body)
		var physics_along_wall := net_physics_force.dot(wall_tangent)

		if sign(velocity_along_wall) == sign(physics_along_wall):
			body.apply_central_force(wall_tangent * sign(velocity_along_wall) * slippery_acceleration)

func _calculate_net_physics_force(body: RigidBody2D) -> Vector2:
	## Net downward force = gravity - buoyancy (if body is underwater).
	var net_force := Vector2(0.0, body.mass * body.gravity_scale * 980.0)

	var ocean := get_tree().get_first_node_in_group("ocean")
	if ocean and ocean.has_method("get_depth") and ocean.has_method("calculate_buoyancy_force"):
		var depth: float = ocean.get_depth(body.global_position)
		if depth > 0.0:
			net_force.y -= ocean.calculate_buoyancy_force(depth, body.mass)

	return net_force

## --- Phase Shift ---

func phase_shift(duration: float) -> void:
	if _is_phased:
		return
	_is_phased = true

	var original_layer := collision_layer
	modulate.a = 0.2
	set_deferred("collision_layer", 0)

	await get_tree().create_timer(duration).timeout

	if not is_instance_valid(self):
		return

	# Grace period so the turtle has time to swim clear before collision re-enables.
	await get_tree().create_timer(0.5).timeout

	if not is_instance_valid(self):
		return

	_is_phased = false
	modulate.a = 1.0
	set_deferred("collision_layer", original_layer)

## --- Visuals ---

func _sync_color() -> void:
	if _polygon:
		_polygon.color = wall_color
