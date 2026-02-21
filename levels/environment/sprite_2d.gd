extends Sprite2D

func _ready() -> void:
	var viewport_size = get_viewport_rect().size
	# Sprite2D draws from center, so position at screen center
	position = viewport_size / 2.0
	# Scale to fill viewport exactly
	var texture_size = texture.get_size()
	scale = Vector2(
		viewport_size.x / texture_size.x,
		viewport_size.y / texture_size.y
	)
