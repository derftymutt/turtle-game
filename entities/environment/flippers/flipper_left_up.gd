extends FlipperBase
class_name FlipperLeftUp

## Left-side flipper that rotates clockwise (upward toward sky)
## Typical use: Left side of play field, launching ball upward (traditional pinball)
## Rest position: Angled down-left
## Flip position: Rotates clockwise to launch ball up/right

@export var rest_angle_degrees: float = 30.0  # Resting position (down-left angle)
@export var flip_angle_degrees: float = 65.0  # How many degrees to rotate when flipping


func get_rest_angle() -> float:
	"""Return rest position in radians"""
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	"""Return active flip position in radians - rotates CLOCKWISE (subtracts from rest angle)"""
	return deg_to_rad(rest_angle_degrees - flip_angle_degrees)
