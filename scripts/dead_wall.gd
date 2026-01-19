@tool
extends StaticBody2D
class_name DeadWall

## Non-bouncy wall that absorbs the turtle's momentum
## Adjustable size and rotation for quick layout prototyping

@export var wall_length: float = 100.0:
	set(value):
		wall_length = value
		_update_wall_shape()

@export var wall_thickness: float = 20.0:
	set(value):
		wall_thickness = value
		_update_wall_shape()

@export var wall_color: Color = Color(0.3, 0.3, 0.4, 1.0):
	set(value):
		wall_color = value
		_update_wall_shape()

@export_group("Physics")
@export var damping_factor: float = 0.3  ## How much velocity is killed on contact

var collision_shape: CollisionShape2D
var polygon: Polygon2D

func _ready():
	add_to_group("walls")
	
	# Set collision layers
	collision_layer = 1
	collision_mask = 1
	
	# Set up physics material for no bounce
	var physics_mat = PhysicsMaterial.new()
	physics_mat.bounce = 0.0
	physics_mat.friction = 0.8
	physics_material_override = physics_mat
	
	# Create or find child nodes
	if get_child_count() == 0:
		_setup_visuals()
	else:
		for child in get_children():
			if child is Polygon2D:
				polygon = child
			elif child is CollisionShape2D:
				collision_shape = child
	
	# Ensure collision shape has actual shape data
	if collision_shape and collision_shape.shape == null:
		var rect = RectangleShape2D.new()
		rect.size = Vector2(wall_length, wall_thickness)
		collision_shape.shape = rect
	
	_update_wall_shape()
	
	# Ensure collision is enabled
	if collision_shape:
		collision_shape.disabled = false

func _setup_visuals():
	# Create visual polygon
	polygon = Polygon2D.new()
	polygon.color = wall_color
	add_child(polygon)
	if Engine.is_editor_hint():
		polygon.owner = get_tree().edited_scene_root
	
	# Create collision shape
	collision_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	collision_shape.shape = rect
	add_child(collision_shape)
	if Engine.is_editor_hint():
		collision_shape.owner = get_tree().edited_scene_root

func _update_wall_shape():
	if not is_inside_tree():
		return
	
	# Update collision rectangle
	if collision_shape and collision_shape.shape:
		collision_shape.shape.size = Vector2(wall_length, wall_thickness)
	
	# Update visual polygon
	if polygon:
		var half_length = wall_length / 2.0
		var half_thickness = wall_thickness / 2.0
		polygon.polygon = PackedVector2Array([
			Vector2(-half_length, -half_thickness),
			Vector2(half_length, -half_thickness),
			Vector2(half_length, half_thickness),
			Vector2(-half_length, half_thickness)
		])
		polygon.color = wall_color
