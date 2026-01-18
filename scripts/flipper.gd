extends StaticBody2D

@export var flip_force: float = 300.0  # Increased base force
@export var flip_angle: float = 65.0
@export var flip_speed: float = 40.0
@export var rest_angle: float = -30.0
@export var flip_input: String = "flipper_left"
@export var flip_sprite_h: bool = false 
@export var is_right_flipper: bool = false

var is_flipping: bool = false
var target_rotation: float = 0.0
var previous_rotation: float = 0.0
var angular_velocity: float = 0.0
var hit_bodies: Dictionary = {}

@onready var collision_shape = $CollisionShape2D
@onready var sprite = $Sprite2D
@onready var area = $Area2D

func _ready():
	target_rotation = deg_to_rad(rest_angle)
	rotation = target_rotation
	previous_rotation = rotation
	
	# Remove existing collision shapes
	if collision_shape:
		collision_shape.queue_free()
	
	var flipper_length = 32
	var collision_radius = 7  # Matches turtle radius
	
	# IMPORTANT: Set collision offset AFTER we know the sprite position
	# We'll calculate this after sprite mirroring below
	
	if sprite:
		sprite.flip_h = flip_sprite_h
	
	if is_right_flipper:
		if sprite:
			sprite.position.x = -sprite.position.x
		# DON'T mirror collision - it's already set correctly above
		if area:
			area.position.x = -area.position.x
	
	# NOW get the actual sprite position after mirroring
	var collision_offset = sprite.position if sprite else Vector2(0, 0)
	
	# Create capsule collision at the sprite's position
	var capsule_collision = CollisionShape2D.new()
	var capsule = CapsuleShape2D.new()
	capsule.radius = collision_radius
	capsule.height = flipper_length
	capsule_collision.shape = capsule
	capsule_collision.rotation = deg_to_rad(90)  # Rotate to horizontal
	capsule_collision.position = collision_offset
	add_child(capsule_collision)
	
	# Area2D - also use capsule with same offset
	if area:
		for child in area.get_children():
			if child is CollisionShape2D:
				child.queue_free()
		
		var area_capsule = CollisionShape2D.new()
		var capsule_shape = CapsuleShape2D.new()
		capsule_shape.radius = collision_radius
		capsule_shape.height = flipper_length
		area_capsule.shape = capsule_shape
		area_capsule.rotation = deg_to_rad(90)  # Rotate to horizontal
		area_capsule.position = collision_offset
		area.add_child(area_capsule)

func _physics_process(delta):  # Changed to _physics_process
	if Input.is_action_pressed(flip_input):
		if not is_flipping:
			activate_flip()
	else:
		if is_flipping:
			deactivate_flip()
	
	previous_rotation = rotation
	rotation = lerp_angle(rotation, target_rotation, flip_speed * delta)
	angular_velocity = (rotation - previous_rotation) / delta  # Keep sign for direction
	
	# Clean up old hit tracking
	var to_remove = []
	for body_id in hit_bodies.keys():
		hit_bodies[body_id] -= delta
		if hit_bodies[body_id] <= 0:
			to_remove.append(body_id)
	for body_id in to_remove:
		hit_bodies.erase(body_id)
	
	# Check for hits while moving
	if abs(angular_velocity) > 0.1 and area:
		for body in area.get_overlapping_bodies():
			if body is RigidBody2D:
				var body_id = body.get_instance_id()
				if not body_id in hit_bodies:
					hit_body(body)
					hit_bodies[body_id] = 0.1

func activate_flip():
	is_flipping = true
	if is_right_flipper:
		target_rotation = deg_to_rad(rest_angle - flip_angle)  # Subtract for counter-clockwise
	else:
		target_rotation = deg_to_rad(rest_angle + flip_angle)  # Add for clockwise
	hit_bodies.clear()

func deactivate_flip():
	is_flipping = false
	target_rotation = deg_to_rad(rest_angle)
	hit_bodies.clear()

func hit_body(body):
	# Get contact point
	var to_body = body.global_position - global_position
	var contact_distance = to_body.length()
	
	# Calculate surface velocity at contact point (v = r Ã— Ï‰)
	# This is the actual speed the flipper surface is moving
	var surface_velocity = contact_distance * angular_velocity
	
	# Get tangent direction (perpendicular to radius)
	var tangent = Vector2(-to_body.y, to_body.x).normalized()
	
	# Correct tangent direction based on angular velocity sign
	if angular_velocity < 0:
		tangent = -tangent
	
	# Apply impulse based on surface velocity (realistic pinball physics)
	var impulse_strength = flip_force * abs(surface_velocity) * 0.1
	impulse_strength = clamp(impulse_strength, flip_force * 0.5, flip_force * 3.0)
	
	body.linear_velocity += tangent * impulse_strength
