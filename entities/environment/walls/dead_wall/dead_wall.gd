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

## --- Internal ---

var _slippery_area: Area2D

## --- Lifecycle ---

func _ready() -> void:
	add_to_group("walls")
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

## --- Visuals ---

func _sync_color() -> void:
	if _polygon:
		_polygon.color = wall_color
