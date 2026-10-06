# ocean_current.gd
extends Node2D
class_name OceanCurrent

## Ocean Current - propels the turtle rapidly along a Path2D curve.
##
## SETUP IN INSPECTOR:
##   1. Add an OceanCurrent node to your level.
##   2. Select the child Path2D and draw your curve using the curve editor.
##   3. Tune the exports below per instance.
##   4. Set collision layers on the child Area2D in the Inspector:
##      - Collision Layer: 0 (detects, doesn't block)
##      - Collision Mask: 1 (detect player on layer 1)
##
## The collision polygon and the streak particles are auto-generated from
## the Path2D at runtime — just draw the curve and everything updates.

# ── Force settings ────────────────────────────────────────────────────────────
@export_group("Current Force")
## How strongly the current pushes the turtle along the path
@export var propulsion_force: float = 800.0
## How strongly the current corrects the turtle back toward the path centre
@export var centering_force: float = 10.0
## Width of the current tunnel in pixels (also controls collision & particle spread)
@export var current_width: float = 48.0
## Dampen the turtle's velocity perpendicular to the current direction
## (1.0 = full kill, 0.0 = no damping). Keeps turtle from drifting sideways.
@export_range(0.0, 1.0) var lateral_damping: float = 0.1
## How far from the path end (in pixels) before we stop pushing and eject the turtle.
@export var exit_zone_length: float = 24.0
## Impulse applied outward when the turtle exits the current end.
@export var exit_impulse: float = 200.0

# ── Appear / Disappear cycling ────────────────────────────────────────────────
@export_group("Visibility Cycle")
## If false the current is always active (no cycling)
@export var cycle_active: bool = false
## How long (seconds) the current is visible and active
@export var active_duration: float = 4.0
## How long (seconds) the current is hidden and inactive
@export var inactive_duration: float = 2.0
## Delay before the first appearance (staggers multiple currents in one level)
@export var start_delay: float = 0.0
## Fade duration for appear / disappear transition
@export var fade_duration: float = 0.5

# ── Alien Tech: Hydro Funnel ──────────────────────────────────────────────────
@export_group("Alien Tech: Hydro Funnel")
## If true, this current starts completely hidden/inert (overriding
## Visibility Cycle above — cycle_active is ignored) and only the Hydro
## Funnel alien tech's turn_on()/turn_off() calls ever change it. See
## AlienTechRegistry.HYDRO_FUNNEL.
@export var hydro_funnel: bool = false
## Only meaningful when hydro_funnel is also true. If set, this current stays
## off for the whole run while Hydro Funnel is cold — it only ever turns on
## once the tech goes HOT (an extra current exclusive to the hot version).
@export var hydro_funnel_hot_only: bool = false

