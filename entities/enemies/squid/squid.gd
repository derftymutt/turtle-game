extends BaseEnemy
class_name Squid

## Wall-lurking squid that's hard to pin down and blinds the turtle with ink.
##
## States:
##   HIDE   — tucked into a wall (a DeadWall face, or any collidable
##            TileMapLayer: ocean walls, ocean floor, level wall tiles). Only
##            one tentacle pokes out, angled to the wall's normal. Spit doesn't
##            hurt it — spit or touch makes it THRUST (touch still costs the
##            turtle a heart).
##   THRUST — a fast straight jet (~a quarter of the screen) in the least
##            obstructed direction, away from the turtle where possible,
##            leaving an InkCloud where it started. Invulnerable.
##   SWIM   — flees the turtle while heading for a fresh wall spot, and hides
##            again once it arrives — but never sooner than min_swim_time.
##            Spit hurts it here, and also sets off another THRUST (and ink).
##
## Hiding holds the body in place by velocity rather than RigidBody2D.freeze,
## because Time Freeze and EnemyShock save and restore `freeze` themselves.

const _INK_CLOUD_SCENE = preload("res://entities/enemies/squid/ink_cloud.tscn")

## Sprite offsets, in the sheet's own (unrotated) pixels. The art points up.
## Hide: the sprite is turned so the frame's right side faces the wall, and
## the pivot is on the art's flat right edge (x = 17, level with the thin end
## at y = 30 in its 32×44 frame) — so that edge sits on the wall surface
## whatever the wall's angle.
const _HIDE_SPRITE_OFFSET := Vector2(-1.0, -8.0)
## Hide sprite rotation relative to the wall normal: a quarter turn clockwise
## from upright, so the tentacle runs along the wall and curls up off it.
const _HIDE_SPRITE_TURN := PI
## Middle of the tentacle art relative to that pivot (unrotated sheet
## pixels) — the hidden body/hitbox sits here.
const _HIDE_ART_CENTER := Vector2(-8.0, -12.0)
## How far the hide art runs along the wall from the pivot (toward frame -y:
## the tentacle spans y 6–30 of its frame, pivot at 30)
const _HIDE_ART_LENGTH := 24.0
## Keeps the tentacle this far in from a dead wall's ends (rounded caps)
const _DEAD_WALL_END_MARGIN := 3.0
const _SWIM_SPRITE_OFFSET := Vector2(0.0, 4.0)
const _THRUST_SPRITE_OFFSET := Vector2(0.0, 1.0)

@export_group("Thrust")
## Jet length — a quarter of the 640px screen
@export var thrust_distance: float = 160.0
@export var thrust_duration: float = 0.45
## Directions sampled when picking where to jet
@export var thrust_directions: int = 16

@export_group("Swim")
@export var max_swim_speed: float = 75.0
@export var swim_acceleration: float = 260.0
## The turtle closer than this makes it swim away
@export var flee_range: float = 120.0
@export var flee_weight: float = 1.6
## Shortest time between a thrust ending and hiding again
@export var min_swim_time: float = 3.0
## How far it looks for a new wall to hide in
@export var hide_search_range: float = 240.0
## Re-checks its hide target this often (turtle got close, spot taken, …)
@export var retarget_interval: float = 1.0
## Gives up on a hide target it hasn't reached in this long, and avoids that
## spot for the next few picks
@export var target_timeout: float = 5.0
@export var steer_probe: float = 24.0
## Keeps at least this far below the surface
@export var min_depth: float = 24.0

@export_group("Hide")
## The tentacle's wall edge is sunk this far into the wall so it reads as
## coming out of it
@export var hide_embed: float = 1.0

enum State { HIDE, THRUST, SWIM, DYING }
var state: State = State.HIDE

## Where this squid is hiding or heading to hide. Other squids skip spots
## near it, so two never share a wall spot.
var claimed_spot: Vector2 = Vector2.ZERO
var has_claim: bool = false

