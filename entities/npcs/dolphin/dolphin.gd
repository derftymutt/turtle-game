extends Node2D
class_name Dolphin

# ============================================================
# MOVEMENT
# ============================================================
@export_group("Movement")
## Horizontal swim speed in pixels/sec
@export var swim_speed: float = 90.0
## 1 = left-to-right, -1 = right-to-left (set by spawner)
@export var swim_direction: int = 1
## Vertical oscillation amplitude (pixels)
@export var swim_amplitude: float = 9.0
## Oscillation cycles per second
@export var swim_frequency: float = 1.6

# ============================================================
# UFO DROP
# ============================================================
@export_group("UFO Drop")
@export var community_ufo_scene: PackedScene
## World X position at which to drop the UFO (set by spawner before _ready)
@export var drop_x: float = 0.0
## World X at which the dolphin leaves the scene
@export var exit_x: float = 9999.0
## Vertical offset of the dropped UFO relative to the dolphin at drop time
@export var ufo_drop_offset: Vector2 = Vector2(0.0, 20.0)
## How fast the dolphin accelerates away after dropping (pixels/sec added)
@export var post_drop_speed_boost: float = 40.0

# ============================================================
# VISUAL
# ============================================================
@export_group("Visual")
@export var body_color: Color = Color(0.28, 0.52, 0.85)
@export var belly_color: Color = Color(0.82, 0.93, 1.0)
@export var eye_color: Color = Color(0.05, 0.05, 0.1)
## Color of the carried-UFO placeholder
@export var carried_ufo_color: Color = Color(0.6, 1.0, 2.0, 0.85)
@export var carried_ufo_radius: float = 12.0

# ============================================================
# INTERNAL STATE
# ============================================================

var _has_dropped: bool = false
var _swim_time: float = 0.0
var _current_speed: float = 0.0

func _ready():
	_current_speed = swim_speed
	# Flip sprite to match direction (dolphin faces right by default)
	scale.x = float(swim_direction)
	add_to_group("dolphins")

func _process(delta: float):
	_swim_time += delta

	# Horizontal movement
	global_position.x += _current_speed * swim_direction * delta

	# Vertical sinusoidal swim
	global_position.y += cos(_swim_time * swim_frequency * TAU) * swim_amplitude * delta

	# Drop UFO at the configured world X
	if not _has_dropped and _should_drop():
		_drop_ufo()

	# Leave scene once past exit X
	if _past_exit():
		queue_free()

	queue_redraw()

func _should_drop() -> bool:
	if swim_direction > 0:
		return global_position.x >= drop_x
	else:
		return global_position.x <= drop_x

func _past_exit() -> bool:
	if swim_direction > 0:
		return global_position.x >= exit_x
	else:
		return global_position.x <= exit_x

func _drop_ufo():
	_has_dropped = true
	_current_speed += post_drop_speed_boost

	if not community_ufo_scene:
		push_warning("Dolphin: community_ufo_scene not assigned!")
		return

	var ufo = community_ufo_scene.instantiate()
	get_parent().add_child(ufo)
	ufo.global_position = global_position + ufo_drop_offset

	# Give the UFO a small downward nudge so it starts sinking immediately
	ufo.apply_central_impulse(Vector2(0.0, 30.0))

# ──────────────────────────────────────────────────────────────────────────────
# PROCEDURAL DOLPHIN DRAWING (placeholder until real sprites are added)
# All coordinates are in the dolphin's local space; swim_direction scale
# handles mirroring automatically.
# ──────────────────────────────────────────────────────────────────────────────

func _draw():
	var t = _swim_time
	var tail_wag = sin(t * swim_frequency * TAU) * 6.0  # Tail oscillation

	# — Body (main ellipse) —
	_draw_ellipse(Vector2(-4, 0), Vector2(26, 12), body_color)

	# — Belly (lighter underside) —
	_draw_ellipse(Vector2(-2, 3), Vector2(18, 7), belly_color)

	# — Snout / rostrum —
	var snout = PackedVector2Array([
		Vector2(22, -2), Vector2(38, 1), Vector2(22, 4)
	])
	draw_colored_polygon(snout, body_color)

	# — Dorsal fin —
	var dorsal = PackedVector2Array([
		Vector2(2, -12), Vector2(8, -22), Vector2(14, -12)
	])
	draw_colored_polygon(dorsal, body_color)

	# — Tail flukes (wag with swim cycle) —
	var tail_base_x = -30.0
	var left_fluke = PackedVector2Array([
		Vector2(tail_base_x, 0),
		Vector2(tail_base_x - 16, tail_wag - 10),
		Vector2(tail_base_x - 8, tail_wag),
	])
	var right_fluke = PackedVector2Array([
		Vector2(tail_base_x, 0),
		Vector2(tail_base_x - 16, tail_wag + 10),
		Vector2(tail_base_x - 8, tail_wag),
	])
	draw_colored_polygon(left_fluke, body_color)
	draw_colored_polygon(right_fluke, body_color)

	# — Pectoral fin —
	var pec = PackedVector2Array([
		Vector2(10, 4), Vector2(20, 18), Vector2(4, 12)
	])
	draw_colored_polygon(pec, body_color)

	# — Eye —
	draw_circle(Vector2(20, -3), 3.0, eye_color)
	draw_circle(Vector2(20.8, -3.5), 1.0, Color.WHITE)

	# — Carried UFO placeholder (only before drop) —
	if not _has_dropped:
		var ufo_local = Vector2(2, -carried_ufo_radius - 14)
		# Saucer body
		_draw_ellipse(ufo_local, Vector2(carried_ufo_radius, carried_ufo_radius * 0.35),
			carried_ufo_color)
		# Dome
		var dome: PackedVector2Array = []
		for i in range(9):
			var a = PI + (i / 8.0) * PI
			dome.append(ufo_local + Vector2(cos(a) * carried_ufo_radius * 0.55,
				sin(a) * carried_ufo_radius * 0.48))
		if dome.size() >= 3:
			draw_colored_polygon(dome, Color(0.7, 1.0, 0.7, 0.5))

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segs: int = 20):
	var pts: PackedVector2Array = []
	for i in range(segs):
		var a = (i / float(segs)) * TAU
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)
