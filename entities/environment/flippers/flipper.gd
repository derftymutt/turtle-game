extends StaticBody2D

@export var flip_force: float = 300.0  # Increased base force
@export var flip_angle: float = 65.0
@export var flip_speed: float = 40.0
@export var rest_angle: float = -30.0
@export var flip_input: String = "flipper_left"
@export var flip_sprite_h: bool = false 
@export var is_right_flipper: bool = false
@export var is_skyward_flipper: bool = false

var is_flipping: bool = false
var target_rotation: float = 0.0
var previous_rotation: float = 0.0
var angular_velocity: float = 0.0
var hit_bodies: Dictionary = {}
var is_actively_moving: bool = false  # True when flipper is responding to input change
var active_movement_timer: float = 0.0  # How long since last input change
var active_movement_duration: float = 0.3  # Time window for active hits
var last_input_was_press: bool = false  # Track if last input change was press or release
var settled_time: float = 0.0  # How long flipper has been at target position
var cradle_threshold: float = 0.2  # Time needed to be considered "cradling"
var was_cradling: bool = false  # True if flipper was settled long enough before release

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
	# Track input changes to determine "active" movement window
	if Input.is_action_pressed(flip_input):
		if not is_flipping:
			activate_flip()
	else:
		if is_flipping:
			# CRADLE DETECTION: Must have ALL of:
			# 1. Flipper settled at target
			# 2. Been settled for a while (0.2s+)
			# 3. Body touching flipper
			# 4. Body is mostly stationary (resting, not actively moving)
			var rotation_distance = abs(angle_difference(rotation, target_rotation))
			var is_currently_settled = (rotation_distance < deg_to_rad(5) and abs(angular_velocity) < 1.0)
			var has_body_touching = false
			var body_is_resting = false
			
			if area:
				var touching_bodies = area.get_overlapping_bodies()
				has_body_touching = touching_bodies.size() > 0
				
				# Check if any touching body is "resting" (low velocity)
				if has_body_touching:
					for body in touching_bodies:
						if body is RigidBody2D:
							var body_velocity = body.linear_velocity.length()
							# Resting = moving slower than 50 pixels/sec
							if body_velocity < 50:
								body_is_resting = true
								break
			
			# Only consider it cradling if body is RESTING, not actively moving
			was_cradling = (is_currently_settled and settled_time >= cradle_threshold and has_body_touching and body_is_resting)
			#print("RELEASE: settled=%s, time=%.2f, touching=%s, resting=%s, was_cradling=%s" % [is_currently_settled, settled_time, has_body_touching, body_is_resting, was_cradling])
			deactivate_flip()
	
	# Update active movement timer
	if active_movement_timer > 0:
		active_movement_timer -= delta
		if active_movement_timer <= 0:
			is_actively_moving = false
	
	previous_rotation = rotation
	rotation = lerp_angle(rotation, target_rotation, flip_speed * delta)
	angular_velocity = (rotation - previous_rotation) / delta  # Keep sign for direction
	
	# Check if flipper has mostly reached its target (for cradle detection)
	var rotation_distance = abs(angle_difference(rotation, target_rotation))
	var is_near_target = rotation_distance < deg_to_rad(5)  # Within 5 degrees
	
	# Track how long flipper has been settled at target
	if is_near_target and abs(angular_velocity) < 1.0:
		settled_time += delta
	else:
		settled_time = 0.0
	
	# If flipper is near target and barely moving, end active window early
	if is_actively_moving and is_near_target and abs(angular_velocity) < 1.0:
		is_actively_moving = false
		active_movement_timer = 0
	
	# Clean up old hit tracking
	var to_remove = []
	for body_id in hit_bodies.keys():
		hit_bodies[body_id] -= delta
		if hit_bodies[body_id] <= 0:
			to_remove.append(body_id)
	for body_id in to_remove:
		hit_bodies.erase(body_id)
	
	# BIDIRECTIONAL FLIPPING with CRADLE PROTECTION:
	# Only hit if:
	# 1. In active movement window AND
	# 2. Flipper is moving with significant velocity AND
	# 3. Flipper hasn't settled into target position yet
	#
	# IMPORTANT: Use lower velocity threshold for releases (upward shots need this!)
	var velocity_threshold = 0.5 if not last_input_was_press else 2.0
	
	if is_actively_moving and abs(angular_velocity) > velocity_threshold and not is_near_target and area:
		for body in area.get_overlapping_bodies():
			if body is RigidBody2D:
				var body_id = body.get_instance_id()
				if not body_id in hit_bodies:
					# DEBUG
					#print("HIT! press=%s, cradling=%s, ang_vel=%.2f" % [last_input_was_press, was_cradling, angular_velocity])
					hit_body(body, last_input_was_press, was_cradling)
					hit_bodies[body_id] = 0.1

func activate_flip():
	is_flipping = true
	if is_right_flipper:
		target_rotation = deg_to_rad((rest_angle + flip_angle) if is_skyward_flipper else (rest_angle - flip_angle))  # Subtract for counter-clockwise
	else:
		target_rotation = deg_to_rad((rest_angle - flip_angle) if is_skyward_flipper else (rest_angle + flip_angle))  # Add for clockwise
	hit_bodies.clear()
	
	# Start active movement window
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = true  # Track that this is a PRESS action
	settled_time = 0.0  # Reset settled time on new input
	was_cradling = false  # Reset cradle flag

func deactivate_flip():
	is_flipping = false
	target_rotation = deg_to_rad(rest_angle)
	hit_bodies.clear()
	
	# Start active movement window for RELEASE stroke (bidirectional!)
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = false  # Track that this is a RELEASE action


func hit_body(body, is_press_action: bool, was_cradle_release: bool):
	# Get contact point
	var to_body = body.global_position - global_position
	var contact_distance = to_body.length()
	
	# Calculate surface velocity at contact point (v = r x omega)
	# This is the actual speed the flipper surface is moving
	var surface_velocity = contact_distance * angular_velocity
	
	# Get tangent direction (perpendicular to radius)
	var tangent = Vector2(-to_body.y, to_body.x).normalized()
	
	# Correct tangent direction based on angular velocity sign
	if angular_velocity < 0:
		tangent = -tangent
	
	# CRADLE DETECTION:
	# If this is a RELEASE and flipper was cradling, don't apply force
	if not is_press_action and was_cradle_release:
		#print("  -> BLOCKED: Cradle release detected")
		return  # This is a cradle release - don't fling
	
	# Apply impulse based on surface velocity (realistic pinball physics)
	var impulse_strength = flip_force * abs(surface_velocity) * 0.1
	
	# BOOST release strokes for upward shots (they need extra power!)
	if not is_press_action:
		impulse_strength *= 2.0  # Double the force for release strokes
		#print("  -> RELEASE BOOST: 2x force")
	
	impulse_strength = clamp(impulse_strength, flip_force * 0.5, flip_force * 3.0)
	
	#print("  -> Applying force: %.2f in direction %s" % [impulse_strength, tangent])
	body.linear_velocity += tangent * impulse_strength
