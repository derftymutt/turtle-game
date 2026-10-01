extends AnimatableBody2D
class_name RainbowFish

## A rainbow fish caught in a six-pack ring — the Rainbow Fish minigame's
## target (see RainbowFishSpawner). Not an enemy: it sits on the Enemies physics
## layer so spit hits it, but stays out of the "enemies" group, so homing spit,
## Shockwave, flippers etc. leave it alone.
##
## States:
##   TRAPPED — bounces around the ocean like a pool ball, pivoting jerkily at
##             the hip as it fights the ring. Only the ocean's four edges stop
##             it (walls, floor, surface) — it ghosts through bumpers, flippers
##             and dead walls. A spit hit or a super-speed hit from the
##             turtle emits `shot` (both free it); a plain bump does nothing.
##   FREED   — swims to the near end of its rainbow stripe, leaps out and
##             paints the stripe across the sky, then dives back in and goes.
##   AWAY    — freed but not painting (not the last of its colour to be
##             freed): darts off and fades.
##   DEAD    — belly up, floats a little and fades.
##
## The body is moved by hand (sync_to_physics off, collision_mask 0) — it
## never pushes or gets pushed by anything.

signal shot(fish: RainbowFish)
## Finished painting its stripe (or vanished partway when the rainbow broke).
signal painting_finished(fish: RainbowFish)

const _TRAPPED_SHEET = preload("res://entities/npcs/rainbow_fish/sprites/rainbow_fish_trapped.png")
## Drop the freed art here (same layout: 24×24 frames, 2 per colour, ROYGBIV)
## and it's picked up automatically. Until then freed fish reuse the trapped art.
const _FREED_SHEET_PATH := "res://entities/npcs/rainbow_fish/sprites/rainbow_fish_freed.png"
const _DIE_SFX = preload("res://assets/sounds/sfx/dead enemy_1.ogg")
const _OUTLINE_SHADER = preload("res://entities/npcs/rainbow_fish/target_outline.gdshader")
const _FRAME_SIZE := 24
const _FRAMES_PER_COLOR := 2

## The art is drawn upright; the hip (where the struggle pivots) sits this far
## below the frame centre.
const _HIP_OFFSET := 5.0

## ROYGBIV, index = colour_index
const COLORS: Array[Color] = [
	Color(0.89, 0.16, 0.18),  # red
	Color(0.98, 0.52, 0.10),  # orange
	Color(1.00, 0.90, 0.15),  # yellow
	Color(0.35, 0.80, 0.20),  # green
	Color(0.30, 0.62, 1.00),  # blue
	Color(0.28, 0.25, 0.65),  # indigo
	Color(0.62, 0.30, 0.70),  # violet
]
const COLOR_NAMES: Array[String] = ["red", "orange", "yellow", "green", "blue", "indigo", "violet"]

@export_group("Trapped")
## Base cruising speed while trapped (px/s, before the jerk surges)
@export var swim_speed: float = 35.0
## Each jerk surges the speed to this multiple, easing back to the low point
@export var surge_multiplier: float = 1.5
@export var surge_low: float = 0.75
## Seconds between hip jerks (random in range)
@export var jerk_interval_min: float = 0.12
@export var jerk_interval_max: float = 0.62
## Hip swing either side of upright, degrees (random in range)
@export var jerk_angle_min: float = 14.0
@export var jerk_angle_max: float = 30.0
## Distance kept between the body centre and the ocean's edges
@export var edge_radius: float = 8.0
## Seconds between horizontal flips (random in range) — part of the squirm
@export var flip_interval_min: float = 0.4
@export var flip_interval_max: float = 1.3

@export_group("Freed")
@export var freed_swim_speed: float = 260.0
## Seconds to travel the whole stripe
@export var arc_duration: float = 2.2
## How far below the surface it lines up before leaping out
@export var surface_line_up_depth: float = 10.0
## Seconds an AWAY fish swims before it's gone
@export var swim_away_time: float = 1.2

