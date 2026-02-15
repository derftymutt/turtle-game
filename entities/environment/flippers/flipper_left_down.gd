extends FlipperBasePixelPerfect
class_name FlipperLeftDown

## Left-side flipper that rotates clockwise (downward into ocean)
## Typical use: Left side of play field, pushing ball down/right
## Rest position: Angled up-left
## Flip position: Rotates clockwise to push ball deeper

@export var rest_angle_degrees: float = -30.0  # Resting position (up-left angle)
@export var flip_angle_degrees: float = 60.0  # How many degrees to rotate when flipping


func get_rest_angle() -> float:
	"""Return rest position in radians"""
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	"""Return active flip position in radians - rotates CLOCKWISE (adds to rest angle)"""
	return deg_to_rad(rest_angle_degrees + flip_angle_degrees)
