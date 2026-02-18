extends Node2D
class_name Ocean

# Ocean boundaries
@export var surface_y: float = -126.0  # Y position of water surface (15% down from top of screen)
@export var floor_y: float = 180.0  # Y position of ocean floor (bottom of screen)

# Physics properties
@export var water_drag: float = 0.98  # Drag applied to objects in water
@export var air_drag: float = 0.99  # Drag applied to objects in air (less than water)

# Depth zones for buoyancy (adjust these to tune difficulty)
@export_group("Buoyancy Zones")
@export var shallow_depth: float = 100.0  # Shallow zone depth in pixels (0 to 100 below surface)
@export var mid_depth: float = 200.0  # Mid zone depth in pixels (100 to 200 below surface)
@export var shallow_buoyancy: float = 150.0  # INCREASED: Was 100.0 - faster rise in shallow
@export var mid_buoyancy_base: float = 225.0  # INCREASED: Was 175.0 - faster rise in mid
@export var mid_buoyancy_rate: float = 4.0  # INCREASED: Was 3.0 - stronger gradient
@export var deep_buoyancy_base: float = 275.0  # INCREASED: Was 200.0 - stronger deep push
@export var deep_buoyancy_curve: float = 0.10   # INCREASED: Was 0.07 - more exponential growth

# Visual effects
@export_group("Visual Settings")
@export var surface_color: Color = Color(0.055, 1.0, 1.0, 1.0)  # Bright cyan turquoise (#0effff)
@export var shallow_color: Color = Color(0.0, 0.85, 0.95, 1.0)  # Vibrant cyan-blue
@export var mid_color: Color = Color(0.0, 0.6, 1.0, 1.0)  # Bright sky blue
@export var deep_color: Color = Color(0.0, 0.3, 1.0, 1.0)  # True vibrant blue
@export var show_gradient: bool = true  # Toggle ocean gradient rendering
@export var show_debug_zones: bool = false  # Toggle depth zone debug overlay

func _ready():
	add_to_group("ocean")
	queue_redraw()

func _draw():
	if show_gradient:
		draw_ocean_gradient()
	
	if show_debug_zones:
		draw_debug_zones()

func draw_ocean_gradient():
	"""Draw a gradient from surface to ocean floor"""
	var screen_width = 640  # Your game resolution
	var ocean_height = floor_y - surface_y
	
	# Create gradient bands for smooth color transition
	var num_bands = 20  # More bands = smoother gradient
	var band_height = ocean_height / num_bands
	
	for i in range(num_bands):
		var y_start = surface_y + (i * band_height)
		var y_end = y_start + band_height
		var depth_ratio = float(i) / float(num_bands - 1)
		
		# Interpolate between colors based on depth zones
		var band_color: Color
		if depth_ratio < 0.25:
			# Surface to shallow
			var local_ratio = depth_ratio / 0.25
			band_color = surface_color.lerp(shallow_color, local_ratio)
		elif depth_ratio < 0.5:
			# Shallow to mid
			var local_ratio = (depth_ratio - 0.25) / 0.25
			band_color = shallow_color.lerp(mid_color, local_ratio)
		else:
			# Mid to deep
			var local_ratio = (depth_ratio - 0.5) / 0.5
			band_color = mid_color.lerp(deep_color, local_ratio)
		
		# Draw the colored band
		draw_rect(
			Rect2(Vector2(-screen_width, y_start), Vector2(screen_width * 3, band_height)),
			band_color
		)

func draw_debug_zones():
	"""Draw colored zone overlays with boundary lines and labels for development"""
	var w = 640.0
	var left = -w
	var right = w * 2.0
	var band_width = right - left
	
	var shallow_y = surface_y + shallow_depth
	var mid_y = surface_y + mid_depth
	
	# --- Zone tint bands (semi-transparent) ---
	# Shallow zone: surface_y -> shallow_y (green tint)
	draw_rect(
		Rect2(Vector2(left, surface_y), Vector2(band_width, shallow_depth)),
		Color(0.0, 1.0, 0.4, 0.15)
	)
	# Mid zone: shallow_y -> mid_y (yellow tint)
	draw_rect(
		Rect2(Vector2(left, shallow_y), Vector2(band_width, mid_depth - shallow_depth)),
		Color(1.0, 0.9, 0.0, 0.15)
	)
	# Deep zone: mid_y -> floor_y (red tint)
	draw_rect(
		Rect2(Vector2(left, mid_y), Vector2(band_width, floor_y - mid_y)),
		Color(1.0, 0.2, 0.0, 0.15)
	)
	
	# --- Boundary lines ---
	# Water surface (bright cyan, thick)
	draw_line(Vector2(left, surface_y), Vector2(right, surface_y), Color.CYAN, 3.0)
	# Shallow/mid boundary (yellow)
	draw_line(Vector2(left, shallow_y), Vector2(right, shallow_y), Color.YELLOW, 2.0)
	# Mid/deep boundary (orange-red)
	draw_line(Vector2(left, mid_y), Vector2(right, mid_y), Color.ORANGE_RED, 2.0)
	# Ocean floor (white, dashed via short segments)
	draw_line(Vector2(left, floor_y), Vector2(right, floor_y), Color.WHITE, 2.0)
	
	# --- Zone labels (drawn at a fixed x, centered in each zone) ---
	var label_x = -200.0
	var font_size = 12
	
	draw_string(ThemeDB.fallback_font, Vector2(label_x, surface_y - 6.0),
		"SURFACE  y=%.0f" % surface_y, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.CYAN)
	
	draw_string(ThemeDB.fallback_font, Vector2(label_x, surface_y + shallow_depth * 0.5),
		"SHALLOW  (0 – %.0fpx)" % shallow_depth, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.2, 1.0, 0.5))
	
	draw_string(ThemeDB.fallback_font, Vector2(label_x, shallow_y + (mid_depth - shallow_depth) * 0.5),
		"MID  (%.0f – %.0fpx)" % [shallow_depth, mid_depth], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.YELLOW)
	
	draw_string(ThemeDB.fallback_font, Vector2(label_x, mid_y + (floor_y - mid_y) * 0.5),
		"DEEP  (%.0fpx+)" % mid_depth, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.ORANGE_RED)

