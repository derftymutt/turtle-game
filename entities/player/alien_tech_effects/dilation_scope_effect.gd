extends AlienTechEffect
class_name DilationScopeEffect

## Dilation Scope — bullet time. While the tech window is open (`active`), a
## flipper, bumper (incl. Bumper Magnet release), puffer-spit or ocean-current
## ejection launch that
## reaches super speed reports itself through TurtlePlayer.notify_launch(),
## and time drops to a near stop almost immediately (SLOWING: a SLOW_DURATION
## drop, then an AIM_DURATION window held at MIN_DILATION, so the turtle has
## barely left the launcher). Meanwhile a trajectory line shows
## the turtle's course, and the stick bends it side to side around the launch
## heading the same way Bumper Magnet's orbit steering works, capped at
## MAX_AIM_DEG either way. When time stops the course locks in (STOPPED): the
## turtle is redirected along it at LAUNCH_BOOST × its launch speed (bumper
## launches get BUMPER_LAUNCH_BOOST instead), and time
## ricochets back to normal (RICOCHET). Swimming is replaced by aiming during
## SLOWING/STOPPED; spitting is blocked only while STOPPED.
##
## The slow-down is global (GameSettings.set_time_dilation(), which also
## pitches audio down), so the phase timing runs on REAL time — the physics
## tick length — rather than the dilated delta. A sudden turn mid-slow-down
## (the turtle hit something) or real damage aborts straight to RICOCHET
## without redirecting. After each bullet time a short real-time lockout stops
## bumper chains from retriggering it back to back. shutdown() (from
## TurtlePlayer._exit_tree()) guarantees time is never left dilated.
##
## Cold: 5s window, 8s cooldown. Hot: click on/off, no timer, no cooldown.
## A bullet time already in progress always finishes, even if the window ends.

enum Phase { IDLE, SLOWING, STOPPED, RICOCHET }

# All durations in real seconds. The drop has to be short: the turtle keeps
# moving at launch speed × dilation, so a slow drop lets it travel far before
# aiming starts. Aiming happens mostly in the near-frozen AIM_DURATION window.
const SLOW_DURATION: float = 0.1
const AIM_DURATION: float = 0.6
const STOP_DURATION: float = 0.15
const RICOCHET_DURATION: float = 0.25
const RETRIGGER_LOCKOUT: float = 0.75
# Direction changes during the first moments of SLOWING are the launcher
# itself still pushing (a flipper mid-swing), not a collision — don't abort.
const ABORT_GRACE: float = 0.08

const MIN_DILATION: float = 0.03   # "stopped" — true zero would stall physics
# Ion Exciter doubles flipper/bumper launch speed, so the turtle would cover
# twice the ground before the stop and creep twice as fast while aiming —
# halve the drop time and the near-stop speed to compensate. Latched per
# launch (see on_launch()).
const ION_SLOW_DURATION: float = 0.05
const ION_MIN_DILATION: float = 0.015
const MAX_AIM_DEG: float = 25.0
const AIM_SPEED: float = 1.3       # radians per real second at full stick
const LAUNCH_BOOST: float = 1.1
const BUMPER_LAUNCH_BOOST: float = 1.25  # bumpers (incl. Bumper Magnet release) punch 15% harder
const ABORT_TURN: float = 0.6      # radians turned in one tick that count as a collision

const LINE_LENGTH: float = 140.0
const CONE_LENGTH: float = 60.0
const WORLD_MASK: int = 1          # World_Player — the line stops at the first wall/bumper
const LINE_COLOR := Color(0.35, 0.95, 0.75, 0.9)
const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const CONE_COLOR := Color(0.35, 0.95, 0.75, 0.3)

var active: bool = false  # tech window open — read by TechAura
var _timer: float = 0.0

