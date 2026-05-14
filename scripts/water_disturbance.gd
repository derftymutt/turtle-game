extends Node2D
class_name WaterDisturbance

## Periodic ocean current system.
## Cycles through CALM → WARNING → SURGE → SUBSIDE states.
## During WARNING, sparse slow particles appear from the incoming edge and chevrons pulse yellow.
## During SURGE, a strong stable current pushes all underwater bodies in one direction.
## Direction is chosen randomly each cycle from a pool of mostly-horizontal vectors.

enum CycleState { CALM, WARNING, SURGE, SUBSIDE }

@export_group("Cycle Timing")
@export var calm_duration: float = 25.0
@export var warning_duration: float = 6.0
@export var surge_duration: float = 15.0
@export var subside_duration: float = 5.0

@export_group("Force")
@export var surge_strength: float = 220.0
@export var turbulence_strength: float = 100.0

@export_group("Targets")
@export var affect_player: bool = true
@export var affect_enemies: bool = true
@export var affect_collectibles: bool = true

signal surge_warning(direction: Vector2)
signal surge_started(direction: Vector2)
signal surge_ended()

var _state: CycleState = CycleState.CALM
var _state_timer: float = 0.0
var _surge_direction: Vector2 = Vector2.RIGHT
var _force_scale: float = 0.0
var _time: float = 0.0
var _ocean: Ocean = null
var _particles: CPUParticles2D = null


func _ready() -> void:
	_state_timer = calm_duration
	_particles = CPUParticles2D.new()
	add_child(_particles)
	_setup_particles()


func _pick_surge_direction() -> Vector2:
	var dirs: Array[Vector2] = [
		Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
		Vector2(0.85, 0.2), Vector2(-0.85, 0.2),
		Vector2(0.85, -0.2), Vector2(-0.85, -0.2),
	]
	return dirs[randi() % dirs.size()]


func _setup_particles() -> void:
	_particles.emitting = false
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.randomness = 0.4
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(320.0, 150.0)
	_particles.gravity = Vector2.ZERO
	_particles.spread = 8.0
	_particles.scale_amount_min = 1.5
	_particles.scale_amount_max = 3.5
	# set_color(0/1) before add_point — add_point shifts indices
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.7, 0.95, 1.0, 0.0))
	ramp.set_color(1, Color(0.7, 0.95, 1.0, 0.0))
	ramp.add_point(0.15, Color(0.82, 0.97, 1.0, 0.55))
	ramp.add_point(0.78, Color(0.62, 0.90, 1.0, 0.55))
	_particles.color_ramp = ramp


func _process(delta: float) -> void:
	_time += delta
	var target_scale: float
	match _state:
		CycleState.WARNING:
			target_scale = 0.15
		CycleState.SURGE:
			target_scale = 1.0
		_:
			target_scale = 0.0
	_force_scale = lerp(_force_scale, target_scale, delta * 2.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_state_timer -= delta
	_update_state()

	if not _ocean:
		var nodes: Array[Node] = get_tree().get_nodes_in_group("ocean")
		if nodes.is_empty():
			return
		_ocean = nodes[0] as Ocean
		if not _ocean:
			return

	if _force_scale > 0.02:
		if affect_player:
			_apply_to_group("player")
		if affect_enemies:
			_apply_to_group("enemies")
		if affect_collectibles:
			_apply_to_group("powerups")
			_apply_to_group("trash_items")


func _update_state() -> void:
	if _state_timer > 0.0:
		return
	match _state:
		CycleState.CALM:
			_enter_warning()
		CycleState.WARNING:
			_enter_surge()
		CycleState.SURGE:
			_enter_subside()
		CycleState.SUBSIDE:
			_enter_calm()


func _enter_warning() -> void:
	_state = CycleState.WARNING
	_state_timer = warning_duration
	_surge_direction = _pick_surge_direction()
	_particles.direction = _surge_direction
	_particles.lifetime = 4.5
	_particles.amount = 22
	_particles.initial_velocity_min = 38.0
	_particles.initial_velocity_max = 62.0
	_particles.emitting = true
	surge_warning.emit(_surge_direction)


func _enter_surge() -> void:
	_state = CycleState.SURGE
	_state_timer = surge_duration
	_particles.emitting = false
	_particles.lifetime = 3.0
	_particles.amount = 80
	_particles.initial_velocity_min = 85.0
	_particles.initial_velocity_max = 135.0
	_particles.emitting = true
	surge_started.emit(_surge_direction)


func _enter_subside() -> void:
	_state = CycleState.SUBSIDE
	_state_timer = subside_duration
	_particles.emitting = false
	surge_ended.emit()


func _enter_calm() -> void:
	_state = CycleState.CALM
	_state_timer = calm_duration
	_force_scale = 0.0


func _draw() -> void:
	if _force_scale < 0.03:
		return

	var perp: Vector2 = Vector2(-_surge_direction.y, _surge_direction.x)
	# Chevrons on the incoming edge (opposite to flow direction)
	var edge_x: float = -_surge_direction.x * 282.0

	var flash: float = 1.0
	if _state == CycleState.WARNING:
		flash = abs(sin(_time * 3.8))

	var col: Color
	if _state == CycleState.SURGE or _state == CycleState.SUBSIDE:
		col = Color(0.55, 0.93, 1.0, _force_scale * 0.85)
	else:
		col = Color(1.0, 0.92, 0.35, _force_scale * flash * 0.85)

	if col.a < 0.03:
		return

	for i in range(6):
		var t: float = float(i) / 5.0
		var y: float = lerp(-108.0, 162.0, t)
		var center: Vector2 = Vector2(edge_x, y)
		var tip: Vector2 = center + _surge_direction * 11.0
		var arm_a: Vector2 = center - _surge_direction * 4.0 + perp * 9.0
		var arm_b: Vector2 = center - _surge_direction * 4.0 - perp * 9.0
		draw_line(arm_a, tip, col, 2.5)
		draw_line(arm_b, tip, col, 2.5)


func _apply_to_group(group: String) -> void:
	for node in get_tree().get_nodes_in_group(group):
		if node is RigidBody2D:
			_apply_current(node as RigidBody2D)


func _apply_current(body: RigidBody2D) -> void:
	var depth: float = _ocean.get_depth(body.global_position)
	if depth <= 5.0:
		return

	var pos: Vector2 = body.global_position

	# Stable directional current + micro-turbulence for organic feel
	var main: Vector2 = _surge_direction * surge_strength * _force_scale
	var tx: float = sin(_time * 2.3 + pos.x * 0.018 + pos.y * 0.013) * turbulence_strength * _force_scale
	var ty: float = cos(_time * 1.8 + pos.y * 0.021 - pos.x * 0.016) * turbulence_strength * _force_scale

	var depth_factor: float = clampf(depth / 80.0, 0.0, 1.0)
	body.apply_central_force((main + Vector2(tx, ty)) * depth_factor)
