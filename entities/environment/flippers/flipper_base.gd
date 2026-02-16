extends StaticBody2D
class_name FlipperBase

## PIXEL-PERFECT FLIPPER - Correct approach:
## - DON'T rotate StaticBody2D (sprite stays in place)
## - Rotate ONLY collision shapes (for physics)
## - Swap sprite frames (pixel-perfect visuals)
## - Collision setup IDENTICAL to original flipper

@export var flip_force: float = 300.0
@export var flip_speed: float = 40.0
@export var flip_input: String = "flipper_left"
@export var collision_rotation_scale: float = 0.85  # Scale collision rotation (e.g., 0.9 = 10% less rotation)

var is_flipping: bool = false
var current_rotation: float = 0.0  # Physics rotation
var target_rotation: float = 0.0
var previous_rotation: float = 0.0
var angular_velocity: float = 0.0
var hit_bodies: Dictionary = {}
var is_actively_moving: bool = false
var active_movement_timer: float = 0.0
var active_movement_duration: float = 0.3
var last_input_was_press: bool = false
var settled_time: float = 0.0
var cradle_threshold: float = 0.2
var was_cradling: bool = false

var base_collision_rotation: float = 0.0  # Store initial collision rotation from scene
var base_collision_position: Vector2 = Vector2.ZERO  # Store initial collision position from scene
var base_area_collision_position: Vector2 = Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var area: Area2D = $Area2D
@onready var area_collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

func _ready():
	target_rotation = get_rest_angle()
	current_rotation = target_rotation
	
	# Store the base collision rotation and position from the scene
	if collision_shape:
		base_collision_rotation = collision_shape.rotation
		base_collision_position = collision_shape.position
	
	if area_collision_shape:
		base_area_collision_position = area_collision_shape.position
	
	# Start at frame 0
	if animated_sprite:
		animated_sprite.frame = 0
		animated_sprite.stop()
	
	# Set initial collision rotation
	update_collision_rotation()

func _physics_process(delta):
	# Input handling
	if Input.is_action_pressed(flip_input):
		if not is_flipping:
			activate_flip()
	else:
		if is_flipping:
			# Cradle detection
			var rotation_distance = abs(angle_difference(current_rotation, target_rotation))
			var is_currently_settled = (rotation_distance < deg_to_rad(5) and abs(angular_velocity) < 1.0)
			var has_body_touching = false
			var body_is_resting = false
			
			if area:
				var touching_bodies = area.get_overlapping_bodies()
				has_body_touching = touching_bodies.size() > 0
				
				if has_body_touching:
					for body in touching_bodies:
						if body is RigidBody2D:
							var body_velocity = body.linear_velocity.length()
							if body_velocity < 50:
								body_is_resting = true
								break
			
			was_cradling = (is_currently_settled and settled_time >= cradle_threshold 
							and has_body_touching and body_is_resting)
			
			deactivate_flip()
	
	# Active movement timer
	if active_movement_timer > 0:
		active_movement_timer -= delta
		if active_movement_timer <= 0:
			is_actively_moving = false
	
	# ROTATE PHYSICS ANGLE (not StaticBody2D, just track the angle)
	previous_rotation = current_rotation
	current_rotation = lerp_angle(current_rotation, target_rotation, flip_speed * delta)
	angular_velocity = (current_rotation - previous_rotation) / delta
	
	# Update collision and sprite
	update_collision_rotation()
	update_sprite_frame()
	
	# Settled time tracking
	var rotation_distance = abs(angle_difference(current_rotation, target_rotation))
	var is_near_target = rotation_distance < deg_to_rad(5)
	
	if is_near_target and abs(angular_velocity) < 1.0:
		settled_time += delta
	else:
		settled_time = 0.0
	
	if is_actively_moving and is_near_target and abs(angular_velocity) < 1.0:
		is_actively_moving = false
		active_movement_timer = 0
	
	# Hit tracking cleanup
	var to_remove = []
	for body_id in hit_bodies.keys():
		hit_bodies[body_id] -= delta
		if hit_bodies[body_id] <= 0:
			to_remove.append(body_id)
	for body_id in to_remove:
		hit_bodies.erase(body_id)
	
	# Force application
	var velocity_threshold = 0.5 if not last_input_was_press else 2.0
	
	if is_actively_moving and abs(angular_velocity) > velocity_threshold and not is_near_target and area:
		for body in area.get_overlapping_bodies():
			if body is RigidBody2D:
				var body_id = body.get_instance_id()
				if not body_id in hit_bodies:
					hit_body(body, last_input_was_press, was_cradling)
					hit_bodies[body_id] = 0.1


func update_collision_rotation():
	"""Rotate collision shapes by physics angle + base rotation
	ALSO rotate the position vector so it orbits around the origin (pivot point)"""
	# Scale the rotation amount for collision (to match sprite angle range)
	var scaled_rotation = current_rotation * collision_rotation_scale
	
	if collision_shape:
		# Rotate the shape itself
		collision_shape.rotation = base_collision_rotation + scaled_rotation
		
		# Rotate the position vector around origin (0,0)
		collision_shape.position = base_collision_position.rotated(scaled_rotation)
	
	if area_collision_shape:
		area_collision_shape.rotation = base_collision_rotation + scaled_rotation
		area_collision_shape.position = base_area_collision_position.rotated(scaled_rotation)


func update_sprite_frame():
	"""Show frame 0 at rest, frame 1 when flipped"""
	if not animated_sprite:
		return
	
	var rest_rot = get_rest_angle()
	var flip_rot = get_flip_angle()
	
	var dist_to_rest = abs(angle_difference(current_rotation, rest_rot))
	var dist_to_flip = abs(angle_difference(current_rotation, flip_rot))
	
	if dist_to_rest < dist_to_flip:
		#animated_sprite.frame = 0
		animated_sprite.play('rest')
	else:
		#animated_sprite.frame = 2
		animated_sprite.play('extend')


func activate_flip():
	is_flipping = true
	target_rotation = get_flip_angle()
	hit_bodies.clear()
	
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = true
	settled_time = 0.0
	was_cradling = false


func deactivate_flip():
	is_flipping = false
	target_rotation = get_rest_angle()
	hit_bodies.clear()
	
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = false


func hit_body(body: RigidBody2D, is_press_action: bool, was_cradle_release: bool):
	"""Exact same physics as original flipper"""
	if not is_press_action and was_cradle_release:
		return
	
	var to_body = body.global_position - global_position
	var contact_distance = to_body.length()
	var surface_velocity = contact_distance * angular_velocity
	
	var tangent = Vector2(-to_body.y, to_body.x).normalized()
	
	if angular_velocity < 0:
		tangent = -tangent
	
	var impulse_strength = flip_force * abs(surface_velocity) * 0.1
	
	if not is_press_action:
		impulse_strength *= 2.0
	
	impulse_strength = clamp(impulse_strength, flip_force * 0.5, flip_force * 3.0)
	
	body.linear_velocity += tangent * impulse_strength


## ABSTRACT METHODS

func get_rest_angle() -> float:
	push_error("get_rest_angle() must be implemented in subclass")
	return 0.0

func get_flip_angle() -> float:
	push_error("get_flip_angle() must be implemented in subclass")
	return 0.0
