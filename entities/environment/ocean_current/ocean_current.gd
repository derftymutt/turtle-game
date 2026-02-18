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
## The collision polygon and particle emitters are auto-generated from
## the Path2D at runtime — just draw the curve and everything updates.

# ── Force settings ────────────────────────────────────────────────────────────
@export_group("Current Force")
## How strongly the current pushes the turtle along the path
@export var propulsion_force: float = 800.0
## How strongly the current corrects the turtle back toward the path centre
@export var centering_force: float = 400.0
## Width of the current tunnel in pixels (also controls collision & particle spread)
@export var current_width: float = 48.0
## Dampen the turtle's velocity perpendicular to the current direction
## (1.0 = full kill, 0.0 = no damping). Keeps turtle from drifting sideways.
@export_range(0.0, 1.0) var lateral_damping: float = 0.85
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

# ── Visual / Particles ────────────────────────────────────────────────────────
@export_group("Visual")
## Primary color of the current (bubbles, glow, arrows)
@export var current_color: Color = Color(0.0, 0.8, 1.0, 0.7)
## Fade-out color for particles at end of life (default = transparent)
@export var current_color_fade: Color = Color(0.4, 1.0, 1.0, 0.0)
## How many GPUParticles2D emitters to place along the path.
## 0 = auto-calculate (roughly 1 per 50px of path length).
@export var emitter_count: int = 0
## Particles emitted per second from EACH emitter
@export var particles_per_emitter: int = 8
## How long each particle lives (seconds)
@export var particle_lifetime: float = 0.6
## Speed range for particles travelling along the current direction
@export var particle_speed_min: float = 30.0
@export var particle_speed_max: float = 70.0
## Lateral scatter: how far particles can drift sideways from the path spine
@export var particle_spread: float = 10.0
## Size of each bubble in pixels. Larger = more visible, rounder feel.
@export var particle_pixel_size: int = 6
## Show debug flow arrows in editor / debug builds
@export var show_debug_arrows: bool = true

# ── Internal refs ─────────────────────────────────────────────────────────────
@onready var _path: Path2D = $Path2D
@onready var _area: Area2D = $Path2D/Area2D
@onready var _collision_polygon: CollisionPolygon2D = $Path2D/Area2D/CollisionPolygon2D
@onready var _visuals: Node2D = $Visuals

# Shared particle texture — one tiny white-pixel image reused by all emitters
var _bubble_texture: ImageTexture = null
# All spawned emitters, kept so we can toggle them during cycling
var _emitters: Array[GPUParticles2D] = []

# State machine
enum _State { ACTIVE, INACTIVE, FADING_IN, FADING_OUT }
var _state: _State = _State.ACTIVE
var _cycle_timer: float = 0.0
var _bodies_inside: Array[RigidBody2D] = []
var _is_ready: bool = false

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("ocean_currents")

	_bubble_texture = _create_bubble_texture()
	_build_collision_polygon()
	_build_particle_emitters()

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	# Wait one frame so all dynamically added emitter nodes are fully in the
	# scene tree before we try to set emitting — otherwise the property set
	# fires before the node is ready and gets silently ignored.
	await get_tree().process_frame

	if cycle_active:
		_state = _State.INACTIVE
		modulate.a = 0.0
		_disable_collision()
		# emitters already created with emitting = false, nothing to do
		if start_delay > 0.0:
			await get_tree().create_timer(start_delay).timeout
		_begin_fade_in()
	else:
		_state = _State.ACTIVE
		modulate.a = 1.0
		_set_emitters_emitting(true)

	_is_ready = true
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _is_ready:
		return

	if _state == _State.ACTIVE and _bodies_inside.size() > 0:
		for body in _bodies_inside:
			if is_instance_valid(body):
				_apply_current_to(body)

	if cycle_active and (_state == _State.ACTIVE or _state == _State.INACTIVE):
		_cycle_timer -= delta
		if _cycle_timer <= 0.0:
			if _state == _State.ACTIVE:
				_begin_fade_out()
			else:
				_begin_fade_in()


# ── Particle texture ──────────────────────────────────────────────────────────

func _create_bubble_texture() -> ImageTexture:
	var size: int = particle_pixel_size
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# ── Particle emitter construction ─────────────────────────────────────────────