@export_group("Target Pulse")
## Pulses per second while this is the colour to free next
@export var target_pulse_rate: float = 3.0
## Outline drawn around the target fish (its own colours are left alone)
@export var target_outline_color: Color = Color.WHITE
## Outline opacity at the dim point of the pulse — never fully off, so it
## reads at any instant
@export_range(0.0, 1.0) var target_outline_min: float = 0.6
## Size throb at the top of the pulse (0.15 = 15% bigger)
@export var target_pulse_scale: float = 0.15

enum State { TRAPPED, FREED_SWIM, FREED_ARC, FREED_DIVE, AWAY, DEAD }
var state: State = State.TRAPPED

var color_index: int = 0
## The colour that has to be freed next — pulses bright while trapped.
## Set by RainbowFishSpawner.
var is_target: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _surge: float = 1.0
var _jerk_timer: float = 0.0
var _flip_timer: float = 0.0
var _popped_in: bool = false  # the target throb waits for the pop-in tween
var _outline: ShaderMaterial = null
var _jerk_side: float = 1.0
var _jerk_target: float = 0.0

var _arc: RainbowArc = null
var _from_left: bool = true
var _arc_t: float = 0.0
var _dive_time: float = 0.0
var _away_time: float = 0.0

var _ocean: Ocean = null

static var _frames_cache: Dictionary = {}

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("rainbow_fish")
	_ocean = get_tree().get_first_node_in_group("ocean")
	_sprite.sprite_frames = _frames_for(color_index)
	# Pivot at the hip rather than the frame centre
	_sprite.offset = Vector2(0.0, -_HIP_OFFSET)
	_sprite.position = Vector2(0.0, _HIP_OFFSET)
	_sprite.play("trapped")
	_outline = ShaderMaterial.new()
	_outline.shader = _OUTLINE_SHADER
	_outline.set_shader_parameter("outline_color", target_outline_color)
	_sprite.material = _outline

	# Pop in
	_sprite.scale = Vector2.ZERO
	_sprite.modulate = Color(3.0, 3.0, 3.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.4)
	tween.chain().tween_callback(func(): _popped_in = true)

## Call before adding to the tree. `direction` is the starting heading.
func setup(index: int, direction: Vector2) -> void:
	color_index = index
	_dir = direction.normalized()

func get_color() -> Color:
	return COLORS[color_index]

func is_trapped() -> bool:
	return state == State.TRAPPED

## Freed and on its way to paint, or painting — not yet diving out.
func is_painting() -> bool:
	return state == State.FREED_SWIM or state == State.FREED_ARC

## Target marker: a pulsing outline (target_outline.gdshader) plus a size
## throb. A plain sine with no rest beat, and the outline never fully fades,
## so it reads at any instant.
func _process(_delta: float) -> void:
	var marked := is_target and state == State.TRAPPED
	var wave := (sin(Time.get_ticks_msec() * 0.001 * TAU * target_pulse_rate) + 1.0) * 0.5
	_outline.set_shader_parameter("strength", lerpf(target_outline_min, 1.0, wave) if marked else 0.0)
	if _popped_in and state == State.TRAPPED:
		_sprite.scale = Vector2.ONE * (1.0 + target_pulse_scale * wave if marked else 1.0)

func _physics_process(delta: float) -> void:
	# Time Freeze stops it like everything else in the water
	var frozen := AlienTechManager.time_freeze_active and state != State.DEAD
	_sprite.speed_scale = 0.0 if frozen else 1.0
	if frozen:
		return
	match state:
		State.TRAPPED:
			_update_struggle(delta)
			_move_trapped(delta)
		State.FREED_SWIM:
			_update_freed_swim(delta)
		State.FREED_ARC:
			_update_arc(delta)
		State.FREED_DIVE:
			_update_dive(delta)
		State.AWAY:
			_update_away(delta)

# ---------------------------------------------------------------------------
# TRAPPED
# ---------------------------------------------------------------------------

