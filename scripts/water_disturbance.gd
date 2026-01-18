extends Area2D

# This creates a "current" or "disturbance" effect in the water
# Objects moving through water create ripples that affect nearby objects

@export var disturbance_strength: float = 100.0
@export var disturbance_radius: float = 200.0
@export var decay_rate: float = 0.9

var current_velocity: Vector2 = Vector2.ZERO
var tracked_body: RigidBody2D = null

func _ready():
	# Set up the collision shape to match disturbance radius
	monitoring = true
	monitorable = false
	
	var disturbance = $WaterDisturbance
	if disturbance:
		disturbance.track_object(self)

func track_object(body: RigidBody2D):
	"""Attach this to a moving object to create disturbance based on its velocity"""
	tracked_body = body
	
	# Position the disturbance at the object
	if body:
		global_position = body.global_position

func _physics_process(delta):
	# Update position if tracking an object
	if tracked_body and is_instance_valid(tracked_body):
		global_position = tracked_body.global_position
		current_velocity = tracked_body.linear_velocity
	
	# Decay the disturbance over time
	current_velocity *= decay_rate
	
	# Apply force to nearby objects
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody2D and body != tracked_body:
			apply_water_force(body)

func apply_water_force(body: RigidBody2D):
	# Calculate distance and falloff
	var distance = global_position.distance_to(body.global_position)
	if distance > disturbance_radius:
		return
	
	# Force falls off with distance (inverse square-ish)
	var falloff = 1.0 - (distance / disturbance_radius)
	falloff = falloff * falloff  # Square for more dramatic falloff
	
	# Direction from disturbance source to body
	var direction = (body.global_position - global_position).normalized()
	
	# Force based on the velocity of the disturbance source
	var force = direction * current_velocity.length() * disturbance_strength * falloff
	
	body.apply_central_force(force)

func create_manual_disturbance(velocity: Vector2):
	"""Create a disturbance without tracking an object"""
	current_velocity = velocity