# ── Visual / Particles ────────────────────────────────────────────────────────
@export_group("Visual")
## Primary color of the current (streaks, debug arrows)
@export var current_color: Color = Color(0.87, 0.95, 0.99, 0.7)
## Colour of the highlight streaks mixed in with the white ones — a rich jade
## green that stands out against both the white streaks and the blue ocean.
@export var highlight_color: Color = Color(0.0, 0.8, 0.5, 0.95)
## How many highlight streaks to mix in, as a fraction of particles_per_emitter
## (0 = none).
@export_range(0.0, 1.0) var highlight_ratio: float = 0.35
## Fade-out color for particles at end of life (default = transparent)
@export var current_color_fade: Color = Color(0.4, 1.0, 1.0, 0.0)
## Particle density: the path is split into this many stretches, each holding
## particles_per_emitter particles. 0 = auto (one stretch per 30px of path).
@export var emitter_count: int = 0
## Particles alive at once in each of those stretches
@export var particles_per_emitter: int = 8
## How long each particle lives (seconds)
@export var particle_lifetime: float = 0.6
## Speed range for particles travelling along the current direction
@export var particle_speed_min: float = 30.0
@export var particle_speed_max: float = 70.0
## Lateral scatter: how far particles can drift sideways from the path spine
@export var particle_spread: float = 10.0
## Length / thickness in pixels of each particle: a short line along the flow
## ("soft rain")
@export var streak_length: int = 6
@export var streak_width: int = 2
## Approaching the end of the path the soft rain stretches and speeds up into
## long streaks ("hard rain") that shoot out of the mouth — "you can't swim
## against this". Skipped when exit_impulse is 0 (nothing is ejected).
@export var exit_streaks: bool = true
## The last stretch of the path (pixels) where the streaks are at full length
@export var exit_streak_zone_length: float = 12.0
## The stretch before that over which the soft rain grows into streaks
@export var exit_streak_ramp_length: float = 16.0
## How far past the end of the path the streaks carry on while fading out
@export var exit_streak_overshoot: float = 10.0
## Extra particles born just upstream of the ramp so the mouth stays busy
## (highlight ones are added on top, by highlight_ratio)
@export var exit_streak_count: int = 8
## Length / thickness of a fully stretched streak in pixels
@export var exit_streak_length: int = 14
@export var exit_streak_width: int = 2
## Speed range of a fully stretched streak — well above the soft rain's so
## they read as a jet
@export var exit_streak_speed_min: float = 140.0
@export var exit_streak_speed_max: float = 200.0
## Show debug flow arrows in editor / debug builds
@export var show_debug_arrows: bool = true

# ── Internal refs ─────────────────────────────────────────────────────────────
@onready var _path: Path2D = $Path2D
@onready var _area: Area2D = $Path2D/Area2D
@onready var _collision_polygon: CollisionPolygon2D = $Path2D/Area2D/CollisionPolygon2D
@onready var _visuals: Node2D = $Visuals

# Streak particles. Simulated here rather than with GPUParticles2D so each one
# can follow the curve and stretch as it nears the exit. Parallel arrays, one
# entry per particle; _streak_canvas (child of the Path2D) draws them.
const _P_ALIVE := 1
const _P_HIGHLIGHT := 2
## Born just upstream of the exit ramp and never dies of age — see exit_streak_count
const _P_FEEDER := 4
## Share of a particle's life spent fading in / point where it starts fading out
const _P_FADE_IN := 0.15
const _P_FADE_OUT := 0.7
var _streak_canvas: Node2D = null
var _p_flags: PackedByteArray = PackedByteArray()
var _p_offset: PackedFloat32Array = PackedFloat32Array()      # distance along the curve
var _p_lateral: PackedFloat32Array = PackedFloat32Array()     # sideways from the spine
var _p_speed: PackedFloat32Array = PackedFloat32Array()
var _p_exit_speed: PackedFloat32Array = PackedFloat32Array()
var _p_age: PackedFloat32Array = PackedFloat32Array()
var _p_life: PackedFloat32Array = PackedFloat32Array()
var _emitting: bool = false
var _alive_count: int = 0
var _curve_length: float = 0.0
# Curve offsets where the stretch begins / is complete; both sit past the end
# of the path when this current has no exit streaks.
var _ramp_start: float = INF
var _ramp_end: float = INF
# One small quad per curve segment — see _build_collision_polygon() for why
# this replaced a single big ribbon polygon.
var _segment_shapes: Array[CollisionPolygon2D] = []

# State machine
enum _State { ACTIVE, INACTIVE, FADING_IN, FADING_OUT }
var _state: _State = _State.ACTIVE
var _cycle_timer: float = 0.0
var _bodies_inside: Array[RigidBody2D] = []
var _is_ready: bool = false

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("ocean_currents")
	if hydro_funnel:
		add_to_group("hydro_funnel_currents")

	_build_collision_polygon()
	_build_particles()

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	await get_tree().process_frame

	if hydro_funnel:
		# Tech-controlled: start fully inert regardless of Visibility Cycle
		# settings above — only turn_on()/turn_off() (driven by TurtlePlayer's
		# Hydro Funnel handling) ever change this from here on.
		_state = _State.INACTIVE
		modulate.a = 0.0
		_disable_collision()
	elif cycle_active:
		_state = _State.INACTIVE
		modulate.a = 0.0
		_disable_collision()
		if start_delay > 0.0:
			await get_tree().create_timer(start_delay).timeout
		_begin_fade_in()
	else:
		_state = _State.ACTIVE
		modulate.a = 1.0
		_set_emitting(true)

	_is_ready = true
	queue_redraw()