var player: Node2D = null
var ocean: Ocean = null

var _hide_normal: Vector2 = Vector2.UP
## Just off the wall in front of claimed_spot, where the body fits without
## touching the wall. The squid swims here, then tucks in to claimed_spot
## (hidden squids don't collide with walls); a thrust starts from here too.
var _approach_point: Vector2 = Vector2.ZERO
var _hide_ready: bool = false  # false until it has a wall spot (hide_at or snap)
## Hide targets it recently failed to reach — skipped when picking a new one
var _failed_spots: Array[Vector2] = []
## Distance to _approach_point at the last retarget check, and how many
## checks in a row it hasn't got meaningfully closer
var _last_target_dist: float = INF
var _stalled_checks: int = 0
var _thrust_dir: Vector2 = Vector2.RIGHT
var _thrust_time: float = 0.0
var _swim_time: float = 0.0
var _target_time: float = 0.0
var _retarget_timer: float = 0.0

@onready var _body_shape: CollisionShape2D = $CollisionShape2D

func _enemy_ready():
	gravity_scale = 0.0
	linear_damp = 0.0  # velocity is steered directly in every state
	lock_rotation = true  # only the sprite turns, never the body
	mass = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE  # the jet is fast enough to skip through an 8px wall
	pass_through_player = true  # touching it makes it jet, it doesn't block

	max_health = 40.0
	current_health = max_health
	contact_damage = 15.0
	knockback_force = 200.0
	death_label = "a squid"
	add_to_group("squids")

	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")

	# Starts hidden; is_invincible also stops Bravado paying out for hits
	# that do nothing.
	is_invincible = true
	_play_anim("hide")

## Puts the squid in HIDE on a wall. `surface_point` is on the wall's face;
## `normal` points out of the wall. Used by SquidSpawner.
func hide_at(surface_point: Vector2, normal: Vector2) -> void:
	_claim(surface_point, normal)
	_enter_hide()

func _claim(surface_point: Vector2, normal: Vector2) -> void:
	_hide_normal = normal
	claimed_spot = _hide_body_position(surface_point, normal)
	_approach_point = _approach_position(surface_point, normal)
	has_claim = true
	_target_time = 0.0
	_last_target_dist = INF
	_stalled_checks = 0

func _physics_process(delta: float):
	match state:
		State.HIDE:
			_update_hide()
		State.THRUST:
			_update_thrust(delta)
		State.SWIM:
			_update_swim(delta)
		State.DYING:
			linear_velocity = Vector2.ZERO

# ---------------------------------------------------------------------------
# HIDE
# ---------------------------------------------------------------------------

func _enter_hide() -> void:
	state = State.HIDE
	_hide_ready = true
	is_invincible = true
	_failed_spots.clear()
	# claimed_spot is closer to the wall than the body's radius, so walls
	# would push it out — it holds its own position while hidden anyway.
	# Bullets still hit it (they mask the Enemies layer).
	collision_mask = 0
	linear_velocity = Vector2.ZERO
	global_position = claimed_spot
	if sprite:
		sprite.rotation = _hide_normal.angle() + _HIDE_SPRITE_TURN
		sprite.position = -hide_art_offset(_hide_normal)
		(sprite as AnimatedSprite2D).offset = _HIDE_SPRITE_OFFSET
		# Tentacle slides out of the wall (frame x is the out-of-wall axis)
		sprite.scale = Vector2(0.2, 1.0)
		create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.25)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play_anim("hide")

func _update_hide() -> void:
	# Placed by hand in a level (no hide_at) — tuck into the nearest wall
	if not _hide_ready:
		if not _snap_to_nearest_wall():
			_enter_swim()
		return
	# Hold still against knockback (bullets, shockwaves)
	linear_velocity = Vector2.ZERO
	global_position = claimed_spot

