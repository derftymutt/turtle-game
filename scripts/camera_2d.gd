extends Camera2D

@export var follow_target: Node2D  # Turtle
@export var ocean_surface_y: float = -126.0
@export var ocean_floor_y: float = 180.0

# Vertical (sky/ocean) settings
@export var sky_zoom_threshold: float = 100.0  # Above surface
@export var sky_zoom: Vector2 = Vector2(0.5, 0.5)  # Zoom out 2x
@export var normal_zoom: Vector2 = Vector2(1.0, 1.0)
@export var vertical_zoom_speed: float = 3.0

# Horizontal (side-scrolling) settings
@export var horizontal_follow_enabled: bool = true
@export var horizontal_offset: float = 100.0  # Turtle stays this far from center
@export var horizontal_smoothing: float = 5.0
@export var horizontal_deadzone: float = 50.0  # Turtle can move this much before camera follows

# Camera bounds (optional - set these to limit how far camera can go)
@export var min_camera_x: float = -1000.0
@export var max_camera_x: float = 5000.0

var target_zoom: Vector2
var target_position: Vector2

func _ready():
	zoom = normal_zoom
	target_zoom = normal_zoom
	target_position = position

func _process(delta):
	if not follow_target:
		return
	
	var turtle_pos = follow_target.global_position
	var distance_above_surface = ocean_surface_y - turtle_pos.y
	
	# === VERTICAL AXIS (Sky/Ocean) ===
	if distance_above_surface > sky_zoom_threshold:
		# TURTLE IN SKY - zoom out dramatically
		target_zoom = sky_zoom
		# Center vertically between turtle and ocean floor
		target_position.y = (turtle_pos.y + ocean_floor_y) / 2.0
	else:
		# TURTLE IN OCEAN - normal zoom, locked Y
		target_zoom = normal_zoom
		target_position.y = 0.0  # Your default camera Y
	
	# === HORIZONTAL AXIS (Side-scrolling) ===
	if horizontal_follow_enabled:
		var camera_to_turtle_x = turtle_pos.x - global_position.x
		
		# Only follow if turtle moves outside deadzone
		if abs(camera_to_turtle_x) > horizontal_deadzone:
			# Follow with offset (turtle stays offset from center)
			if camera_to_turtle_x > 0:
				target_position.x = turtle_pos.x - horizontal_offset
			else:
				target_position.x = turtle_pos.x + horizontal_offset
			
			# Clamp to bounds
			target_position.x = clamp(target_position.x, min_camera_x, max_camera_x)
	
	# === SMOOTH TRANSITIONS ===
	zoom = zoom.lerp(target_zoom, vertical_zoom_speed * delta)
	position = position.lerp(target_position, horizontal_smoothing * delta)
