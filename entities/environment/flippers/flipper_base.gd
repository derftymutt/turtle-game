extends StaticBody2D
class_name FlipperBase

## Base class for all flipper types
## Contains shared physics, cradle detection, and force application
## Subclasses define rotation direction and rest/flip angles

## Exported variables - configure in Inspector
@export var flip_force: float = 300.0  # Base force applied to bodies
@export var flip_speed: float = 40.0  # How fast flipper rotates (lerp speed)
@export var flip_input: String = "flipper_left"  # Input action to trigger flip

## Physics tracking
var is_flipping: bool = false
var target_rotation: float = 0.0
var previous_rotation: float = 0.0
var angular_velocity: float = 0.0
var hit_bodies: Dictionary = {}  # Tracks bodies we've recently hit (prevents double-hits)

## Active movement tracking (for bidirectional hits)
var is_actively_moving: bool = false  # True when flipper is responding to input change
var active_movement_timer: float = 0.0  # Countdown for active hit window
var active_movement_duration: float = 0.3  # How long after input change we apply force
var last_input_was_press: bool = false  # Tracks press vs release for force direction

## Cradle detection (prevents accidental flings when holding ball)
var settled_time: float = 0.0  # How long flipper has been at target
var cradle_threshold: float = 0.2  # Time needed to be considered "cradling"
var was_cradling: bool = false  # True if ball was being cradled before release

## Node references
@onready var area = $Area2D


func _ready():
	# Set initial rotation to rest position
	target_rotation = get_rest_angle()
	rotation = target_rotation
	previous_rotation = rotation


func _physics_process(delta):
	# Handle input - subclasses determine rotation targets via abstract methods
	if Input.is_action_pressed(flip_input):
		if not is_flipping:
			activate_flip()
	else:
		if is_flipping:
			# CRADLE DETECTION before deactivating
			# Must have ALL of:
			# 1. Flipper settled at target position
			# 2. Been settled for minimum threshold time
			# 3. Body touching flipper
			# 4. Body is mostly stationary (resting, not bouncing)
			var rotation_distance = abs(angle_difference(rotation, target_rotation))
			var is_currently_settled = (rotation_distance < deg_to_rad(5) and abs(angular_velocity) < 1.0)
			var has_body_touching = false
			var body_is_resting = false
			
			if area:
				var touching_bodies = area.get_overlapping_bodies()
				has_body_touching = touching_bodies.size() > 0
				
				# Check if any touching body is "resting" (low velocity = being cradled)
				if has_body_touching:
					for body in touching_bodies:
						if body is RigidBody2D:
							var body_velocity = body.linear_velocity.length()
							# Resting threshold: slower than 50 pixels/sec
							if body_velocity < 50:
								body_is_resting = true
								break
			
			# Only flag as cradling if body is RESTING, not actively moving
			was_cradling = (is_currently_settled and settled_time >= cradle_threshold 
							and has_body_touching and body_is_resting)
			
			deactivate_flip()
	
	# Update active movement timer (for hit detection window)
	if active_movement_timer > 0:
		active_movement_timer -= delta
		if active_movement_timer <= 0:
			is_actively_moving = false
	
	# Smoothly rotate toward target
	previous_rotation = rotation
	rotation = lerp_angle(rotation, target_rotation, flip_speed * delta)
	angular_velocity = (rotation - previous_rotation) / delta  # Preserves sign for direction
	
	# Track how long flipper has been settled (for cradle detection)
	var rotation_distance = abs(angle_difference(rotation, target_rotation))
	var is_near_target = rotation_distance < deg_to_rad(5)  # Within 5 degrees
	
	if is_near_target and abs(angular_velocity) < 1.0:
		settled_time += delta
	else:
		settled_time = 0.0
	
	# End active window early if flipper has settled
	if is_actively_moving and is_near_target and abs(angular_velocity) < 1.0:
		is_actively_moving = false
		active_movement_timer = 0
	
	# Clean up old hit tracking (prevents hitting same body multiple times)
	var to_remove = []
	for body_id in hit_bodies.keys():
		hit_bodies[body_id] -= delta
		if hit_bodies[body_id] <= 0:
			to_remove.append(body_id)
	for body_id in to_remove:
		hit_bodies.erase(body_id)
	
	# BIDIRECTIONAL FORCE APPLICATION
	# Only apply force during active movement window to prevent:
	# - Hitting bodies that just come to rest on flipper
	# - Flinging cradled balls when releasing
	#
	# Lower velocity threshold for releases (upward shots need this)
	var velocity_threshold = 0.5 if not last_input_was_press else 2.0
	
	if is_actively_moving and abs(angular_velocity) > velocity_threshold and not is_near_target and area:
		for body in area.get_overlapping_bodies():
			if body is RigidBody2D:
				var body_id = body.get_instance_id()
				if not body_id in hit_bodies:
					hit_body(body, last_input_was_press, was_cradling)
					hit_bodies[body_id] = 0.1  # Cooldown before can hit again


func activate_flip():
	"""Called when flip input is pressed - rotates to active position"""
	is_flipping = true
	target_rotation = get_flip_angle()
	hit_bodies.clear()
	
	# Start active movement window
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = true
	settled_time = 0.0
	was_cradling = false


func deactivate_flip():
	"""Called when flip input is released - returns to rest position"""
	is_flipping = false
	target_rotation = get_rest_angle()
	hit_bodies.clear()
	
	# Start active movement window for RELEASE stroke (enables bidirectional hits)
	is_actively_moving = true
	active_movement_timer = active_movement_duration
	last_input_was_press = false


func hit_body(body: RigidBody2D, is_press_action: bool, was_cradle_release: bool):
	"""
	Apply force to a body based on flipper's surface velocity
	Uses realistic pinball physics: force = contact_distance × angular_velocity
	"""
	# CRADLE PROTECTION: Don't fling balls that were being held
	if not is_press_action and was_cradle_release:
		return  # Ball was cradled - don't apply force on release
	
	# Calculate contact point and distance from pivot
	var to_body = body.global_position - global_position
	var contact_distance = to_body.length()
	
	# Surface velocity at contact point (v = r × ω)
	# This is the actual speed the flipper surface is moving at impact point
	var surface_velocity = contact_distance * angular_velocity
	
	# Get tangent direction (perpendicular to radius - direction of surface movement)
	var tangent = Vector2(-to_body.y, to_body.x).normalized()
	
	# Correct tangent based on rotation direction
	if angular_velocity < 0:
		tangent = -tangent
	
	# Calculate impulse based on surface velocity (realistic pinball physics)
	var impulse_strength = flip_force * abs(surface_velocity) * 0.1
	
	# BOOST release strokes for upward shots (they need extra power to overcome gravity)
	if not is_press_action:
		impulse_strength *= 2.0
	
	# Clamp to reasonable range
	impulse_strength = clamp(impulse_strength, flip_force * 0.5, flip_force * 3.0)
	
	# Apply the impulse
	body.linear_velocity += tangent * impulse_strength


## ABSTRACT METHODS - Subclasses must implement these

func get_rest_angle() -> float:
	"""Return the rest angle in radians - override in subclass"""
	push_error("get_rest_angle() must be implemented in subclass")
	return 0.0


func get_flip_angle() -> float:
	"""Return the active flip angle in radians - override in subclass"""
	push_error("get_flip_angle() must be implemented in subclass")
	return 0.0
