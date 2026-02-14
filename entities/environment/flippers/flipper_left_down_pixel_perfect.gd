extends FlipperBasePixelPerfect
class_name FlipperLeftDownPixelPerfect

@export var rest_angle_degrees: float = -30.0
@export var flip_angle_degrees: float = 60.0

func get_rest_angle() -> float:
	return deg_to_rad(rest_angle_degrees)

func get_flip_angle() -> float:
	return deg_to_rad(rest_angle_degrees + flip_angle_degrees)