func _process(delta: float) -> void:
	if _streak_canvas == null or (not _emitting and _alive_count == 0):
		return
	_update_particles(delta)
	_streak_canvas.queue_redraw()


func _physics_process(delta: float) -> void:
	if not _is_ready:
		return

	if _state == _State.ACTIVE and _bodies_inside.size() > 0:
		for body in _bodies_inside:
			if is_instance_valid(body):
				_apply_current_to(body)

	if cycle_active and not hydro_funnel and (_state == _State.ACTIVE or _state == _State.INACTIVE):
		_cycle_timer -= delta
		if _cycle_timer <= 0.0:
			if _state == _State.ACTIVE:
				_begin_fade_out()
			else:
				_begin_fade_in()


# ── Streak particles ──────────────────────────────────────────────────────────

func _build_particles() -> void:
	var curve: Curve2D = _path.curve
	if curve == null or curve.point_count < 2:
		push_warning("OceanCurrent (%s): Path2D needs at least 2 points!" % name)
		return

	_streak_canvas = Node2D.new()
	_streak_canvas.z_index = 2          # Above ocean (0) but below turtle/enemies
	_streak_canvas.draw.connect(_draw_particles)
	_path.add_child(_streak_canvas)

	_curve_length = curve.get_baked_length()
	if exit_streaks and exit_impulse > 0.0:
		_ramp_end = max(_curve_length - exit_streak_zone_length, 0.0)
		_ramp_start = max(_ramp_end - max(exit_streak_ramp_length, 1.0), 0.0)
		# A path shorter than the zone: keep a sliver of ramp so smoothstep
		# still has two distinct edges
		_ramp_end = max(_ramp_end, _ramp_start + 1.0)

	var stretches: int = emitter_count if emitter_count > 0 else max(int(_curve_length / 30.0), 2)
	var body: int = stretches * particles_per_emitter
	var feeders: int = exit_streak_count if _ramp_start < INF else 0
	var groups: Array[Vector3i] = [
		Vector3i(body, 0, 0),
		Vector3i(roundi(body * highlight_ratio), _P_HIGHLIGHT, 0),
		Vector3i(feeders, _P_FEEDER, 0),
		Vector3i(roundi(feeders * highlight_ratio), _P_FEEDER | _P_HIGHLIGHT, 0),
	]
	for group in groups:
		for i in range(group.x):
			_p_flags.append(group.y)
	var total: int = _p_flags.size()
	_p_offset.resize(total)
	_p_lateral.resize(total)
	_p_speed.resize(total)
	_p_exit_speed.resize(total)
	_p_age.resize(total)
	_p_life.resize(total)


## Puts particle i back at a fresh spot. `scatter_age` starts it part-way
## through its life, so a current that has just switched on doesn't pulse.
func _respawn_particle(i: int, scatter_age: bool = false) -> void:
	var flags: int = _p_flags[i]
	if flags & _P_FEEDER:
		# Soft rain born just short of the ramp, across most of the tunnel:
		# the whole mouth pushes, not just the spine
		var lead: float = max(exit_streak_ramp_length, 1.0)
		var wide: float = max(particle_spread, current_width * 0.3)
		_p_offset[i] = randf_range(max(_ramp_start - lead, 0.0), _ramp_start)
		_p_lateral[i] = randf_range(-wide, wide)
	else:
		_p_offset[i] = randf_range(0.0, min(_ramp_start, _curve_length))
		_p_lateral[i] = randf_range(-particle_spread, particle_spread)
	_p_speed[i] = randf_range(particle_speed_min, particle_speed_max)
	_p_exit_speed[i] = randf_range(exit_streak_speed_min, exit_streak_speed_max)
	_p_life[i] = particle_lifetime * randf_range(0.8, 1.2)
	_p_age[i] = randf() * _p_life[i] if scatter_age and not (flags & _P_FEEDER) else 0.0
	_p_flags[i] = flags | _P_ALIVE


