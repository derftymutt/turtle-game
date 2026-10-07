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
## (layer 0, mask = Player). The visuals are drawn in code for now — a cloud
## of puffs with a tail — until there is a sprite.

@export_group("Shape")
## Radius of the comet's head, in pixels. The CollisionShape2D follows it.
@export var radius: float = 16.0:
	set(value):
		radius = value
		_sync_shape()
		queue_redraw()
## Direction it points while idle, in degrees (0 = right, -90 = up)
@export var rest_angle_degrees: float = -90.0:
	set(value):
		rest_angle_degrees = value
		if _state == State.WANDERING:
			_angle = deg_to_rad(value)
		queue_redraw()

@export_group("Wander")
## How far from home it drifts, sideways / up and down (pixels). The editor
## shows this as a faint outline.
@export var wander_range: Vector2 = Vector2(28.0, 18.0):
	set(value):
		wander_range = value
		queue_redraw()
## Seconds for one lazy loop around home
@export var wander_period: float = 9.0

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
@export var cloud_color: Color = Color(0.86, 0.95, 1.0, 1.0)
@export var core_color: Color = Color(0.55, 0.85, 1.0, 1.0)
@export var aim_color: Color = Color(1.0, 0.9, 0.3, 1.0)

enum State { WANDERING, HOLDING, FLYING, GONE }
var _state: State = State.WANDERING

const _EVAPORATE_SECONDS := 0.45
const _MATERIALIZE_SECONDS := 0.6
const _PUFF_COUNT := 9
## In flight the cloud draws over the turtle (z 1), which shows through it
const _FLIGHT_Z_INDEX := 2

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
var _rest_z_index: int = 0
var _draw_time: float = 0.0
## Cloud puffs: Vector3(angle, distance from centre (× radius), size (× radius))
var _puffs: Array[Vector3] = []

func _ready() -> void:
	_angle = deg_to_rad(rest_angle_degrees)
	_sync_shape()
	_build_puffs()
	if Engine.is_editor_hint():
		return
	add_to_group("rotating_launchers")
	_home = global_position
	_rest_z_index = z_index
	# Each comet starts somewhere different on its loop
	_wander_time = randf() * wander_period
	body_entered.connect(_on_body_entered)

func _sync_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	# Own shape per instance, so one launcher's radius never resizes another's
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape_node.shape = circle

func _build_puffs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_puffs.clear()
	for i in _PUFF_COUNT:
		_puffs.append(Vector3(TAU * i / _PUFF_COUNT + rng.randf_range(-0.2, 0.2), rng.randf_range(0.5, 0.75), rng.randf_range(0.42, 0.6)))

# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	match _state:
		State.WANDERING:
			_presence = minf(1.0, _presence + delta / _MATERIALIZE_SECONDS)
			_wander_time += delta
			global_position = _home + _wander_offset()
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
	# Follow the turtle every drawn frame, so the cloud never lags behind it
	if _state == State.FLYING and is_instance_valid(_passenger):
		global_position = _passenger.global_position
	queue_redraw()

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
	z_index = _FLIGHT_Z_INDEX
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
	global_position = _home + _wander_offset()
	z_index = _rest_z_index

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
# DRAWING
# ---------------------------------------------------------------------------

func _draw() -> void:
	if Engine.is_editor_hint():
		# Where it wanders
		draw_set_transform(Vector2.ZERO, 0.0, wander_range + Vector2.ONE * radius)
		draw_arc(Vector2.ZERO, 1.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), -1.0)
		draw_set_transform(Vector2.ZERO)
	if _presence <= 0.0:
		return

	var dir := Vector2.from_angle(_angle)
	var holding := _state == State.HOLDING
	var flying := _state == State.FLYING
	# Puffed up around the turtle while it's inside
	var size: float = radius * (1.25 if holding else 1.0)
	# Evaporating: the puffs drift apart as they fade
	var spread: float = 1.0 + (1.0 - _presence) * 1.2
	# See-through in flight so the turtle shows inside the cloud
	var alpha: float = _presence * (0.55 if flying else 0.9)

	# Tail: streams out behind the aim (holding) or the flight; a stub at rest
	var tail_length: float = size * (3.2 if flying else (2.2 if holding else 1.1))
	var tail_puffs: int = 7
	for i in tail_puffs:
		var f: float = float(i + 1) / tail_puffs
		var wobble: float = sin(_draw_time * 9.0 - f * 5.0) * size * 0.14 * f
		var p: Vector2 = -dir * (size * 0.5 + tail_length * f) + dir.orthogonal() * wobble
		draw_circle(p * spread, size * lerpf(0.5, 0.12, f), Color(cloud_color, alpha * (1.0 - f) * 0.7))

	# Head: a ring of soft puffs that breathe a little, over a brighter core
	for i in _puffs.size():
		var puff: Vector3 = _puffs[i]
		var breathe: float = 1.0 + sin(_draw_time * 2.4 + i * 1.7) * 0.08
		var p: Vector2 = Vector2.from_angle(puff.x + _draw_time * 0.25) * puff.y * size * spread
		draw_circle(p, puff.z * size * breathe, Color(cloud_color, alpha * 0.75))
	draw_circle(Vector2.ZERO, size * 0.6, Color(core_color, alpha * 0.8))
	draw_circle(dir * size * 0.2, size * 0.32, Color(1, 1, 1, alpha))

	# Aim: arrow on the leading edge plus a dotted line out ahead
	if holding:
		var side := dir.orthogonal()
		var tip := dir * (size + 9.0)
		var base := dir * (size - 1.0)
		draw_colored_polygon(PackedVector2Array([tip, base + side * 6.0, base - side * 6.0]), aim_color)
		for i in 3:
			var blink: float = 0.45 + 0.55 * absf(sin(_draw_time * 6.0 - i * 0.9))
			draw_circle(dir * (size + 17.0 + i * 9.0), 2.0 - i * 0.4, Color(aim_color, blink))
	elif _state == State.WANDERING:
		draw_circle(dir * (size * 0.9), 2.0, Color(aim_color, _presence))
