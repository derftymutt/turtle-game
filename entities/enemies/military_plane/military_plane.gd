# military_plane.gd
extends Node2D
class_name MilitaryPlane

## Invincible military plane that flies horizontally through the sky
## and fires at the turtle. Two variants:
##
##   SPREAD  — fires a 3-bullet spread arc, twice per pass
##   MISSILE — fires a single homing missile, once per pass
##
## The plane is a plain Node2D with no physics body — it cannot be hit.
## Projectiles are spawned directly into the level root so they persist
## independently after the plane exits.
##
## SCENE SETUP:
##   Add two sprite children named "SpreadSprite" and "MissileSprite".
##   Only the active one is shown during a pass.
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
@export var fly_speed: float = 220.0

@export_group("Spread Shot")
@export var spread_bullet_count: int = 3
## Total arc width in degrees. 40° gives a readable fan.
@export var spread_angle_deg: float = 40.0
@export var spread_bullet_speed: float = 300.0
## How many times the plane fires during one spread pass.
@export var spread_shot_count: int = 2

@export_group("Homing Missile")
@export var missile_count: int = 1

# ── Internal State ─────────────────────────────────────────────────────────
var active: bool = false
var plane_type: PlaneType = PlaneType.SPREAD
var travel_direction: float = 1.0  # +1 = left→right, -1 = right→left
var target_x: float = 0.0

var _fire_x_positions: Array[float] = []
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

	# Fire when crossing pre-calculated X positions
	if _fired_count < _fire_x_positions.size():
		var next_fire_x: float = _fire_x_positions[_fired_count]
		var crossed: bool = (travel_direction > 0.0 and position.x >= next_fire_x) \
						 or (travel_direction < 0.0 and position.x <= next_fire_x)
		if crossed:
			if plane_type == PlaneType.SPREAD:
				_fire_spread()
			else:
				_fire_missile()
			_fired_count += 1

	# End pass once off the far side of the screen
	var exited: bool = (travel_direction > 0.0 and position.x > target_x) \
					or (travel_direction < 0.0 and position.x < target_x)
	if exited:
		_finish_pass()


# ── Public API ─────────────────────────────────────────────────────────────

func launch(type: PlaneType = PlaneType.SPREAD, from_left: bool = true) -> void:
	if active:
		return

	plane_type       = type
	travel_direction = 1.0 if from_left else -1.0

	# Use half the viewport width to place the plane just off screen.
	# position (local) is used throughout — the plane is a direct child of
	# the level root, so local and global coords are identical.
	var half_w: float = get_viewport_rect().size.x / 2.0
	position = Vector2(
		(-half_w - spawn_x_margin) if from_left else (half_w + spawn_x_margin),
		fly_y
	)
	target_x = (half_w + spawn_x_margin) if from_left else (-half_w - spawn_x_margin)

	_set_sprite_flip(travel_direction < 0.0)
	_set_sprites_visible(type == PlaneType.SPREAD, type == PlaneType.MISSILE)

	# Pre-calculate X positions where the plane fires.
	# Shots are distributed evenly across the visible screen width.
	_fired_count = 0
	_fire_x_positions.clear()

	var shot_count: int = spread_shot_count if type == PlaneType.SPREAD else missile_count
	for i in range(shot_count):
		var frac: float = float(i + 1) / float(shot_count + 1)
		var fire_x: float = lerp(-half_w, half_w, frac)
		# For right→left passes, mirror the positions
		_fire_x_positions.append(fire_x if from_left else -fire_x)

	if not from_left:
		_fire_x_positions.reverse()

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