var _phase: Phase = Phase.IDLE
var _phase_time: float = 0.0
var _lockout: float = 0.0
var _ricochet_from: float = MIN_DILATION
var _base_dir: Vector2 = Vector2.RIGHT
var _offset: float = 0.0
var _speed: float = 0.0
var _boost: float = LAUNCH_BOOST
var _slow_duration: float = SLOW_DURATION
var _min_dilation: float = MIN_DILATION

var _line: Line2D = null
var _cone_a: Line2D = null
var _cone_b: Line2D = null

func setup(player) -> void:
	_line = _make_line(player, "DilationScopeLine", LINE_COLOR, 1.0)
	_cone_a = _make_line(player, "DilationScopeConeA", CONE_COLOR, 1.0)
	_cone_b = _make_line(player, "DilationScopeConeB", CONE_COLOR, 1.0)

func _make_line(player, line_name: String, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.top_level = true  # points are in global space, unaffected by the body's spin
	line.default_color = color
	line.width = width
	line.z_as_relative = false
	line.z_index = 24
	line.visible = false
	player.add_child(line)
	return line

func activate(_player, _slot_index: int) -> void:
	if AlienTechManager.is_tech_hot(AlienTechRegistry.DILATION_SCOPE):
		# Hot: click on, click off — no timer, no cooldown (see _effective_cooldown_max).
		active = not active
		if active:
			AlienTechManager.set_passive_bar(AlienTechRegistry.DILATION_SCOPE, 1.0)
		else:
			AlienTechManager.clear_passive_bar(AlienTechRegistry.DILATION_SCOPE)
		return
	active = true
	_timer = AlienTechManager.DILATION_SCOPE_ACTIVE_DURATION

func physics_process(player, delta: float) -> void:
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.DILATION_SCOPE):
		_timer -= delta
		if _timer <= 0.0:
			active = false

	var real_dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if _lockout > 0.0:
		_lockout -= real_dt
	if _phase == Phase.IDLE:
		return
	_phase_time += real_dt
	match _phase:
		Phase.SLOWING:
			_process_slowing(player, real_dt)
		Phase.STOPPED:
			_update_lines(player)
			if _phase_time >= STOP_DURATION:
				_start_ricochet(_min_dilation)
		Phase.RICOCHET:
			var t: float = clampf(_phase_time / RICOCHET_DURATION, 0.0, 1.0)
			GameSettings.set_time_dilation(lerpf(_ricochet_from, 1.0, 1.0 - (1.0 - t) * (1.0 - t)))
			if t >= 1.0:
				_finish()

## Called from TurtlePlayer.notify_launch() right after a flipper / bumper /
## puffer / current ejection has launched the turtle. `launch_velocity`
## (a Vector2, or null to read linear_velocity) covers impulse launches.
func on_launch(player, from_bumper: bool = false, launch_velocity = null) -> void:
	if not active or _phase != Phase.IDLE or _lockout > 0.0:
		return
	var v: Vector2 = launch_velocity if launch_velocity is Vector2 else player.linear_velocity
	if v.length() < player.super_speed_threshold:
		return
	_base_dir = v.normalized()
	_speed = v.length()
	_boost = BUMPER_LAUNCH_BOOST if from_bumper else LAUNCH_BOOST
	var ion: bool = player.is_ion_exciter_active()
	_slow_duration = ION_SLOW_DURATION if ion else SLOW_DURATION
	_min_dilation = ION_MIN_DILATION if ion else MIN_DILATION
	_offset = 0.0
	_phase = Phase.SLOWING
	_phase_time = 0.0
	_line.default_color = LINE_COLOR
	_set_lines_visible(true)
	_update_lines(player)