func is_in_water(global_pos: Vector2) -> bool:
	"""Check if a position is below the water surface"""
	return global_pos.y > surface_y

func is_in_air(global_pos: Vector2) -> bool:
	"""Check if a position is above the water surface"""
	return global_pos.y <= surface_y

func get_depth(global_pos: Vector2) -> float:
	"""Returns depth below surface (negative = above water, 0 = at surface, positive = deeper)"""
	return global_pos.y - surface_y

func get_depth_zone(depth: float) -> String:
	"""Returns which zone the depth is in: 'air', 'shallow', 'mid', or 'deep'"""
	if depth <= 0:
		return "air"
	elif depth < shallow_depth:
		return "shallow"
	elif depth < mid_depth:
		return "mid"
	else:
		return "deep"

func calculate_buoyancy_force(depth: float, object_mass: float = 1.0) -> float:
	"""
	Calculate upward buoyancy force based on depth.
	Returns force value (positive = upward, negative = downward).
	Scales with mass so heavier objects feel appropriate force.
	
	Now uses NEGATIVE depth (above water) for smooth transition at surface.
	"""
	var buoyancy: float
	
	# Allow negative depth for objects above water
	# This creates smooth transition at the surface
	if depth < -100.0:
		# Far above water - full gravity
		return -980.0 * object_mass
	elif depth < 0:
		# Splash zone - gentle downward pull allows jumping with momentum
		var transition = depth / -50.0  # 0.0 at surface, 1.0 at -50 pixels above (was -20)
		return lerp(0.0, -800.0, transition) * object_mass  # Even gentler pull (was -200)
		#return 0.0
	elif depth < 10.0:
		# At surface - gentle buoyancy that ramps up
		# Smoothly ramps from 0 at surface to ~980 at 10 pixels deep (matches gravity)
		var surface_factor = depth / 10.0  # 0.0 to 1.0
		buoyancy = lerp(0.0, 20.0, surface_factor)
	elif depth < shallow_depth:
		# Shallow zone - minimal buoyancy, easy to control
		buoyancy = shallow_buoyancy
	elif depth < mid_depth:
		# Mid zone - moderate buoyancy that increases with depth
		var depth_in_zone = depth - shallow_depth
		buoyancy = mid_buoyancy_base + (depth_in_zone * mid_buoyancy_rate)
	else:
		# Deep zone - STRONG buoyancy with exponential growth
		var depth_in_zone = depth - mid_depth
		buoyancy = deep_buoyancy_base + (depth_in_zone * depth_in_zone * deep_buoyancy_curve)
	
	# Scale by mass - heavier objects need more force to feel same buoyancy
	return buoyancy * object_mass

func get_drag_coefficient(global_pos: Vector2) -> float:
	"""Returns the appropriate drag for the position (water vs air)"""
	if is_in_water(global_pos):
		return water_drag
	else:
		return air_drag

func apply_ocean_physics(body: RigidBody2D, delta: float):
	"""
	Convenience function that applies all ocean physics to a RigidBody2D.
	Call this from the object's _physics_process if you want automatic handling.
	"""
	if not body:
		return
	
	var depth = get_depth(body.global_position)
	
	if depth > 0:
		# Object is underwater
		# Apply buoyancy (upward force)
		var buoyancy = calculate_buoyancy_force(depth, body.mass)
		body.apply_central_force(Vector2(0, -buoyancy))
		
		# Apply water drag
		body.linear_velocity *= water_drag
	else:
		# Object is in air
		# Apply normal gravity (let Godot handle it)
		# Just apply air drag
		body.linear_velocity *= air_drag

func get_pressure_tint(depth: float) -> Color:
	"""
	Returns a color tint based on depth for visual effects.
	Useful for shading sprites darker as they go deeper.
	"""
	if depth <= 0:
		return Color.WHITE  # No tint in air
	
	var depth_ratio = clamp(depth / mid_depth, 0.0, 1.0)
	return surface_color.lerp(deep_color, depth_ratio)

# Debug helpers
func print_depth_info(global_pos: Vector2):
	"""Debug function to print depth information"""
	var depth = get_depth(global_pos)
	var zone = get_depth_zone(depth)
	var buoyancy = calculate_buoyancy_force(depth, 1.0)
	print("Position: ", global_pos)
	print("Depth: ", depth, " Zone: ", zone, " Buoyancy: ", buoyancy)