func _snap_to_nearest_wall() -> bool:
	var spots := find_hide_spots(get_world_2d(), global_position, hide_search_range, 24, _min_hide_y(), [get_rid()])
	var best: Dictionary = {}
	var best_dist := INF
	for spot in spots:
		var dist: float = global_position.distance_to(spot.position)
		if dist < best_dist and not _spot_taken(_hide_body_position(spot.position, spot.normal)):
			best_dist = dist
			best = spot
	if best.is_empty():
		return false
	hide_at(best.position, best.normal)
	return true

# ---------------------------------------------------------------------------
# THRUST
# ---------------------------------------------------------------------------

func _start_thrust() -> void:
	if state == State.HIDE:
		# Pop out clear of the wall before measuring which way is open.
		# Deferred: this can run inside the DamageArea's physics callback.
		global_position = _approach_point
		set_deferred("collision_mask", 1)
	_thrust_dir = _choose_thrust_direction()
	_spawn_ink()

	state = State.THRUST
	is_invincible = true
	_thrust_time = 0.0
	has_claim = false  # its old wall spot is free again
	if sprite:
		sprite.position = Vector2.ZERO
		sprite.scale = Vector2.ONE
		sprite.rotation = _thrust_dir.angle() + PI * 0.5
		(sprite as AnimatedSprite2D).offset = _THRUST_SPRITE_OFFSET
	_play_anim("thrust")
	linear_velocity = _thrust_dir * _thrust_speed(0.0)

## Linear slow-down that covers exactly thrust_distance over thrust_duration.
func _thrust_speed(t: float) -> float:
	return 2.0 * thrust_distance / thrust_duration * (1.0 - t)

func _update_thrust(delta: float) -> void:
	_thrust_time += delta
	var t := _thrust_time / thrust_duration
	if t >= 1.0:
		_enter_swim()
		return
	# Ran into something — the engine has already killed most of the velocity
	# we set last frame.
	var expected := _thrust_speed(t)
	if _thrust_time > 0.08 and linear_velocity.length() < expected * 0.3:
		_enter_swim()
		return
	linear_velocity = _thrust_dir * expected

## Samples directions around the squid and returns the one it can jet the
## furthest in (the full thrust_distance, ideally, without leaving the water),
## breaking ties by how directly it points away from the turtle.
func _choose_thrust_direction() -> Vector2:
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _body_shape.shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 1  # walls, floor, bumpers, flippers
	params.exclude = [get_rid()]

	var away := Vector2.ZERO
	if is_instance_valid(player):
		away = (global_position - player.global_position).normalized()
	var min_y := _min_hide_y()

	var best_open := Vector2.ZERO
	var best_open_score := -INF
	var best_any := Vector2.UP
	var best_any_score := -INF
	var jitter := randf() * TAU / thrust_directions
	for i in thrust_directions:
		var dir := Vector2.RIGHT.rotated(jitter + TAU * i / thrust_directions)
		params.motion = dir * thrust_distance
		var clear: float = space.cast_motion(params)[0] * thrust_distance
		# Don't jet out of the water
		if ocean and dir.y < 0.0:
			clear = minf(clear, maxf(0.0, (global_position.y - min_y) / -dir.y))
		var ratio := clear / thrust_distance
		var away_score := dir.dot(away) + randf() * 0.1
		if ratio >= 0.95 and away_score > best_open_score:
			best_open_score = away_score
			best_open = dir
		var any_score := ratio + away_score * 0.3
		if any_score > best_any_score:
			best_any_score = any_score
			best_any = dir
	return best_open if best_open != Vector2.ZERO else best_any

func _spawn_ink() -> void:
	var cloud := _INK_CLOUD_SCENE.instantiate() as Node2D
	var parent := get_parent() as Node2D
	cloud.position = parent.to_local(global_position) if parent else global_position
	# Deferred: a touch-triggered thrust runs inside the DamageArea's physics
	# callback, where adding the cloud's Area2D isn't allowed.
	get_parent().add_child.call_deferred(cloud)

# ---------------------------------------------------------------------------
# SWIM
# ---------------------------------------------------------------------------