func _process_slowing(player, real_dt: float) -> void:
	var t: float = clampf(_phase_time / _slow_duration, 0.0, 1.0)
	# Cubic ease-out drop, then held at the near-stop for the aim window.
	GameSettings.set_time_dilation(lerpf(_min_dilation, 1.0, pow(1.0 - t, 3.0)))

	# Follow the live heading (gravity curves it in the sky); a sharp turn
	# means the turtle hit something — abort without redirecting.
	var v: Vector2 = player.linear_velocity
	if v.length() < 1.0:
		_start_ricochet(_current_dilation())
		return
	var dir: Vector2 = v.normalized()
	if _phase_time > ABORT_GRACE and absf(_base_dir.angle_to(dir)) > ABORT_TURN:
		_start_ricochet(_current_dilation())
		return
	_base_dir = dir

	# Bumper Magnet-style steering: project the stick onto the clockwise
	# tangent of the current aim, so "push the way you want to curve" works
	# for any launch angle, vertical included.
	var stick := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if GameSettings.thrust_inverted:
		stick = -stick
	var aim := _aim_dir()
	var tangent_cw := Vector2(-aim.y, aim.x)
	var max_offset := deg_to_rad(MAX_AIM_DEG)
	_offset = clampf(_offset + stick.dot(tangent_cw) * AIM_SPEED * real_dt, -max_offset, max_offset)
	_update_lines(player)

	if _phase_time >= _slow_duration + AIM_DURATION:
		_lock(player)

func _lock(player) -> void:
	var dir := _aim_dir()
	player.linear_velocity = dir * _speed * _boost
	player.facing_direction = player._vector_to_direction_suffix(dir)
	player._play_animation("kick")
	GameSettings.set_time_dilation(_min_dilation)
	_line.default_color = LOCKED_COLOR
	_set_cone_visible(false)
	_phase = Phase.STOPPED
	_phase_time = 0.0
	_update_lines(player)

func _start_ricochet(from_dilation: float) -> void:
	_ricochet_from = from_dilation
	_phase = Phase.RICOCHET
	_phase_time = 0.0
	_set_lines_visible(false)

func _finish() -> void:
	GameSettings.reset_time_dilation()
	_phase = Phase.IDLE
	_phase_time = 0.0
	_lockout = RETRIGGER_LOCKOUT
	_set_lines_visible(false)

## Real damage mid-slow-down cancels the redirect; time still eases back.
func cancel_on_damage(_player) -> void:
	if _phase == Phase.SLOWING:
		_start_ricochet(_current_dilation())

func on_slots_changed(_player) -> void:
	if not AlienTechManager.has_tech(AlienTechRegistry.DILATION_SCOPE):
		active = false
		_timer = 0.0

## Hard stop with no easing — the player is leaving the tree.
func shutdown() -> void:
	if _phase != Phase.IDLE:
		_phase = Phase.IDLE
		GameSettings.reset_time_dilation()

## Swim input is the aiming stick during bullet time.
func blocks_swim() -> bool:
	return _phase == Phase.SLOWING or _phase == Phase.STOPPED

func blocks_shooting() -> bool:
	return _phase == Phase.STOPPED

func _aim_dir() -> Vector2:
	return _base_dir.rotated(_offset)

func _current_dilation() -> float:
	return Engine.time_scale / GameSettings.GAME_SPEED

func _update_lines(player) -> void:
	var from: Vector2 = player.global_position
	_line.points = PackedVector2Array([from, _ray_end(player, from, _aim_dir(), LINE_LENGTH)])
	if _cone_a.visible:
		var max_offset := deg_to_rad(MAX_AIM_DEG)
		_cone_a.points = PackedVector2Array([from, from + _base_dir.rotated(-max_offset) * CONE_LENGTH])
		_cone_b.points = PackedVector2Array([from, from + _base_dir.rotated(max_offset) * CONE_LENGTH])

## Where the course line meets the first wall/bumper, or its full length.
func _ray_end(player, from: Vector2, dir: Vector2, length: float) -> Vector2:
	var to: Vector2 = from + dir * length
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else to

func _set_lines_visible(on: bool) -> void:
	_line.visible = on
	_set_cone_visible(on)

func _set_cone_visible(on: bool) -> void:
	_cone_a.visible = on
	_cone_b.visible = on
