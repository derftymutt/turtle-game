extends RefCounted
class_name HeartsDisplay

## Heart health display — built programmatically with plain Label nodes ("♥")
## so the icon can be swapped for a sprite later. Owns its heart Labels for
## its entire lifetime once built via build(); lives inside the scene's
## HealthContainer HBox, whose old fluid-bar children are hidden at build time.

const HEART_FULL_COLOR := Color(0.30, 0.85, 0.35)
const HEART_EMPTY_COLOR := Color(0.24, 0.24, 0.26)

const BLINK_PERIOD_MSEC: int = 200
const BLINK_LOW_ALPHA: float = 0.25

var current: int = 7
var max_hearts: int = 7
var blinking: bool = false

var _labels: Array = []

## Retires the scene's old fluid health bar (TextureProgressBar + meter icon)
## and builds `hearts_max` heart Label icons into `container`.
func build(container: Control, hearts_max: int = 7) -> void:
	max_hearts = hearts_max
	if not container:
		return
	for child in container.get_children():
		child.visible = false
		child.queue_free()

	container.add_theme_constant_override("separation", 1)

	var heart_font: Font = load("res://assets/fonts/BoldPixels.ttf")
	for i in max_hearts:
		var l := Label.new()
		l.text = "♥"  # ♥ BLACK HEART SUIT — swap this Label for a sprite later
		if heart_font:
			l.add_theme_font_override("font", heart_font)
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", HEART_FULL_COLOR)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		container.add_child(l)
		_labels.append(l)

## Update the heart icons. `hearts_current` / `hearts_max` come from TurtlePlayer.
func update(hearts_current: int, hearts_max_in: int = 7) -> void:
	current = hearts_current
	max_hearts = hearts_max_in
	for i in _labels.size():
		var l: Label = _labels[i]
		l.visible = i < hearts_max_in
		l.add_theme_color_override(
			"font_color",
			HEART_FULL_COLOR if i < hearts_current else HEART_EMPTY_COLOR
		)

## Blink the heart icons for the duration of an active invincibility powerup
func set_blinking(active: bool) -> void:
	blinking = active
	if not active:
		for l in _labels:
			l.modulate.a = 1.0

## Called every frame from HUD._process() — applied last so it wins over any
## other color-coding for the frame it's active, same as the original.
func process() -> void:
	if not blinking or _labels.is_empty():
		return
	var blink_on := int(Time.get_ticks_msec() / BLINK_PERIOD_MSEC) % 2 == 0
	var a := 1.0 if blink_on else BLINK_LOW_ALPHA
	for l in _labels:
		l.modulate.a = a
