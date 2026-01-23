extends Piranha
class_name SuperPiranha

## Elite piranha variant with increased health and visual distinction
## Inherits all behavior from base Piranha class

func _enemy_ready():
	# Call parent setup first
	super._enemy_ready()
	
	# Override health for super variant
	max_health = 30.0
	current_health = max_health
	
	# Optional: Slightly increased damage for tougher enemy
	contact_damage = 20.0
	
	# Optional: Visual distinction (if using AnimatedSprite2D)
	if sprite and sprite is AnimatedSprite2D:
		# You can set a different animation or modulate color
		sprite.play("default")
	elif sprite:
		# For regular Sprite2D, just tint it
		sprite.modulate = Color(1.2, 0.5, 0.5)

## Override die() to show this was a tougher enemy
func die():
	# Optional: Different death effect for super piranhas
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out with red flash
	tween.tween_property(self, "modulate", Color(2.0, 0.3, 0.3, 0.0), 0.8)
	
	# Spin while dying (faster than regular)
	tween.tween_property(self, "rotation", rotation + TAU * 2, 0.8)
	
	# Float upward
	tween.tween_property(self, "global_position:y", global_position.y - 100, 0.8)
	
	tween.finished.connect(queue_free)
	
	# Disable collision while dying
	collision_layer = 0
	collision_mask = 0
