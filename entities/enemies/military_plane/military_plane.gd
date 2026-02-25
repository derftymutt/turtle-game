# military_plane.gd
extends Node2D
class_name MilitaryPlane

## Invincible military plane that flies horizontally through the sky
## and fires at the turtle. Two variants:
##
##   SPREAD  — fires a 3-bullet spread arc, spread_shot_count times per pass
##   MISSILE — fires homing missiles, missile_count times per pass
##
## Shots are distributed evenly across the pass duration using a time-based
## approach, so they always spread out regardless of entry direction or speed.
##
## SCENE SETUP:
##   Add two sprite children named "SpreadSprite" and "MissileSprite".
##   Assign plane_bullet_scene and homing_missile_scene in the Inspector.

signal pass_started(plane_type: PlaneType)
signal pass_completed

enum PlaneType { SPREAD, MISSILE }

# ── Configuration ──────────────────────────────────────────────────────────
@export_group("Scenes")
@export var plane_bullet_scene: PackedScene
@export var homing_missile_scene: PackedScene

@export_group("Movement")
## How far off either side of the screen the plane starts and ends its pass.
@export var spawn_x_margin: float = 400.0
## Y position the plane flies at. Tune to sit within your visible sky area.
@export var fly_y: float = -400.0
@export var fly_speed: float = 175.0

@export_group("Spread Shot")
@export var spread_bullet_count: int = 3
## Total arc width in degrees. 40° gives a readable fan.
@export var spread_angle_deg: float = 40.0
@export var spread_bullet_speed: float = 300.0
## How many spread bursts fire during one pass.
@export var spread_shot_count: int = 3

@export_group("Homing Missile")
## How many missiles fire during one pass.
@export var missile_count: int = 2

# ── Internal State ─────────────────────────────────────────────────────────
var active: bool = false
var plane_type: PlaneType = PlaneType.SPREAD
var travel_direction: float = 1.0
var target_x: float = 0.0

# Time-based firing
var _pass_duration: float = 0.0    # Total time the pass takes
var _pass_elapsed: float = 0.0     # Time since pass started
var _fire_times: Array[float] = [] # Pre-calculated times to fire (seconds into pass)
var _fired_count: int = 0

var _spread_sprite: Node2D = null
var _missile_sprite: Node2D = null


func _ready() -> void:
	_spread_sprite  = get_node_or_null("SpreadSprite")
	_missile_sprite = get_node_or_null("MissileSprite")
	_set_sprites_visible(false, false)
	visible = false


func _process(delta: float) -> void:
	if not active:
		return

	position.x += travel_direction * fly_speed * delta
	_pass_elapsed += delta

	# Fire at pre-calculated times during the pass
	while _fired_count < _fire_times.size() and _pass_elapsed >= _fire_times[_fired_count]:
		if plane_type == PlaneType.SPREAD:
			_fire_spread()
		else:
			_fire_missile()
		_fired_count += 1

	# End pass once the full duration has elapsed
	if _pass_elapsed >= _pass_duration:
		_finish_pass()


# ── Public API ─────────────────────────────────────────────────────────────

func launch(type: PlaneType = PlaneType.SPREAD, from_left: bool = true) -> void:
	if active:
		return

	plane_type       = type
	travel_direction = 1.0 if from_left else -1.0

	var half_w: float = get_viewport_rect().size.x / 2.0
	var total_distance: float = half_w * 2.0 + spawn_x_margin * 2.0

	position = Vector2(
		(-half_w - spawn_x_margin) if from_left else (half_w + spawn_x_margin),
		fly_y
	)
	target_x = (half_w + spawn_x_margin) if from_left else (-half_w - spawn_x_margin)

	# Total time for the plane to cross from spawn to exit
	_pass_duration = total_distance / fly_speed
	_pass_elapsed  = 0.0
	_fired_count   = 0
	_fire_times.clear()

	# How many shots this pass
	var shot_count: int = spread_shot_count if type == PlaneType.SPREAD else missile_count

	# Distribute shots evenly across the VISIBLE portion of the pass.
	# We only fire while the plane is on screen, not during the off-screen margins.
	# on_screen_start/end are the times when the plane enters/exits the viewport.
	var margin_time: float = spawn_x_margin / fly_speed
	var on_screen_start: float = margin_time
	var on_screen_end: float   = _pass_duration - margin_time

	for i in range(shot_count):
		# Distribute evenly: frac goes from 0 to 1 across the on-screen window.
		# Using (i + 1) / (shot_count + 1) keeps shots away from the very edges.
		var frac: float = float(i + 1) / float(shot_count + 1)
		_fire_times.append(lerp(on_screen_start, on_screen_end, frac))

	_set_sprite_flip(travel_direction < 0.0)
	_set_sprites_visible(type == PlaneType.SPREAD, type == PlaneType.MISSILE)

	visible = true
	active  = true
	pass_started.emit(plane_type)


# ── Firing ─────────────────────────────────────────────────────────────────

func _fire_spread() -> void:
	if not plane_bullet_scene:
		push_warning("MilitaryPlane: plane_bullet_scene not assigned!")
		return

	var half_arc: float = deg_to_rad(spread_angle_deg / 2.0)
	for i in range(spread_bullet_count):
		var t: float = float(i) / float(spread_bullet_count - 1) if spread_bullet_count > 1 else 0.5
		var dir: Vector2 = Vector2.DOWN.rotated(lerp(-half_arc, half_arc, t))
		var bullet: Node2D = plane_bullet_scene.instantiate()
		_spawn_projectile(bullet, dir * spread_bullet_speed)


func _fire_missile() -> void:
	if not homing_missile_scene:
		push_warning("MilitaryPlane: homing_missile_scene not assigned!")
		return

	for i in range(missile_count):
		var missile: Node2D = homing_missile_scene.instantiate()
		_spawn_projectile(missile, Vector2.DOWN * 30.0)


func _spawn_projectile(projectile: Node2D, initial_velocity: Vector2) -> void:
	var level: Node = get_tree().get_first_node_in_group("level")
	if not level:
		push_warning("MilitaryPlane: No node in 'level' group found!")
		projectile.queue_free()
		return

	level.add_child(projectile)
	projectile.global_position = global_position

	if projectile is CharacterBody2D:
		(projectile as CharacterBody2D).velocity = initial_velocity
	elif projectile is RigidBody2D:
		(projectile as RigidBody2D).linear_velocity = initial_velocity


# ── Internal ───────────────────────────────────────────────────────────────

func _finish_pass() -> void:
	active  = false
	visible = false
	_set_sprites_visible(false, false)
	pass_completed.emit()


func _set_sprites_visible(spread_vis: bool, missile_vis: bool) -> void:
	if _spread_sprite:
		_spread_sprite.visible = spread_vis
	if _missile_sprite:
		_missile_sprite.visible = missile_vis


func _set_sprite_flip(flip: bool) -> void:
	for sprite: Node in [_spread_sprite, _missile_sprite]:
		if sprite is Sprite2D:
			(sprite as Sprite2D).flip_h = flip
		elif sprite is AnimatedSprite2D:
			(sprite as AnimatedSprite2D).flip_h = flip