## Hip jerks: snap to one side, hold, snap to the other — each snap kicks a
## little surge of speed.
func _update_struggle(delta: float) -> void:
	_jerk_timer -= delta
	if _jerk_timer <= 0.0:
		_jerk_timer = randf_range(jerk_interval_min, jerk_interval_max)
		_jerk_side = -_jerk_side
		_jerk_target = _jerk_side * deg_to_rad(randf_range(jerk_angle_min, jerk_angle_max))
		_surge = surge_multiplier
	_sprite.rotation = lerp_angle(_sprite.rotation, _jerk_target, 1.0 - exp(-28.0 * delta))
	_surge = move_toward(_surge, surge_low, 2.5 * delta)
	_flip_timer -= delta
	if _flip_timer <= 0.0:
		_flip_timer = randf_range(flip_interval_min, flip_interval_max)
		_sprite.flip_h = not _sprite.flip_h

## Straight line, perfect reflection off the ocean's edges.
func _move_trapped(delta: float) -> void:
	var motion := _dir * swim_speed * _surge * delta
	var hit := find_ocean_wall_hit(get_world_2d(), global_position, motion + _dir * edge_radius, [get_rid()])
	if not hit.is_empty():
		var normal: Vector2 = hit.normal
		_dir = _dir.bounce(normal).normalized()
		global_position = (hit.position as Vector2) + normal * (edge_radius + 0.5)
	else:
		global_position += motion

	if _ocean:
		var top := _ocean.surface_y + edge_radius
		var bottom := _ocean.floor_y - edge_radius
		if global_position.y < top:
			global_position.y = top
			_dir.y = absf(_dir.y)
		elif global_position.y > bottom:
			global_position.y = bottom
			_dir.y = -absf(_dir.y)

## The turtle's SuperSpeedArea hit it during super speed (or its cooldown
## window, which still shows the green trail) — frees it like spit does.
## Bumping it at normal speed never gets here: the turtle doesn't collide
## with the Enemies layer.
func on_super_speed_contact(_turtle: Node2D) -> void:
	on_shot()

## Spit hit it (bullet.gd, laser_bullet.gd, phase_bullet.gd), or a super-speed
## hit (on_super_speed_contact).
func on_shot() -> void:
	if state == State.TRAPPED:
		shot.emit(self)

# ---------------------------------------------------------------------------
# FREED
# ---------------------------------------------------------------------------

## The ring's off — swim to the near end of stripe `color_index` on `arc` and
## paint it.
func release(arc: RainbowArc) -> void:
	if state != State.TRAPPED:
		return
	_arc = arc
	_from_left = global_position.x < arc.center.x
	_stop_colliding()
	state = State.FREED_SWIM
	z_index = 3  # in front of the stripes and the ocean art
	_sprite.play("freed")
	_sprite.speed_scale = 2.0
	# Burst of joy
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.3)

func _arc_start() -> Vector2:
	return _arc.stripe_point(color_index, 0.0 if _from_left else 1.0)

func _update_freed_swim(delta: float) -> void:
	if not is_instance_valid(_arc):
		vanish()
		return
	var target := _arc_start() + Vector2(0.0, surface_line_up_depth)
	var to_target := target - global_position
	var step := freed_swim_speed * delta
	if to_target.length() <= step:
		global_position = target
		state = State.FREED_ARC
		_arc_t = 0.0
		return
	var dir := to_target.normalized()
	global_position += dir * step
	# Head first, with an excited wiggle
	var wiggle := sin(Time.get_ticks_msec() * 0.03) * 0.35
	_sprite.rotation = dir.angle() + PI * 0.5 + wiggle

func _update_arc(delta: float) -> void:
	if not is_instance_valid(_arc):
		vanish()
		return
	_arc_t = minf(1.0, _arc_t + delta / arc_duration)
	var t := _arc_t if _from_left else 1.0 - _arc_t
	var pos := _arc.stripe_point(color_index, t)
	var ahead := _arc.stripe_point(color_index, clampf(t + (0.01 if _from_left else -0.01), 0.0, 1.0))
	var dir := (ahead - pos).normalized()
	if _arc_t >= 1.0:
		dir = Vector2.DOWN  # end of the stripe: nose into the water
	global_position = pos
	_sprite.rotation = dir.angle() + PI * 0.5
	_arc.paint(color_index, _arc_t, _from_left)
	if _arc_t >= 1.0:
		state = State.FREED_DIVE
		_dive_time = 0.0

