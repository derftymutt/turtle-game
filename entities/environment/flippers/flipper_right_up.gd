extends FlipperBase
class_name FlipperRightUp

## Right-side flipper that rotates counter-clockwise (upward toward sky)
## Typical use: Right side of play field, launching ball upward (traditional pinball)
## Rest position: Angled down-right
## Flip position: Rotates counter-clockwise to launch ball up/left

@export var rest_angle_degrees: float = -30.0  # Resting position (down-right angle)
@export var flip_angle_degrees: float = 65.0  # How many degrees to rotate when flipping


func get_rest_angle() -> float:
	"""Return rest position in radians"""
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	"""Return active flip position in radians - rotates COUNTER-CLOCKWISE (adds to rest angle)"""
	return deg_to_rad(rest_angle_degrees + flip_angle_degrees)
