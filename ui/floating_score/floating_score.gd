extends Node2D
class_name FloatingScore

## Brief floating "+N" label that rises and fades at a world-space position.
## Instantiate via GameManager.spawn_floating_score(position, amount).

func setup(amount: int) -> void:
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(60, 16)
	label.position = Vector2(-30, -14)
	add_child(label)

	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 36, 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.65).set_delay(0.45)
	tween.tween_callback(queue_free)
