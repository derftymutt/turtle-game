@tool
extends Area2D
class_name RotatingLauncher

## ROTATING LAUNCHER — a comet. Passive pinball element: touching it pulls the
## turtle inside, its aim then spins, and the launch button (or `hold_seconds`
## running out) fires the comet off with the turtle in it. Works like a
## captured PufferFish, but it is not an enemy: it never hurts the turtle and
## needs no super speed to enter.
##
## Life cycle:
##   WANDERING — drifts slowly around its home (where it sits in the scene).
##   HOLDING   — the turtle is inside; the comet holds still and its aim spins.
##   FLYING    — launched. The turtle is back in the physics world, flying on
##               its own; the comet rides along as a cloud around it, tail
##               streaming behind.
##   GONE      — the flight ended and the comet evaporated. After
##               `respawn_seconds` it rematerialises around its home.
##
## Reuses the turtle's puffer capture (TurtlePlayer.enter_puffer() /
## exit_puffer()): while HOLDING the turtle is hidden, invulnerable and out of
## the physics world, and it drives update_capture() from its own
## _physics_process.
##
## SCENE SETUP: the Area2D's collision layer / mask are set in the Inspector
## (layer 0, mask = Player).
##
## ART: comet.png — frames side by side, each 60×30: a 30px head (the circle,
## left) with the tail to its right. The sheet is split in code into the head,
## which never rotates, and the tail, which swings around the head to sit
## opposite the launch direction (or, while wandering, opposite the way the
## comet is drifting). See _build_frames().

@export_group("Shape")
## Catch radius, in pixels (the head art is 30px across). The
## CollisionShape2D follows it.
@export var radius: float = 15.0:
	set(value):
		radius = value
		_sync_shape()
		queue_redraw()
## Direction it aims in the editor and when first caught, in degrees
## (0 = right, -90 = up)
@export var rest_angle_degrees: float = -90.0:
	set(value):
		rest_angle_degrees = value
		if _state == State.WANDERING:
			_angle = deg_to_rad(value)
			_tail_angle = _angle + PI
			_apply_visuals()

@export_group("Wander")
## How far from home it drifts, sideways / up and down (pixels). The editor
## shows this as a faint outline.
@export var wander_range: Vector2 = Vector2(28.0, 18.0):
	set(value):
		wander_range = value
		queue_redraw()
## Seconds for one lazy loop around home
@export var wander_period: float = 9.0

@export_group("Roam")
## A roaming comet has no home: it drifts all over `roam_area`, and after a
## flight it rematerialises wherever it evaporated. Wander settings are
## ignored.
@export var roams: bool = false:
	set(value):
		roams = value
		queue_redraw()
## Where it may roam, in level coordinates. The editor outlines it.
@export var roam_area: Rect2 = Rect2(-290.0, 80.0, 540.0, 2400.0):
	set(value):
		roam_area = value
		queue_redraw()
## Drift speed, in pixels per second
@export var roam_speed: float = 40.0
## How sharply its course meanders (radians per second, at most)
@export var roam_turn_rate: float = 0.7

@export_group("Launch")
@export var launch_action: String = "ufo_windup"
## Speed the turtle leaves at (a full flipper hit is ~900)
@export var launch_speed: float = 900.0
## Aim spin speed while the turtle is inside, in turns per second
@export var spin_turns_per_second: float = 1.0
## The turtle is launched on its own after this long (0 = only on the button)
@export var hold_seconds: float = 3.0
## Launch presses are ignored this long after entering
@export var launch_input_grace: float = 0.15

@export_group("Flight")
## The flight is over once the turtle slows below this…
@export var flight_end_speed: float = 160.0
## …or stops heading the way it was launched (a bounce), or after this long
@export var max_flight_seconds: float = 1.5
## Seconds after evaporating before it rematerialises at home
@export var respawn_seconds: float = 5.0

@export_group("Visual")
## Frames per second of the two-frame shimmer
@export var animation_fps: float = 5.0
## How quickly the tail swings round to follow a change of direction while
## wandering (higher = snappier)
@export var tail_turn_speed: float = 5.0
## Blinking dots ahead of the comet while the turtle is inside
@export var show_aim_dots: bool = true
@export var aim_color: Color = Color(1.0, 0.9, 0.3, 1.0)

