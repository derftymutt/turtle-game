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
@export var slippery_mode: bool = true  ## Oil slick coating - speeds up sliding
@export var slippery_acceleration: float = 150.0  ## Force applied along wall surface when sliding

var collision_shape: CollisionShape2D
var polygon: Polygon2D
var slippery_area: Area2D

func _ready():
	add_to_group("walls")
	
	# Set collision layers
	collision_layer = 1
	collision_mask = 1
	
	# Set up physics material for no bounce and ultra-slippery surface
	var physics_mat = PhysicsMaterial.new()
	physics_mat.bounce = 0.0
	physics_mat.friction = 0.0  # Zero friction = ice skating!
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
	
	# Create Area2D for slippery effect detection
	if slippery_mode:
		_setup_slippery_area()

func _physics_process(_delta):
	if not slippery_mode or not slippery_area:
		return
	
	# Apply "oil slick" acceleration to touching bodies
	var bodies = slippery_area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody2D:
			_apply_slippery_force(body)

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
	
	# Update slippery area shape to match
	if slippery_area:
		for child in slippery_area.get_children():
			if child is CollisionShape2D and child.shape is RectangleShape2D:
				child.shape.size = Vector2(wall_length, wall_thickness)
	
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

func _setup_slippery_area():
	"""Create an Area2D to detect bodies for oil slick effect"""
	slippery_area = Area2D.new()
	slippery_area.name = "SlipperyArea"
	
	# Collision setup - detect all bodies
	slippery_area.collision_layer = 0  # Not on any layer
	slippery_area.collision_mask = 1  # Detect layer 1 (world/player)
	
	# Create collision shape matching wall dimensions
	var area_collision = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(wall_length, wall_thickness)
	area_collision.shape = rect
	
	slippery_area.add_child(area_collision)
	add_child(slippery_area)
	
	# Update area shape when wall shape changes
	if collision_shape and collision_shape.shape:
		area_collision.shape.size = collision_shape.shape.size

func _apply_slippery_force(body: RigidBody2D):
	"""Apply tangential force along wall surface - creates 'oil slick' effect"""
	# Get the wall's tangent direction (perpendicular to its normal)
	var wall_angle = global_rotation
	var wall_tangent = Vector2(cos(wall_angle), sin(wall_angle))
	
	# Get body's velocity component along the wall
	var velocity_along_wall = body.linear_velocity.dot(wall_tangent)
	
	# Only accelerate if already moving along wall (not perpendicular collisions)
	if abs(velocity_along_wall) > 10:  # Minimum sliding speed threshold
		# Apply force in the direction of motion along the wall
		var direction = sign(velocity_along_wall)
		var force = wall_tangent * direction * slippery_acceleration
		body.apply_central_force(force)
