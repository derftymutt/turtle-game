extends FlipperBasePixelPerfect
class_name FlipperLeftDownPixelPerfectDebug

## Debug version to diagnose issues

@export var rest_angle_degrees: float = -30.0
@export var flip_angle_degrees: float = 60.0  # Using 60 for cleaner math
@export var enable_debug_print: bool = true


func get_rest_angle() -> float:
	return deg_to_rad(rest_angle_degrees)


func get_flip_angle() -> float:
	return deg_to_rad(rest_angle_degrees + flip_angle_degrees)


func _physics_process(delta):
	super._physics_process(delta)
	
	if enable_debug_print and Engine.get_physics_frames() % 30 == 0:  # Print every 30 frames
		print("=== FLIPPER DEBUG ===")
		#print("Current angle: %.1f°" % rad_to_deg(current_angle))
		#print("Target angle: %.1f°" % rad_to_deg(target_angle))
		#print("Sprite frame: %d / %d" % [animated_sprite.frame if animated_sprite else -1, total_frames - 1])
		print("Is flipping: %s" % is_flipping)
		print("Angular velocity: %.2f" % angular_velocity)
		
		if collision_shape:
			print("Collision rotation: %.1f°" % rad_to_deg(collision_shape.rotation))
			print("Collision position: %s" % collision_shape.position)
			print("Collision disabled: %s" % collision_shape.disabled)
		
		print("====================")