func _enter_swim() -> void:
	state = State.SWIM
	is_invincible = false
	_swim_time = 0.0
	_retarget_timer = 0.0
	has_claim = false
	if not _is_phased:  # Phase Shifter restores the mask itself when it ends
		collision_mask = 1
	if sprite:
		sprite.position = Vector2.ZERO
		(sprite as AnimatedSprite2D).offset = _SWIM_SPRITE_OFFSET
	_play_anim(_swim_anim())

func _update_swim(delta: float) -> void:
	_swim_time += delta
	_target_time += delta
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		if has_claim:
			var dist := global_position.distance_to(_approach_point)
			var fleeing := is_instance_valid(player) and player.global_position.distance_to(global_position) < flee_range
			if dist < 4.0 or dist < _last_target_dist - 5.0 or fleeing:
				_stalled_checks = 0
			else:
				_stalled_checks += 1
			_last_target_dist = dist
		if has_claim and (_target_time > target_timeout or _stalled_checks >= 2):
			# Couldn't get there (wedged, or pushed around) — don't keep
			# fixating on it; the next pick skips it.
			_failed_spots.append(claimed_spot)
			if _failed_spots.size() > 4:
				_failed_spots.pop_front()
			has_claim = false
		if not has_claim or _target_compromised():
			_pick_hide_target()

	var desired := Vector2.ZERO
	var speed := max_swim_speed
	var probe := steer_probe
	if has_claim:
		var to_target := _approach_point - global_position
		var dist := to_target.length()
		if dist < 4.0:
			_target_time = 0.0  # made it — only waiting on min_swim_time
			if _swim_time >= min_swim_time:
				_enter_hide()
				return
			# Early — hover at the spot until min_swim_time is up
			speed = 0.0
		else:
			desired = to_target / dist
			speed = max_swim_speed * clampf(dist / 30.0, 0.25, 1.0)  # ease in to land on it
			# Near the target the wall it hides in would otherwise read as an
			# obstacle and steer it away
			probe = minf(steer_probe, dist)

	if is_instance_valid(player):
		var from_player: Vector2 = global_position - player.global_position
		var player_dist := from_player.length()
		if player_dist < flee_range and player_dist > 0.01:
			desired += from_player / player_dist * flee_weight * (1.0 - player_dist / flee_range)
			speed = max_swim_speed

	if ocean and ocean.get_depth(global_position) < min_depth:
		desired.y += 1.0

	var velocity_goal := Vector2.ZERO
	if desired != Vector2.ZERO:
		velocity_goal = _steer_toward(desired.normalized(), probe) * speed
	linear_velocity = linear_velocity.move_toward(velocity_goal, swim_acceleration * delta)

	# Point the mantle the way it's going
	if sprite and linear_velocity.length() > 10.0:
		sprite.rotation = lerp_angle(sprite.rotation, linear_velocity.angle() + PI * 0.5, 8.0 * delta)

## The turtle has moved in on the target, or another squid got there first.
func _target_compromised() -> bool:
	if is_instance_valid(player) and player.global_position.distance_to(claimed_spot) < flee_range * 0.75:
		return true
	return _spot_taken(claimed_spot)

func _pick_hide_target() -> void:
	var spots := find_hide_spots(get_world_2d(), global_position, hide_search_range, 24, _min_hide_y(), [get_rid()])
	var best_score := -INF
	var best: Dictionary = {}
	for spot in spots:
		var body_pos := _hide_body_position(spot.position, spot.normal)
		if _spot_taken(body_pos) or _recently_failed(body_pos):
			continue
		var score := randf() * 30.0 - 0.3 * global_position.distance_to(body_pos)
		if is_instance_valid(player):
			var player_pos: Vector2 = player.global_position
			var from_player := player_pos.distance_to(body_pos)
			if from_player < flee_range:
				continue
			score += minf(from_player, 300.0)
			# Don't route past the turtle to get there
			var nearest := Geometry2D.get_closest_point_to_segment(player_pos, global_position, body_pos)
			if player_pos.distance_to(nearest) < 50.0:
				score -= 200.0
		if score > best_score and _path_clear(_approach_position(spot.position, spot.normal)):
			best_score = score
			best = spot
	if best.is_empty():
		has_claim = false  # nothing reachable — keep fleeing and look again soon
		return
	_claim(best.position, best.normal)