## 0 in the body of the current, rising to 1 where the streaks are full length.
func _stretch_at(offset: float) -> float:
	if offset <= _ramp_start:
		return 0.0
	return smoothstep(_ramp_start, _ramp_end, offset)


func _update_particles(delta: float) -> void:
	var end: float = _curve_length + exit_streak_overshoot
	_alive_count = 0
	for i in range(_p_flags.size()):
		var flags: int = _p_flags[i]
		if not (flags & _P_ALIVE):
			if not _emitting:
				continue
			_respawn_particle(i)
		var offset: float = _p_offset[i]
		offset += lerpf(_p_speed[i], _p_exit_speed[i], _stretch_at(offset)) * delta
		_p_offset[i] = offset

		var dead: bool
		if offset > _ramp_start:
			# Caught by the exit: it no longer fades with age (beyond finishing
			# its fade-in), it rides the whole way out of the mouth
			if _p_age[i] < _p_life[i] * _P_FADE_IN:
				_p_age[i] += delta
			dead = offset >= end
		else:
			_p_age[i] += delta
			# A feeder lives until the exit takes it
			dead = _p_age[i] >= _p_life[i] and not (flags & _P_FEEDER)
		if dead:
			_p_flags[i] = flags & ~_P_ALIVE
		else:
			_alive_count += 1


func _set_emitting(enabled: bool) -> void:
	if enabled and not _emitting:
		for i in range(_p_flags.size()):
			if not (_p_flags[i] & _P_ALIVE):
				_respawn_particle(i, true)
	_emitting = enabled


## A point `offset` along the flow and `lateral` to its side, in Path2D space.
## Past the end of the path the flow carries straight on along the end tangent.
func _flow_point(offset: float, lateral: float) -> Vector2:
	var xform: Transform2D = _path.curve.sample_baked_with_rotation(clampf(offset, 0.0, _curve_length), true)
	return xform.origin + xform.x * max(offset - _curve_length, 0.0) + xform.y * lateral


func _draw_particles() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE])
	for i in range(_p_flags.size()):
		var flags: int = _p_flags[i]
		if not (flags & _P_ALIVE):
			continue
		var offset: float = _p_offset[i]
		var stretch: float = _stretch_at(offset)

		# Fade in at birth and out at end of life; a particle the exit has
		# caught brightens to full instead, then fades out past the path's end
		var life_t: float = _p_age[i] / _p_life[i]
		var alpha: float = min(life_t / _P_FADE_IN, 1.0)
		if life_t > _P_FADE_OUT:
			alpha = clampf((1.0 - life_t) / (1.0 - _P_FADE_OUT), 0.0, 1.0)
		alpha = lerpf(alpha, 1.0, stretch)
		if offset > _curve_length and exit_streak_overshoot > 0.0:
			alpha *= clampf(1.0 - (offset - _curve_length) / exit_streak_overshoot, 0.0, 1.0)

		var color: Color = highlight_color if flags & _P_HIGHLIGHT else current_color
		color.a *= alpha
		var length: float = lerpf(streak_length, exit_streak_length, stretch)
		# Transparent tail, solid head
		points[0] = _flow_point(offset - length, _p_lateral[i])
		points[1] = _flow_point(offset, _p_lateral[i])
		colors[0] = Color(color, 0.0)
		colors[1] = color
		_streak_canvas.draw_polyline_colors(points, colors, lerpf(streak_width, exit_streak_width, stretch))