enum State { WANDERING, HOLDING, FLYING, GONE }
var _state: State = State.WANDERING

const _EVAPORATE_SECONDS := 0.45
const _MATERIALIZE_SECONDS := 0.6
const _SHEET = preload("res://entities/environment/rotating_launcher/comet.png")
const _FRAME_SIZE := Vector2i(60, 30)
const _HEAD_DIAMETER := 30
## Split art, built once and shared by every comet: one texture per frame
static var _head_frames: Array[ImageTexture] = []
static var _tail_frames: Array[ImageTexture] = []

## Direction of the aim / tail, in radians
var _angle: float = -PI * 0.5
var _home: Vector2 = Vector2.ZERO
var _wander_time: float = 0.0
var _passenger: Node2D = null
var _hold_timer: float = 0.0
var _flight_timer: float = 0.0
var _gone_timer: float = 0.0
var _launch_dir: Vector2 = Vector2.UP
var _spin_sign: float = 1.0
## 0 = invisible / evaporated, 1 = fully formed
var _presence: float = 1.0
## Where the tail points (radians) — eased toward opposite the aim / motion
var _tail_angle: float = PI * 0.5
var _last_position: Vector2 = Vector2.ZERO
## Roaming: current course (radians) and the clock behind its meander
var _roam_heading: float = 0.0
var _roam_time: float = 0.0
var _draw_time: float = 0.0

@onready var _tail: Sprite2D = $Tail
@onready var _head: Sprite2D = $Head

func _ready() -> void:
	_angle = deg_to_rad(rest_angle_degrees)
	_tail_angle = _angle + PI
	_sync_shape()
	_build_frames()
	_apply_visuals()
	if Engine.is_editor_hint():
		return
	add_to_group("rotating_launchers")
	_home = global_position
	_last_position = global_position
	# Each comet starts somewhere different on its loop
	_wander_time = randf() * wander_period
	_roam_heading = randf() * TAU
	_roam_time = randf() * 100.0
	body_entered.connect(_on_body_entered)

func _sync_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	# Own shape per instance, so one launcher's radius never resizes another's
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape_node.shape = circle