func _build_particle_emitters() -> void:
	var curve: Curve2D = _path.curve
	if curve == null or curve.point_count < 2:
		push_warning("OceanCurrent (%s): Path2D needs at least 2 points!" % name)
		return

	for e in _emitters:
		if is_instance_valid(e):
			e.queue_free()
	_emitters.clear()

	var baked_length: float = curve.get_baked_length()
	var count: int = emitter_count if emitter_count > 0 else max(int(baked_length / 30.0), 2)

	for i in range(count):
		var t: float = (float(i) + 0.5) / float(count)
		var offset: float = t * baked_length
		var point: Vector2 = curve.sample_baked(offset)
		var angle: float = curve.sample_baked_with_rotation(offset, true).get_rotation()

		var emitter := _create_emitter(point, angle)
		_path.add_child(emitter)
		_emitters.append(emitter)


func _create_emitter(local_point: Vector2, angle: float) -> GPUParticles2D:
	var emitter := GPUParticles2D.new()

	# local_point is in Path2D local space — emitter is parented to _path
	emitter.position = local_point
	emitter.rotation = angle

	emitter.amount = particles_per_emitter
	emitter.lifetime = particle_lifetime
	emitter.explosiveness = 0.0
	emitter.randomness = 0.5
	emitter.z_index = 2          # Above ocean (0) but below turtle/enemies
	emitter.emitting = false     # Enabled after process_frame in _ready

	var mat := ParticleProcessMaterial.new()

	# Forward along the current — emitter is rotated to the curve tangent
	# so Vector3(1,0,0) always means "downstream"
	mat.direction = Vector3(1.0, 0.0, 0.0)
	mat.spread = 25.0

	mat.initial_velocity_min = particle_speed_min
	mat.initial_velocity_max = particle_speed_max

	# Spawn across the tunnel width, not just from the spine
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(4.0, particle_spread, 0.0)

	mat.gravity = Vector3.ZERO

	# Gentle damping so particles trail off naturally at end of life
	mat.damping_min = 15.0
	mat.damping_max = 30.0

	# Randomise bubble sizes so they don't all look identical
	mat.scale_min = 0.8
	mat.scale_max = 2.0

	# Fade from full current color to transparent — the key visual effect.
	# We use mat.color directly instead of a GradientTexture1D because
	# creating Gradient resources in code can produce silent failures.
	# The alpha fade is handled by animating color_initial_ramp below.
	mat.color = current_color

	# Alpha over lifetime: full opacity at birth, zero at death
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 1.0))
	alpha_curve.add_point(Vector2(0.7, 0.8))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.bake()
	var alpha_tex := CurveTexture.new()
	alpha_tex.curve = alpha_curve
	mat.alpha_curve = alpha_tex

	emitter.process_material = mat
	return emitter


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

func _build_collision_polygon() -> void:
	var curve: Curve2D = _path.curve
	if curve == null or curve.point_count < 2:
		push_warning("OceanCurrent (%s): Path2D needs at least 2 points!" % name)
		return

	var baked_length: float = curve.get_baked_length()
	var sample_count: int = max(int(baked_length / 12.0), 4)
	var half_width: float = current_width * 0.5

	var left_points: PackedVector2Array = []
	var right_points: PackedVector2Array = []

	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var offset: float = t * baked_length
		var point: Vector2 = curve.sample_baked(offset)
		var angle: float = curve.sample_baked_with_rotation(offset, true).get_rotation()
		var perp := Vector2(-sin(angle), cos(angle))

		left_points.append(point + perp * half_width)
		right_points.append(point - perp * half_width)

	var polygon: PackedVector2Array = []
	for p in left_points:
		polygon.append(p)
	right_points.reverse()
	for p in right_points:
		polygon.append(p)

	_collision_polygon.polygon = polygon


# ── Appear / Disappear ────────────────────────────────────────────────────────

func _begin_fade_in() -> void:
	_state = _State.FADING_IN
	_enable_collision()
	_set_emitters_emitting(true)
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
		_set_emitters_emitting(false)
	)


func _enable_collision() -> void:
	_collision_polygon.disabled = false


func _disable_collision() -> void:
	_collision_polygon.disabled = true
	_bodies_inside.clear()


func _set_emitters_emitting(enabled: bool) -> void:
	print("OceanCurrent: setting %d emitters emitting=%s" % [_emitters.size(), enabled])
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.emitting = enabled
			print("  emitter at %s emitting=%s valid=%s" % [emitter.position, emitter.emitting, is_instance_valid(emitter)])


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