# ── Force application ─────────────────────────────────────────────────────────

func _apply_current_to(body: RigidBody2D) -> void:
	var curve: Curve2D = _path.curve
	if curve.point_count < 2:
		return

	var baked_length: float = curve.get_baked_length()
	var local_pos: Vector2 = _path.to_local(body.global_position)
	var closest_offset: float = curve.get_closest_offset(local_pos)

	# Exit zone: stop pushing and eject when near the path end.
	# Prevents the turtle getting trapped — get_closest_offset clamps to the
	# endpoint so without this the current keeps pulling the turtle back forever.
	if closest_offset >= baked_length - exit_zone_length:
		var end_angle: float = curve.sample_baked_with_rotation(baked_length, true).get_rotation()
		var exit_dir := Vector2(cos(end_angle), sin(end_angle))
		var exit_dir_global: Vector2 = _path.global_transform.basis_xform(exit_dir)
		body.apply_central_impulse(exit_dir_global * exit_impulse)
		# Ejection only (not entering or riding) can trigger Acceleration Focus.
		# The impulse doesn't reach linear_velocity until the next physics
		# step, so hand over the velocity it's about to produce.
		if body.has_method("notify_launch"):
			body.notify_launch(false, body.linear_velocity + exit_dir_global * exit_impulse / body.mass)
		_bodies_inside.erase(body)
		return

	var closest_point: Vector2 = curve.sample_baked(closest_offset)
	var curve_angle: float = curve.sample_baked_with_rotation(closest_offset, true).get_rotation()
	var tangent := Vector2(cos(curve_angle), sin(curve_angle))

	# Propulsion: push along the tangent
	var tangent_global: Vector2 = _path.global_transform.basis_xform(tangent)
	body.apply_central_force(tangent_global * propulsion_force)

	# Centering: push toward the spine
	var lateral_offset: Vector2 = local_pos - closest_point
	var lateral_offset_global: Vector2 = _path.global_transform.basis_xform(-lateral_offset)
	body.apply_central_force(lateral_offset_global * centering_force)

	# Lateral damping: bleed off perpendicular velocity
	var body_vel_local: Vector2 = _path.global_transform.basis_xform_inv(body.linear_velocity)
	var lateral_vel: Vector2 = body_vel_local - body_vel_local.project(tangent)
	body.linear_velocity -= _path.global_transform.basis_xform(lateral_vel * lateral_damping)


# ── Collision polygon generation ──────────────────────────────────────────────

## Builds the current's collision as a chain of small quads, one per curve
## segment, instead of a single big polygon offset left/right of the whole
## curve. A one-piece ribbon self-intersects wherever the curve bends
## tighter than current_width allows, and Godot's automatic convex
## decomposition can fail outright on that (logs "Convex decomposing
## failed!") — leaving the current with NO collision shape at all, so it
## silently stops detecting the player entirely. Each per-segment quad is a
## simple, inherently-convex shape on its own, so that failure mode can't
## happen here regardless of how tightly the curve bends.
func _build_collision_polygon() -> void:
	for shape in _segment_shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	_segment_shapes.clear()
	# The scene's own CollisionPolygon2D node is superseded by the per-segment
	# shapes below — neutralize it rather than remove it, so the @onready
	# reference (and current.tscn) don't need to change.
	_collision_polygon.polygon = PackedVector2Array()
	_collision_polygon.disabled = true

	var curve: Curve2D = _path.curve
	if curve == null or curve.point_count < 2:
		push_warning("OceanCurrent (%s): Path2D needs at least 2 points!" % name)
		return

	var baked_length: float = curve.get_baked_length()
	var sample_count: int = max(int(baked_length / 12.0), 4)
	var half_width: float = current_width * 0.5

	var prev_left: Vector2
	var prev_right: Vector2
	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var offset: float = t * baked_length
		var point: Vector2 = curve.sample_baked(offset)
		var angle: float = curve.sample_baked_with_rotation(offset, true).get_rotation()
		var perp := Vector2(-sin(angle), cos(angle))
		var left: Vector2 = point + perp * half_width
		var right: Vector2 = point - perp * half_width

		if i > 0:
			var quad := CollisionPolygon2D.new()
			quad.polygon = PackedVector2Array([prev_left, left, right, prev_right])
			_area.add_child(quad)
			_segment_shapes.append(quad)

		prev_left = left
		prev_right = right