func _update_dive(delta: float) -> void:
	_dive_time += delta
	global_position.y += freed_swim_speed * 0.5 * delta
	_sprite.rotation = PI  # head down
	_sprite.modulate.a = 1.0 - _dive_time / 0.4
	if _dive_time >= 0.4:
		painting_finished.emit(self)
		queue_free()

## Freed without a stripe to paint — darts off along its heading (away from
## the turtle if it's close) and fades out.
func swim_away() -> void:
	if state != State.TRAPPED:
		return
	_stop_colliding()
	state = State.AWAY
	_away_time = 0.0
	z_index = 3
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.distance_to(global_position) < 80.0:
		_dir = (global_position - player.global_position).normalized()
	_sprite.play("freed")
	_sprite.speed_scale = 2.0
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.3)

func _update_away(delta: float) -> void:
	_away_time += delta
	global_position += _dir * freed_swim_speed * delta
	var wiggle := sin(Time.get_ticks_msec() * 0.03) * 0.35
	_sprite.rotation = _dir.angle() + PI * 0.5 + wiggle
	modulate.a = clampf((swim_away_time - _away_time) / 0.4, 0.0, 1.0)
	if _away_time >= swim_away_time:
		queue_free()

## The rainbow broke while this one was on its way or painting — fade out.
func vanish() -> void:
	if state == State.DEAD:
		return
	var was_freed := state != State.TRAPPED
	state = State.DEAD
	_stop_colliding()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
	if was_freed:
		painting_finished.emit(self)

# ---------------------------------------------------------------------------
# DEATH
# ---------------------------------------------------------------------------

## Dies where it is: belly up, drifts up a touch, fades.
func die_in_place() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_stop_colliding()
	_sprite.stop()
	_play_die_sound()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "rotation", PI, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "modulate", Color(0.6, 0.6, 0.6, 0.0), 1.2).set_delay(0.3)
	tween.tween_property(self, "global_position:y", global_position.y - 16.0, 1.5)
	tween.chain().tween_callback(queue_free)

func _stop_colliding() -> void:
	# Deferred: can run inside a physics callback (bullet contact, super speed)
	set_deferred("collision_layer", 0)

func _play_die_sound() -> void:
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _DIE_SFX
	sfx.volume_db = -8.0
	sfx.pitch_scale = 1.4
	get_parent().add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

## The ocean's walls and floor: tile layers (ocean walls, floor, level wall
## tiles) and the level's WorldSafetyBoundaries. Bumpers, flippers and dead
## walls share layer 1 but aren't edges of the ocean.
static func is_ocean_wall(collider: Object) -> bool:
	if collider is TileMapLayer:
		return true
	var node := collider as Node
	return node != null and node.get_parent() != null and node.get_parent().name == "WorldSafetyBoundaries"

## First ocean wall along `from` → `from + motion`, looking past everything
## else on layer 1. {} if none, else the intersect_ray result.
static func find_ocean_wall_hit(world: World2D, from: Vector2, motion: Vector2, exclude: Array[RID] = []) -> Dictionary:
	var space := world.direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, from + motion, 1)
	var skip: Array[RID] = exclude.duplicate()
	for _i in 8:
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if is_ocean_wall(hit.collider):
			return hit
		skip.append(hit.rid)
	return {}

static func _frames_for(index: int) -> SpriteFrames:
	if _frames_cache.has(index):
		return _frames_cache[index]
	var freed_sheet: Texture2D = _TRAPPED_SHEET
	if ResourceLoader.exists(_FREED_SHEET_PATH):
		freed_sheet = load(_FREED_SHEET_PATH)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in ["trapped", "freed"]:
		var sheet: Texture2D = _TRAPPED_SHEET if anim == "trapped" else freed_sheet
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 6.0)
		frames.set_animation_loop(anim, true)
		for f in _FRAMES_PER_COLOR:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2((index * _FRAMES_PER_COLOR + f) * _FRAME_SIZE, 0, _FRAME_SIZE, _FRAME_SIZE)
			frames.add_frame(anim, atlas)
	_frames_cache[index] = frames
	return frames
