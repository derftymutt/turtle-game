@tool
extends BaseWall
class_name BumperWall2

## BUMPER WALL — Bouncy pinball-style wall that amplifies the turtle's velocity.
## Extends BaseWall for pixel-perfect angle/length/mirror configuration.
##
## Special properties:
##   - High bounce physics (PhysicsMaterial set in Inspector)
##   - Hit detection via Area2D → applies amplified reflection force
##   - Flash-on-hit visual feedback
##   - Electrified mode: TODO — add electric visual + extra stun force
##
## SCENE SETUP REQUIRED:
##   The HitArea (Area2D) must exist as a child node in the scene.
##   Its collision layer and mask MUST be set in the Inspector — never in code.
##   The script finds it by name, connects its signal, and keeps its shape in sync.

@export_group("Bumper Physics")
@export var bounce_multiplier: float = 1.5   ## Multiplier on incoming speed
@export var min_bounce_force: float = 400.0  ## Floor on bounce velocity
@export var max_bounce_force: float = 800.0  ## Ceiling on bounce velocity

@export_group("Visual Feedback")
@export var wall_color: Color = Color(0.9, 0.3, 0.3, 1.0):
	set(value):
		wall_color = value
		_original_color = value
		if _polygon:
			_polygon.color = value
@export var flash_color: Color = Color.WHITE
@export var flash_duration: float = 0.1

## --- Internal ---

var _hit_area: Area2D
var _original_color: Color

## --- Lifecycle ---

func _ready() -> void:
	_original_color = wall_color
	add_to_group("walls")
	super._ready()  ## BaseWall: _find_children() → _ensure_unique_shapes() → _update_wall()

	## Physics material must be set in the Inspector.
	## This fallback only fires if it was accidentally removed from the scene.
	if not physics_material_override:
		push_warning("BumperWall: No PhysicsMaterial found — creating fallback. Set this in the Inspector.")
		var mat := PhysicsMaterial.new()
		mat.bounce = 1.2
		mat.friction = 0.1
		physics_material_override = mat

	_sync_color()

func _find_children() -> void:
	## BaseWall finds CollisionShape2D, Polygon2D, Sprite2D.
	## We then look for the HitArea by name and connect its signal.
	## Signal connection happens here (not _ready) so it's guaranteed to run
	## after the node is in the tree and the Area2D is fully initialized.
	super._find_children()
	for child in get_children():
		if child is Area2D and child.name == "HitArea":
			_hit_area = child
			## Only connect at runtime — the @tool editor context doesn't need it
			## and connecting in editor can cause spurious signal firings.
			if not Engine.is_editor_hint():
				if not _hit_area.body_entered.is_connected(_on_body_hit):
					_hit_area.body_entered.connect(_on_body_hit)

## Called by BaseWall._update_wall() after collision/visual are refreshed.
func _on_wall_updated() -> void:
	_resize_hit_area()
	_sync_color()

## --- Hit Area ---

func _resize_hit_area() -> void:
	## Keeps the HitArea's CollisionShape2D in sync with the wall's
	## current length_units and angle_preset whenever either changes.
	if not _hit_area:
		return

	for child in _hit_area.get_children():
		if child is CollisionShape2D:
			## Always create a fresh shape — avoids shared-resource mutation bugs.
			var new_rect := RectangleShape2D.new()
			new_rect.size = Vector2(get_pixel_length(), get_pixel_thickness())
			child.shape = new_rect
			child.rotation_degrees = get_collision_rotation_degrees()

## --- Bumper Logic ---

func _on_body_hit(body: Node2D) -> void:
	if body.is_in_group("player") and body is RigidBody2D:
		_apply_bumper_force(body)
		_play_hit_effect()

func _apply_bumper_force(body: RigidBody2D) -> void:
	## Reflects the turtle away from the wall center with amplified force.
	## Using position delta for direction means it always pushes outward
	## regardless of which face of the wall was hit.
	var collision_normal := (body.global_position - global_position).normalized()
	var bounce_force: float = clamp(
		body.linear_velocity.length() * bounce_multiplier,
		min_bounce_force,
		max_bounce_force
	)
	body.linear_velocity = collision_normal * bounce_force
	## Small random rotation keeps bounces unpredictable and fun
	body.linear_velocity = body.linear_velocity.rotated(randf_range(-0.1, 0.1))

## --- Visuals ---

func _play_hit_effect() -> void:
	if not _polygon:
		return
	_polygon.color = flash_color
	await get_tree().create_timer(flash_duration).timeout
	if is_instance_valid(_polygon):
		_polygon.color = _original_color

func _sync_color() -> void:
	if _polygon:
		_polygon.color = wall_color