# ── Appear / Disappear ────────────────────────────────────────────────────────

func _begin_fade_in() -> void:
	_state = _State.FADING_IN
	_enable_collision()
	_set_emitting(true)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	tween.tween_callback(func():
		_state = _State.ACTIVE
		_cycle_timer = active_duration
	)


func _begin_fade_out() -> void:
	_state = _State.FADING_OUT
	_bodies_inside.clear()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(func():
		_state = _State.INACTIVE
		_cycle_timer = inactive_duration
		_disable_collision()
		_set_emitting(false)
	)


# ── Alien Tech: Hydro Funnel control ──────────────────────────────────────────
# Called every physics frame by TurtlePlayer while it owns the Hydro Funnel
# tech (see _update_hydro_funnel_currents()) — idempotent, so a steady-state
# call each frame is cheap and needs no edge-detection on the caller's side.

## Fades this current in and enables it. No-op unless hydro_funnel is set, and
## for a hydro_funnel_hot_only current, no-op unless Hydro Funnel is HOT.
func turn_on() -> void:
	if not hydro_funnel or not _is_ready:
		return
	if hydro_funnel_hot_only and not AlienTechManager.is_tech_hot(AlienTechRegistry.HYDRO_FUNNEL):
		return
	if _state == _State.ACTIVE or _state == _State.FADING_IN:
		return
	_begin_fade_in()

## Fades this current out and disables it. No-op unless hydro_funnel is set.
func turn_off() -> void:
	if not hydro_funnel or not _is_ready:
		return
	if _state == _State.INACTIVE or _state == _State.FADING_OUT:
		return
	_begin_fade_out()


func _enable_collision() -> void:
	for shape in _segment_shapes:
		if is_instance_valid(shape):
			shape.disabled = false


func _disable_collision() -> void:
	for shape in _segment_shapes:
		if is_instance_valid(shape):
			shape.disabled = true
	_bodies_inside.clear()


## True while `body` is riding this current.
func has_body(body: Node) -> bool:
	return body in _bodies_inside


# ── Area signals ──────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if body is RigidBody2D and body.is_in_group("player"):
		if not body in _bodies_inside:
			_bodies_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)


# ── Debug drawing ─────────────────────────────────────────────────────────────

func _draw() -> void:
	if not show_debug_arrows:
		return
	if not Engine.is_editor_hint() and not OS.is_debug_build():
		return
	if _path == null or _path.curve == null or _path.curve.point_count < 2:
		return

	var curve: Curve2D = _path.curve
	var baked_length: float = curve.get_baked_length()
	var arrow_count: int = max(int(baked_length / 40.0), 2)

	for i in range(arrow_count):
		var t: float = (float(i) + 0.5) / float(arrow_count)
		var offset: float = t * baked_length
		var point: Vector2 = _path.to_global(curve.sample_baked(offset))
		var angle: float = curve.sample_baked_with_rotation(offset, true).get_rotation()
		var forward := Vector2(cos(angle), sin(angle)) * 12.0
		var perp := Vector2(-sin(angle), cos(angle)) * 6.0

		var p := to_local(point)
		draw_line(p - forward, p + forward, current_color, 1.5)
		draw_line(p + forward, p + forward - forward * 0.4 + perp * 0.5, current_color, 1.5)
		draw_line(p + forward, p + forward - forward * 0.4 - perp * 0.5, current_color, 1.5)
