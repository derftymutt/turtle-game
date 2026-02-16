extends FlipperBase
class_name FlipperRightDown

## Right-side flipper that rotates counter-clockwise (downward into ocean)
## Typical use: Right side of play field, pushing ball down/left
## Rest position: Angled up-right
## Flip position: Rotates counter-clockwise to push ball deeper

@export var rest_angle_degrees: float = 30.0  # Resting position (up-right angle)
@export var flip_angle_degrees: float = 60.0  # How many degrees to rotate when flipping


func get_rest_angle() -> float:
	"""Return rest position in radians"""
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	"""Return active flip position in radians - rotates COUNTER-CLOCKWISE (subtracts from rest angle)"""
	return deg_to_rad(rest_angle_degrees - flip_angle_degrees)
