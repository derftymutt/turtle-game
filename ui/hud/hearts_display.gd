extends RefCounted
class_name HeartsDisplay

## Heart health display — built programmatically with plain Label nodes ("♥")
## so the icon can be swapped for a sprite later. Owns its heart Labels for
## its entire lifetime once built via build(); lives inside the scene's
## HealthContainer HBox, whose old fluid-bar children are hidden at build time.
##
## Rainbow hearts (GameManager.rainbow_heart_count(), the rightmost icons) are
## worth 2 HP: drawn with rainbow_heart.gdshader, which empties their right
## half first.

const HEART_FULL_COLOR := Color(0.30, 0.85, 0.35)
const HEART_EMPTY_COLOR := Color(0.24, 0.24, 0.26)

const BLINK_PERIOD_MSEC: int = 200
const _RAINBOW_HEART_SHADER = preload("res://ui/hud/shaders/rainbow_heart.gdshader")
const BLINK_LOW_ALPHA: float = 0.25

var current: int = 7
var max_hearts: int = 7
var blinking: bool = false

var _labels: Array = []
## One material per heart icon, created when that icon becomes a rainbow heart
var _rainbow_materials: Dictionary = {}

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

## Update the heart icons. `hearts_current` (HP) / `hearts_max` (icons) come
## from TurtlePlayer. HP fills the icons left to right; a rainbow icon holds 2.
func update(hearts_current: int, hearts_max_in: int = 7) -> void:
	current = hearts_current
	max_hearts = hearts_max_in
	var start := 0
	for i in _labels.size():
		var l: Label = _labels[i]
		l.visible = i < hearts_max_in
		var cap := GameManager.heart_capacity(i)
		var held := clampi(hearts_current - start, 0, cap)
		start += cap
		if cap == 2:
			var mat := _rainbow_material(i)
			l.material = mat
			mat.set_shader_parameter("fill", float(held) / cap)
			l.add_theme_color_override("font_color", Color.WHITE)
		else:
			l.material = null
			l.add_theme_color_override("font_color", HEART_FULL_COLOR if held > 0 else HEART_EMPTY_COLOR)

func _rainbow_material(i: int) -> ShaderMaterial:
	if not _rainbow_materials.has(i):
		var mat := ShaderMaterial.new()
		mat.shader = _RAINBOW_HEART_SHADER
		mat.set_shader_parameter("empty_color", HEART_EMPTY_COLOR)
		_rainbow_materials[i] = mat
	return _rainbow_materials[i]

## A small pixel-art rainbow heart (black outline, seven bands) — for the
## bonus rainbow level summary's "gained!" line.
static func rainbow_heart_texture() -> ImageTexture:
	var shape: Array[String] = [
		".XX...XX.",
		"XXXX.XXXX",
		"XXXXXXXXX",
		"XXXXXXXXX",
		".XXXXXXX.",
		"..XXXXX..",
		"...XXX...",
		"....X....",
	]
	var w := shape[0].length() + 2
	var h := shape.size() + 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var filled := func(x: int, y: int) -> bool:
		return y >= 0 and y < shape.size() and x >= 0 and x < shape[0].length() and shape[y][x] == "X"
	for y in h:
		for x in w:
			if filled.call(x - 1, y - 1):
				var band := mini(int(float(y - 1) / shape.size() * 7.0), 6)
				img.set_pixel(x, y, RainbowFish.COLORS[band])
			else:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if filled.call(x - 1 + d.x, y - 1 + d.y):
						img.set_pixel(x, y, Color.BLACK)
						break
	return ImageTexture.create_from_image(img)

## Blink the heart icons for the duration of an active invincibility powerup
func set_blinking(active: bool) -> void:
	blinking = active
	if not active:
		for l in _labels:
			l.modulate.a = 1.0

## Called every frame from HUD._process() — applied last so it wins over any
## other color-coding for the frame it's active, same as the original.
func process() -> void:
	# The rainbow shader maps VERTEX to the glyph by the label's size, which
	# isn't known until layout — keep it current
	for i in _rainbow_materials:
		if i < _labels.size():
			(_rainbow_materials[i] as ShaderMaterial).set_shader_parameter("label_size", (_labels[i] as Label).size)
	if not blinking or _labels.is_empty():
		return
	var blink_on := int(Time.get_ticks_msec() / BLINK_PERIOD_MSEC) % 2 == 0
	var a := 1.0 if blink_on else BLINK_LOW_ALPHA
	for l in _labels:
		l.modulate.a = a