## The hide-spot rays are thin — make sure the body itself can swim straight
## to `target` without getting wedged in a gap the ray slipped through.
func _path_clear(target: Vector2) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _body_shape.shape
	params.transform = Transform2D(0.0, global_position)
	params.motion = target - global_position
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_2d().direct_space_state.cast_motion(params)[0] >= 1.0

func _recently_failed(body_pos: Vector2) -> bool:
	for failed in _failed_spots:
		if failed.distance_to(body_pos) < 24.0:
			return true
	return false

# ---------------------------------------------------------------------------
# HIDE SPOTS
# ---------------------------------------------------------------------------

## Body position for hiding at `surface_point`: the tentacle's pivot is sunk
## hide_embed into the wall and the body sits on the middle of the art.
func _hide_body_position(surface_point: Vector2, normal: Vector2) -> Vector2:
	return surface_point - normal * hide_embed + hide_art_offset(normal)

## claimed_spot for this wall spot, pushed straight out from the wall until
## the body circle clears it.
func _approach_position(surface_point: Vector2, normal: Vector2) -> Vector2:
	var body_pos := _hide_body_position(surface_point, normal)
	var radius: float = (_body_shape.shape as CircleShape2D).radius
	var out := (body_pos - surface_point).dot(normal)
	return body_pos + normal * maxf(0.0, radius + 1.5 - out)

## Pivot → middle of the hide art, once the sprite is turned to a wall with
## this normal.
static func hide_art_offset(normal: Vector2) -> Vector2:
	return _HIDE_ART_CENTER.rotated(normal.angle() + _HIDE_SPRITE_TURN)

func _spot_taken(body_pos: Vector2) -> bool:
	for other in get_tree().get_nodes_in_group("squids"):
		if other == self or not is_instance_valid(other):
			continue
		var squid := other as Squid
		if squid.has_claim and squid.claimed_spot.distance_to(body_pos) < 40.0:
			return true
	return false

## Squids stay this far below the surface.
func _min_hide_y() -> float:
	return (ocean.surface_y if ocean else -INF) + min_depth

## Surfaces a squid can hide in: pinball dead walls and any collidable
## TileMapLayer (ocean walls, ocean floor, level wall tiles).
static func is_hideable_surface(collider: Object, normal: Vector2) -> bool:
	if collider is TileMapLayer:
		return true
	if collider is DeadWall:
		# The long faces only — not the 8px end caps
		var face := Vector2.UP.rotated(deg_to_rad((collider as DeadWall).get_collision_rotation_degrees()))
		return absf(face.dot(normal)) > 0.9
	return false

## `pos` (on a face of `wall`) moved along the wall just enough that the hide
## art — which runs _HIDE_ART_LENGTH from the pivot to one side — lies
## entirely within the wall's length. null if the wall is too short.
static func _fit_on_dead_wall(wall: DeadWall, pos: Vector2, normal: Vector2) -> Variant:
	var tangent := Vector2.RIGHT.rotated(deg_to_rad(wall.get_collision_rotation_degrees()))
	var half := wall.get_pixel_length() * 0.5 - _DEAD_WALL_END_MARGIN
	var t := (pos - wall.global_position).dot(tangent)
	# Which way along the tangent the art runs from the pivot (±1)
	var art_dir := Vector2.UP.rotated(normal.angle() + _HIDE_SPRITE_TURN).dot(tangent)
	var lo := -half + maxf(0.0, -art_dir) * _HIDE_ART_LENGTH
	var hi := half - maxf(0.0, art_dir) * _HIDE_ART_LENGTH
	if lo > hi:
		return null
	return pos + tangent * (clampf(t, lo, hi) - t)

