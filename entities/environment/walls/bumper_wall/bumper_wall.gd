@tool
extends StaticBody2D
class_name BumperWall

## Bouncy pinball-style bumper wall
## Reflects the turtle with added force for exciting gameplay

@export var wall_length: float = 100.0:
	set(value):
		wall_length = value
		_update_wall_shape()

@export var wall_thickness: float = 20.0:
	set(value):
		wall_thickness = value
		_update_wall_shape()

@export var wall_color: Color = Color(0.9, 0.3, 0.3, 1.0):
	set(value):
		wall_color = value
		original_color = value
		_update_wall_shape()

@export_group("Bumper Physics")
@export var bounce_multiplier: float = 1.5  ## How much force to add to reflection
@export var min_bounce_force: float = 200.0  ## Minimum bounce velocity
@export var max_bounce_force: float = 800.0  ## Cap on bounce velocity

@export_group("Visual Feedback")
@export var flash_color: Color = Color.WHITE
@export var flash_duration: float = 0.1

var collision_shape: CollisionShape2D
var polygon: Polygon2D
var original_color: Color

func _ready():
	original_color = wall_color
	add_to_group("walls")
	
	# Set collision layers
	collision_layer = 1
	collision_mask = 1
	
	# Set up physics material for high bounce
	var physics_mat = PhysicsMaterial.new()
	physics_mat.bounce = 1.2
	physics_mat.friction = 0.1
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
	
	# Create Area2D for detecting player hits (only in-game, not editor)
	if not Engine.is_editor_hint():
		var area = Area2D.new()
		area.collision_layer = 0  # Don't be on any layer
		area.collision_mask = 1   # Detect layer 1 (player)
		add_child(area)
		
		# Create matching collision shape for area
		var area_shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(wall_length, wall_thickness)
		area_shape.shape = rect
		area.add_child(area_shape)
		
		# Connect area signal
		area.body_entered.connect(_on_body_hit)

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
	
	# Update visual polygon with slight bevel for 3D effect
	if polygon:
		var half_length = wall_length / 2.0
		var half_thickness = wall_thickness / 2.0
		var bevel = 3.0
		
		polygon.polygon = PackedVector2Array([
			Vector2(-half_length, -half_thickness),
			Vector2(half_length, -half_thickness),
			Vector2(half_length - bevel, -half_thickness + bevel),
			Vector2(half_length - bevel, half_thickness - bevel),
			Vector2(half_length, half_thickness),
			Vector2(-half_length, half_thickness),
			Vector2(-half_length + bevel, half_thickness - bevel),
			Vector2(-half_length + bevel, -half_thickness + bevel)
		])
		polygon.color = wall_color

func _on_body_hit(body: Node2D):
	if body.is_in_group("player") and body is RigidBody2D:
		apply_bumper_force(body)
		play_hit_effect()

func apply_bumper_force(body: RigidBody2D):
	# Calculate reflection direction
	var collision_normal = (body.global_position - global_position).normalized()
	
	# Get current velocity magnitude
	var current_speed = body.linear_velocity.length()
	
	# Calculate bounce force (amplify it!)
	var bounce_force = clamp(
		current_speed * bounce_multiplier,
		min_bounce_force,
		max_bounce_force
	)
	
	# Apply the bounce impulse
	var bounce_velocity = collision_normal * bounce_force
	body.linear_velocity = bounce_velocity
	
	# Add slight random variation for unpredictability
	var random_angle = randf_range(-0.1, 0.1)
	body.linear_velocity = body.linear_velocity.rotated(random_angle)

func play_hit_effect():
	# Flash white on hit
	if polygon:
		polygon.color = flash_color
		await get_tree().create_timer(flash_duration).timeout
		if polygon and is_instance_valid(polygon):
			polygon.color = original_color
