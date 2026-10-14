class_name SpitSplatter
extends Node2D

## A few green specks that bounce off whatever a spit bullet hits.
## Built in code: SpitSplatter.spawn(parent, point, incoming_dir, normal, texture).

const MIN_SPECKS: int = 4
const MAX_SPECKS: int = 7
const MIN_SPEED: float = 45.0
const MAX_SPEED: float = 120.0
const SPREAD_DEG: float = 65.0  # cone half-angle around the bounce direction
const GRAVITY: float = 260.0
const DRAG: float = 0.9  # per-tick velocity multiply (via GameSettings.drag_step)
const MIN_LIFE: float = 0.22
const MAX_LIFE: float = 0.42
const FADE_FRACTION: float = 0.4  # last part of each speck's life fades out

const FALLBACK_COLORS: Array[Color] = [
	Color("3f8f3a"), Color("6cc24a"), Color("a6e36b"),
]

## Opaque colours of each bullet texture, read once so the specks match the spit
static var _palette_cache: Dictionary = {}

var _specks: Array[Dictionary] = []


static func spawn(parent: Node, point: Vector2, incoming_dir: Vector2, normal: Vector2,
		texture: Texture2D = null) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var splatter := SpitSplatter.new()
	splatter.global_position = point
	splatter.z_index = 5
	splatter._init_specks(incoming_dir, normal, _palette_for(texture))
	parent.add_child(splatter)


static func _palette_for(texture: Texture2D) -> Array[Color]:
	if texture == null:
		return FALLBACK_COLORS
	if _palette_cache.has(texture):
		return _palette_cache[texture]
	var colors: Array[Color] = []
	var image := texture.get_image()
	if image:
		if image.is_compressed():
			image.decompress()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a > 0.5:
					c.a = 1.0
					if not colors.has(c):
						colors.append(c)
	if colors.is_empty():
		colors = FALLBACK_COLORS
	_palette_cache[texture] = colors
	return colors


func _init_specks(incoming_dir: Vector2, normal: Vector2, palette: Array[Color]) -> void:
	var dir := incoming_dir.normalized() if incoming_dir.length() > 0.01 else Vector2.LEFT
	var n := normal.normalized() if normal.length() > 0.01 else -dir
	# Bounce = reflect off the surface, leaned toward the normal so it splashes back out
	var bounce := dir.bounce(n)
	if bounce.dot(n) < 0.0:
		bounce = n
	bounce = (bounce + n * 0.6).normalized()

	for i in randi_range(MIN_SPECKS, MAX_SPECKS):
		var angle := deg_to_rad(randf_range(-SPREAD_DEG, SPREAD_DEG))
		var life := randf_range(MIN_LIFE, MAX_LIFE)
		_specks.append({
			"pos": n * 1.5,
			"vel": bounce.rotated(angle) * randf_range(MIN_SPEED, MAX_SPEED),
			"life": life,
			"max_life": life,
			"size": 2.0 if randf() < 0.3 else 1.0,
			"color": palette.pick_random(),
		})


func _process(delta: float) -> void:
	var drag := GameSettings.drag_step(DRAG, delta)
	var alive := 0
	for s in _specks:
		if s.life <= 0.0:
			continue
		s.life -= delta
		s.vel = s.vel * drag + Vector2(0.0, GRAVITY * delta)
		s.pos += s.vel * delta
		if s.life > 0.0:
			alive += 1
	if alive == 0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for s in _specks:
		if s.life <= 0.0:
			continue
		var c: Color = s.color
		c.a = clampf(s.life / (s.max_life * FADE_FRACTION), 0.0, 1.0)
		var size: float = s.size
		var p: Vector2 = s.pos.round() - Vector2(size, size) * 0.5
		draw_rect(Rect2(p, Vector2(size, size)), c)