## Casts `ray_count` rays out of `from` (rotated randomly each call) and
## returns every hideable wall hit within `max_distance` as
## {position, normal}: `position` is on the wall's face, `normal` points out
## of it. Spots above `min_y`, or with no room for a squid (something solid
## or another enemy in the way), are left out.
static func find_hide_spots(world: World2D, from: Vector2, max_distance: float, ray_count: int, min_y: float, exclude: Array[RID] = []) -> Array[Dictionary]:
	var space := world.direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(from, from)
	ray.collision_mask = 1  # walls, floor, bumpers, flippers
	ray.exclude = exclude

	var room := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	room.shape = circle
	room.collision_mask = 1 | 4  # world + enemies (urchins, other squids)
	room.exclude = exclude

	var spots: Array[Dictionary] = []
	var offset := randf() * TAU
	for i in ray_count:
		var dir := Vector2.RIGHT.rotated(offset + TAU * i / ray_count)
		ray.to = from + dir * max_distance
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var pos: Vector2 = hit.position
		var normal: Vector2 = hit.normal
		if pos.y < min_y or normal == Vector2.ZERO:
			continue
		if not is_hideable_surface(hit.collider, normal):
			continue
		if hit.collider is DeadWall:
			# Dead walls are short — slide the spot along the wall so the
			# whole tentacle fits on it instead of hanging off an end
			var fitted: Variant = _fit_on_dead_wall(hit.collider, pos, normal)
			if fitted == null:
				continue
			pos = fitted
		# Room for the tentacle: nothing solid over the art (checked a little
		# further out than its middle, which lies close along the wall)
		room.transform = Transform2D(0.0, pos + hide_art_offset(normal) + normal * 4.0)
		if not space.intersect_shape(room, 1).is_empty():
			continue
		spots.append({"position": pos, "normal": normal})
	return spots

# ---------------------------------------------------------------------------
# DAMAGE
# ---------------------------------------------------------------------------

## Hidden: startled, unhurt. Swimming: hurt, then jets off again.
## Thrusting: can't be touched.
func take_damage(amount: float):
	match state:
		State.HIDE:
			_start_thrust()
		State.SWIM:
			is_invincible = false
			super(amount)
			if state == State.SWIM:  # survived the hit
				_start_thrust()

## Touching it hurts the turtle, and startles the squid into jetting away —
## inking the turtle on the way out. Only fires when the contact-damage
## cooldown allows, so a turtle sitting on it isn't re-hit every frame.
func _deal_damage_to_player(target: Node2D):
	super(target)
	if state == State.HIDE or state == State.SWIM:
		_start_thrust()

## Multi-Beam would otherwise shock it whenever it's hidden (is_invincible).
func can_be_shocked() -> bool:
	return false

func _resume_animation_after_damage(animated_sprite: AnimatedSprite2D, _previous_animation: String, _previous_frame: int) -> void:
	match state:
		State.HIDE:
			animated_sprite.play("hide")
		State.THRUST:
			animated_sprite.play("thrust")
		_:
			animated_sprite.play(_swim_anim())

## Swimming look: near_death once one more spit would kill it (same 10hp
## threshold BaseEnemy uses), otherwise swim. Hide and thrust keep their own
## poses at any health.
func _swim_anim() -> String:
	if current_health <= 10.0 and sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames.has_animation("near_death"):
		return "near_death"
	return "swim"

func _play_anim(anim_name: String) -> void:
	if sprite is AnimatedSprite2D:
		var anim := sprite as AnimatedSprite2D
		if anim.sprite_frames and anim.sprite_frames.has_animation(anim_name):
			anim.play(anim_name)

func die():
	if state == State.DYING:
		return
	state = State.DYING
	has_claim = false
	current_health = 0.0
	linear_velocity = Vector2.ZERO
	_contact_players.clear()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	super()