## Splits each frame of the sheet into a head texture and a tail texture.
## The tail is drawn hugging the right side of the head, so a straight cut
## won't do: a pixel belongs to the head if it mirrors an opaque pixel of the
## head's left half (which the tail never touches). The art has no outline
## where the tail joins on, so the left outline is mirrored across to close
## the circle — otherwise the head would show a gap once the tail swings away.
func _build_frames() -> void:
	if not _head_frames.is_empty():
		return
	var sheet: Image = _SHEET.get_image()
	if sheet == null:
		return
	if sheet.is_compressed():
		sheet.decompress()
	sheet.convert(Image.FORMAT_RGBA8)
	var half: int = _HEAD_DIAMETER / 2
	for f in sheet.get_width() / _FRAME_SIZE.x:
		var frame: Image = sheet.get_region(Rect2i(Vector2i(f * _FRAME_SIZE.x, 0), _FRAME_SIZE))
		var head := Image.create(_HEAD_DIAMETER, _FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		var tail: Image = frame.duplicate()
		for y in _FRAME_SIZE.y:
			# First opaque pixel from the left = the outline on this row
			var edge: int = -1
			for x in half:
				if frame.get_pixel(x, y).a > 0.0:
					edge = x
					break
			if edge < 0:
				continue
			var right_edge: int = _HEAD_DIAMETER - 1 - edge
			for x in range(edge, right_edge + 1):
				var mirrored: int = _HEAD_DIAMETER - 1 - x
				# Outline pixels on the right come from the left side
				var from_left: bool = x >= half and mirrored <= edge + 1 and _is_outline(frame, mirrored, y, edge)
				head.set_pixel(x, y, frame.get_pixel(mirrored if from_left else x, y))
				tail.set_pixel(x, y, Color(0, 0, 0, 0))
		_head_frames.append(ImageTexture.create_from_image(head))
		_tail_frames.append(ImageTexture.create_from_image(tail))

## The outline is the first pixel of a row, plus the one after it where the
## circle's edge is two pixels thick (same colour as the first).
func _is_outline(frame: Image, x: int, y: int, edge: int) -> bool:
	return x == edge or frame.get_pixel(x, y).is_equal_approx(frame.get_pixel(edge, y))

# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	match _state:
		State.WANDERING:
			_presence = minf(1.0, _presence + delta / _MATERIALIZE_SECONDS)
			if roams:
				_roam(delta)
			else:
				_wander_time += delta
				global_position = _home + _wander_offset()
			# Tail trails the drift. Turn faster the faster it's moving, so
			# the slow turnarounds of the loop don't whip it about.
			var drift: Vector2 = (global_position - _last_position) / maxf(delta, 0.0001)
			if drift.length() > 0.5:
				var weight: float = clampf(tail_turn_speed * delta * minf(drift.length() / 12.0, 1.5), 0.0, 1.0)
				_tail_angle = lerp_angle(_tail_angle, (-drift).angle(), weight)
			_last_position = global_position
			# Only catches once fully formed
			if _presence >= 1.0 and not monitoring:
				monitoring = true
		State.FLYING:
			_fly(delta)
		State.GONE:
			_presence = maxf(0.0, _presence - delta / _EVAPORATE_SECONDS)
			_gone_timer -= delta
			if _gone_timer <= 0.0:
				_rematerialize()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_draw_time += delta
	match _state:
		State.HOLDING:
			# Directly opposite the aim, eased in from wherever it was trailing
			_tail_angle = lerp_angle(_tail_angle, _angle + PI, clampf(18.0 * delta, 0.0, 1.0))
		State.FLYING:
			# Follow the turtle every drawn frame, so the comet never lags it
			if is_instance_valid(_passenger):
				global_position = _passenger.global_position
			_tail_angle = lerp_angle(_tail_angle, _angle + PI, clampf(14.0 * delta, 0.0, 1.0))
	_apply_visuals()
	queue_redraw()

## Drifts on a slowly meandering course, turning back in from the edges of
## roam_area. Two out-of-step sines make the meander wander without repeating
## noticeably.
func _roam(delta: float) -> void:
	_roam_time += delta
	_roam_heading += (sin(_roam_time * 0.37) + sin(_roam_time * 0.83 + 1.3)) * 0.5 * roam_turn_rate * delta
	var course := Vector2.from_angle(_roam_heading)
	# Near an edge (or outside): steer back toward the middle of the area
	var margin := 40.0
	var inner := roam_area.grow(-margin)
	if not inner.has_point(global_position):
		var inward: Vector2 = (global_position.clamp(inner.position, inner.end) - global_position).normalized()
		# Quick enough to come about within the margin, whatever the speed
		course = course.lerp(inward, clampf(roam_speed / margin * 3.0 * delta, 0.0, 1.0)).normalized()
		_roam_heading = course.angle()
	global_position = (global_position + course * roam_speed * delta).clamp(roam_area.position, roam_area.end)

## A slow figure-of-eight-ish loop around home.
func _wander_offset() -> Vector2:
	var t: float = _wander_time / maxf(wander_period, 0.1) * TAU
	return Vector2(sin(t) * wander_range.x, sin(t * 2.0 + 0.6) * wander_range.y)

func _on_body_entered(body: Node2D) -> void:
	if _state != State.WANDERING or _presence < 1.0:
		return
	if not body.is_in_group("player") or not body.has_method("enter_puffer"):
		return
	# Read before enter_puffer() zeroes it
	var incoming: Vector2 = body.linear_velocity
	var offset: Vector2 = global_position - body.global_position
	if not body.enter_puffer(self):
		return  # already inside something else
	_passenger = body
	_state = State.HOLDING  # holds still from here: wandering stops
	_hold_timer = 0.0
	# Spin toward the side the turtle came in from
	_spin_sign = 1.0 if incoming.cross(offset) >= 0.0 else -1.0

## Ticked by the turtle every physics frame while it's inside.
func update_capture(turtle: Node2D, delta: float) -> void:
	_angle = wrapf(_angle + _spin_sign * spin_turns_per_second * TAU * delta, -PI, PI)
	turtle.global_position = global_position
	_hold_timer += delta
	var pressed := Input.is_action_just_pressed(launch_action) and _hold_timer >= launch_input_grace
	if pressed or (hold_seconds > 0.0 and _hold_timer >= hold_seconds):
		_launch(turtle)

## The turtle goes back into the physics world at speed; the comet stops
## catching and rides along with it until the flight is over.
func _launch(turtle: Node2D) -> void:
	_launch_dir = Vector2.from_angle(_angle)
	_state = State.FLYING
	_flight_timer = 0.0
	set_deferred("monitoring", false)
	turtle.exit_puffer(global_position, _launch_dir * launch_speed)

func _fly(delta: float) -> void:
	if not is_instance_valid(_passenger):
		_evaporate()
		return
	global_position = _passenger.global_position
	_flight_timer += delta
	var velocity: Vector2 = _passenger.linear_velocity
	if velocity.length() > 1.0:
		_angle = velocity.angle()
	# Captured by something else (a puffer, another comet) counts as landing
	var grabbed: bool = _passenger.get("captor_puffer") != null
	if grabbed or _flight_timer >= max_flight_seconds or velocity.length() < flight_end_speed or velocity.dot(_launch_dir) <= 0.0:
		_evaporate()

func _evaporate() -> void:
	_passenger = null
	_state = State.GONE
	_gone_timer = respawn_seconds

func _rematerialize() -> void:
	_state = State.WANDERING
	_presence = 0.0
	_angle = deg_to_rad(rest_angle_degrees)
	if roams:
		# No home: carries on from wherever the flight ended
		global_position = global_position.clamp(roam_area.position, roam_area.end)
	else:
		global_position = _home + _wander_offset()
	_last_position = global_position

## The turtle is going away without launching (PufferFish API).
func release_captured() -> void:
	if _state == State.HOLDING:
		_evaporate()

func _exit_tree() -> void:
	if _state == State.HOLDING and is_instance_valid(_passenger):
		var turtle := _passenger
		_passenger = null
		turtle.exit_puffer(global_position, Vector2.ZERO)

# ---------------------------------------------------------------------------
# VISUALS
# ---------------------------------------------------------------------------

## Head stays upright; the tail swings around the head's centre. Fading in
## and out (materialise / evaporate) is the whole node's alpha.
func _apply_visuals() -> void:
	if _head == null or _tail == null or _head_frames.is_empty():
		return
	var frame: int = int(_draw_time * animation_fps) % _head_frames.size()
	_head.texture = _head_frames[frame]
	_tail.texture = _tail_frames[frame]
	# The tail art points right (angle 0) from the head
	_tail.rotation = _tail_angle
	modulate.a = _presence
	# Evaporating: swells a little as it fades
	var swell: float = 1.0 + (1.0 - _presence) * 0.35 if _state == State.GONE else 1.0
	_head.scale = Vector2.ONE * swell
	_tail.scale = Vector2.ONE * swell

func _draw() -> void:
	if Engine.is_editor_hint():
		# Where it wanders / roams
		if roams:
			draw_rect(Rect2(roam_area.position - global_position, roam_area.size), Color(1, 1, 1, 0.35), false)
			return
		draw_set_transform(Vector2.ZERO, 0.0, wander_range + Vector2.ONE * radius)
		draw_arc(Vector2.ZERO, 1.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), -1.0)
		draw_set_transform(Vector2.ZERO)
		return
	# Aim: blinking dots out ahead, opposite the tail
	if _state == State.HOLDING and show_aim_dots:
		var dir := Vector2.from_angle(_angle)
		for i in 3:
			var blink: float = 0.45 + 0.55 * absf(sin(_draw_time * 6.0 - i * 0.9))
			draw_circle(dir * (radius + 7.0 + i * 8.0), 2.0 - i * 0.4, Color(aim_color, blink))
