extends AlienTechEffect
class_name MultiLanceEffect

## Multi Lance — fires a short lance (a fifth of the screen wide) in the aimed
## direction (stick, then momentum, then facing — same priority as Transporter).
## What it does depends on the FIRST thing the lance strikes:
##   enemy          — 20 damage (double a basic bullet), lance retracts.
##                    Invincible enemies (crocodile, sea urchin) can't be hurt,
##                    so they're shocked instead: frozen and harmless for
##                    SHOCK_DURATION (see EnemyShock).
##   air bubble     — pops it (same as a bullet), lance retracts
##   solid          — wall / floor / boundary / flipper / bumper: hauls the
##                    turtle to the contact point at PULL_SPEED
##   pickup         — UFO piece, powerup, alien tech piece, health plant: reels
##                    it to the turtle at PULL_SPEED until it's collected
##   trash          — trash item, trash bag (cluster), cluster piece, space
##                    debris: triggers it as if shot (a bag takes CLUSTER_HITS
##                    hits — enough to burst it), lance retracts
##   nothing        — lance retracts
## Hot adds Sky Hook: a lance that reaches nothing but ends above the ocean
## surface anchors on the empty air and hauls the turtle there, and the
## cooldown is halved.
##
## The strike is resolved instantly on press (a raycast, not a travelling
## projectile); the line then animates out to the contact point and the
## outcome is applied when the tip lands.
##
## Damage ends everything at once (see cancel_on_damage()). The cooldown does
## NOT start on press — AlienTechManager holds it full (_HOLD_COOLDOWN_TECHS)
## until _end() releases it, so it runs from the end of the whole sequence.
## A lance that did nothing (hit nothing, struck something it couldn't act on,
## or its target vanished) is cut down to MISS_COOLDOWN when it's released.
##
## `pulling` and `pulling_player` are read directly by TurtlePlayer (thrust
## lockout / ocean-physics suppression), same public-flag convention as the
## other effects.

const REACH: float = 128.0            # a fifth of the 640px viewport
const DAMAGE: float = 20.0
const MISS_COOLDOWN: float = 1.0      # cooldown after a lance that did nothing (never longer than the normal one)
const SHOCK_DURATION: float = 5.0     # invincible enemies: frozen + harmless this long
const PULL_SPEED: float = 150.0       # well under super_speed_threshold (300)
const PLAYER_RADIUS: float = 7.0
const STANDOFF: float = PLAYER_RADIUS + 1.0  # stop this far off a struck surface
const ARRIVE_DISTANCE: float = 3.0
const EXTEND_TIME: float = 0.08
const RETRACT_TIME: float = 0.10
const STUCK_TIMEOUT: float = 0.4      # no closing progress for this long = give up
const MAX_PULL_TIME: float = 3.0
const HEALTH_PLANT_HIT_RADIUS: float = 11.0  # matches HealthPlant's Area2D circle
const CLUSTER_HITS: int = 3           # = TrashCluster.max_hits, so one lance strike bursts a bag outright

# The beam is BEAM_WIDTH wide: three parallel rays BEAM_HALF_WIDTH apart, so the
# strike area matches the drawn line.
const BEAM_WIDTH: float = 4.0
const BEAM_HALF_WIDTH: float = BEAM_WIDTH * 0.5

# World_Player (walls, floor, boundaries, flippers, bumpers — and enemies, which
# also sit on it), Collectibles, Enemies, CloudFlippers, Trash. Trash is also
# where OceanFlora lives; _classify() lets the lance pass through that.
const RAY_MASK: int = 1 | 2 | 4 | 16 | 128
const MAX_RAY_SKIPS: int = 8

const TRASH_GROUPS: Array[String] = ["trash_items", "trash_clusters", "trash_cluster_pieces", "space_debris"]

enum State { IDLE, EXTENDING, PULLING_PLAYER, PULLING_ITEM, RETRACTING }
enum Kind { NONE, DUD, ENEMY, BUBBLE, TRASH, SOLID, ITEM, PLANT, AIR }

var pulling: bool = false          # true during either pull — thrust is locked out
var pulling_player: bool = false   # true only while the turtle itself is hauled

var _state: State = State.IDLE
var _whiffed: bool = false   # the lance did nothing — see MISS_COOLDOWN
var _kind: Kind = Kind.NONE
# Untyped on purpose: enemies, bubbles, rigid pickups and health plants share
# no base class, and each is called through its own duck-typed method.
var _target = null
var _tip_point: Vector2 = Vector2.ZERO   # where the visible line ends (contact point)
var _anchor: Vector2 = Vector2.ZERO      # where the turtle is hauled to (PULLING_PLAYER)
var _timer: float = 0.0
var _pull_elapsed: float = 0.0
var _best_dist: float = INF
var _stuck_timer: float = 0.0
var _line: Line2D = null

func setup(player) -> void:
	_line = Line2D.new()
	# top_level so the turtle's free spin doesn't rotate the line; points are
	# global coordinates.
	_line.top_level = true
	_line.width = BEAM_WIDTH
	_line.default_color = Color(0.3, 1.0, 0.85)
	_line.z_as_relative = false
	_line.z_index = 14  # over motion trails, under the turtle sprite (15)
	_line.visible = false
	player.add_child(_line)

func activate(player, _slot_index: int) -> void:
	if _state != State.IDLE:
		return

	var origin: Vector2 = player.global_position
	var dir: Vector2 = _aim_direction(player)
	var result: Dictionary = _cast(player, origin, dir)

	# Sky Hook (hot): a lance that reached nothing but ends above the surface
	# treats the empty air as a solid anchor.
	if result.kind == Kind.NONE and AlienTechManager.is_tech_hot(AlienTechRegistry.MULTI_LANCE):
		var end: Vector2 = origin + dir * REACH
		if player.ocean and end.y < player.ocean.surface_y:
			var air_point: Vector2 = player._clamp_to_boundaries(end)
			result = {"kind": Kind.AIR, "point": air_point, "anchor": air_point, "node": null}

	_kind = result.kind
	_target = result.node
	_whiffed = _kind == Kind.NONE or _kind == Kind.DUD
	_tip_point = result.point
	_anchor = result.get("anchor", result.point)
	_timer = 0.0
	_state = State.EXTENDING
	player.get_node("SfxShoot").play()
	_draw_line(origin, origin)

func physics_process(player, delta: float) -> void:
	if _state == State.IDLE:
		return
	var origin: Vector2 = player.global_position
	match _state:
		State.EXTENDING:
			_timer += delta
			var t: float = minf(_timer / EXTEND_TIME, 1.0)
			_draw_line(origin, origin.lerp(_tip_point, t))
			if t >= 1.0:
				_land()
		State.PULLING_PLAYER:
			_tick_pull_player(player, origin, delta)
		State.PULLING_ITEM:
			_tick_pull_item(player, origin, delta)
		State.RETRACTING:
			_timer += delta
			var t: float = minf(_timer / RETRACT_TIME, 1.0)
			_draw_line(origin, origin.lerp(_tip_point, 1.0 - t))
			if t >= 1.0:
				_end()

## Real damage lands — the lance is destroyed and everything it was doing stops.
func cancel_on_damage(_player) -> void:
	if _state != State.IDLE:
		_whiffed = false  # getting hurt earns no cooldown discount
		_end()

## Tech swapped out mid-lance.
func on_slots_changed(_player) -> void:
	if _state != State.IDLE and not AlienTechManager.has_tech(AlienTechRegistry.MULTI_LANCE):
		_end()

# ---------------------------------------------------------------------------
# AIMING + STRIKE RESOLUTION
# ---------------------------------------------------------------------------

## Direction priority: active input > current velocity > facing direction.
func _aim_direction(player) -> Vector2:
	var movement_input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if movement_input.length() > 0.1:
		var dir: Vector2 = movement_input.normalized()
		if GameSettings.thrust_inverted:
			dir = -dir
		return dir
	var vel: Vector2 = player.linear_velocity
	if vel.length() > 30.0:
		return vel.normalized()
	return player._direction_suffix_to_vector(player.facing_direction)

## Finds the first thing the beam strikes. Returns
## {kind, point, node} (+ "anchor" for SOLID).
func _cast(player, origin: Vector2, dir: Vector2) -> Dictionary:
	var end: Vector2 = origin + dir * REACH
	var result: Dictionary = {"kind": Kind.NONE, "point": end, "node": null}
	var strike_dist: float = REACH  # distance along dir to whatever currently wins

	# Three parallel rays make up the beam; the nearest strike wins (the centre
	# ray goes first, so it wins ties).
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var side: Vector2 = dir.orthogonal() * BEAM_HALF_WIDTH
	for offset: Vector2 in [Vector2.ZERO, side, -side]:
		var hit: Dictionary = _cast_ray(player, space, origin + offset, dir)
		if hit.is_empty():
			continue
		var point: Vector2 = hit.point
		var along: float = (point - origin).dot(dir)
		if along >= strike_dist:
			continue
		strike_dist = along
		# The drawn tip sits on the beam's centre line.
		result = {"kind": hit.kind, "point": origin + dir * along, "node": hit.node}
		if hit.kind == Kind.SOLID:
			result["anchor"] = point + (hit.normal as Vector2) * STANDOFF

	# Health plants have no physics body (a Node2D with a bare Area2D), so the
	# rays can't see them — test them geometrically and let the nearer strike win.
	for plant in player.get_tree().get_nodes_in_group("health_plants"):
		if not _is_live(plant):
			continue
		var d: float = _ray_circle_dist(origin, dir, REACH, plant.global_position, HEALTH_PLANT_HIT_RADIUS + BEAM_HALF_WIDTH)
		if d >= 0.0 and d < strike_dist:
			strike_dist = d
			result = {"kind": Kind.PLANT, "point": origin + dir * d, "node": plant}

	return result

## One ray of the beam. Things that aren't real targets (stars, sky stars,
## ocean flora…) and the turtle itself are excluded and the ray re-cast, so they
## can't shadow a wall or enemy behind them. Returns {} for no strike, else
## {kind, point, normal, node}.
func _cast_ray(player, space: PhysicsDirectSpaceState2D, from: Vector2, dir: Vector2) -> Dictionary:
	var to: Vector2 = from + dir * REACH
	var exclude: Array[RID] = [player.get_rid()]
	for _i in MAX_RAY_SKIPS:
		var query := PhysicsRayQueryParameters2D.create(from, to, RAY_MASK, exclude)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider = hit.collider
		var kind: Kind = _classify(collider)
		if kind == Kind.NONE:  # not a target — skip it
			exclude.append(hit.rid)
			continue
		return {"kind": kind, "point": hit.position, "normal": hit.normal, "node": collider}
	return {}

## Maps a ray collider to a Kind. NONE means "not a target, look past it".
func _classify(collider) -> Kind:
	# Groups first: enemies also sit on the World_Player layer, so the layer
	# alone would misread them as walls.
	if collider.is_in_group("enemies"):
		return Kind.ENEMY if collider.has_method("take_damage") else Kind.DUD
	if collider.is_in_group("air_bubbles"):
		return Kind.BUBBLE if _is_live(collider) and collider.has_method("pop_from_bullet") else Kind.NONE
	if collider is UFOPiece:
		var piece := collider as UFOPiece
		if piece.is_carried or piece._drop_grace_timer > 0.0:
			return Kind.NONE
		# Hands full: the lance strikes it but can't reel it in.
		return Kind.ITEM if GameManager.can_carry_more_pieces() else Kind.DUD
	if collider is Powerup or collider is AlienTechPiece:
		return Kind.ITEM if _is_live(collider) else Kind.NONE
	if _is_trash(collider):
		return Kind.TRASH if _is_live(collider) else Kind.NONE
	if collider.is_in_group("collectibles"):
		return Kind.NONE  # stars, sky stars, … — not lance targets
	# Anything else on the world / cloud-flipper layers is solid (OceanFlora,
	# which shares the Trash layer, falls through to NONE here). TileMapLayer
	# (floor, walls) exposes no collision_layer of its own — treat it as solid.
	var layer = collider.get("collision_layer")
	if layer == null or (int(layer) & (1 | 16)) != 0:
		return Kind.SOLID
	return Kind.NONE

## Distance along the ray to a circle, or -1 if it misses.
static func _ray_circle_dist(origin: Vector2, dir: Vector2, length: float, center: Vector2, radius: float) -> float:
	var t: float = clampf((center - origin).dot(dir), 0.0, length)
	var d: float = (origin + dir * t).distance_to(center)
	if d > radius:
		return -1.0
	return maxf(0.0, t - sqrt(radius * radius - d * d))

# ---------------------------------------------------------------------------
# OUTCOMES
# ---------------------------------------------------------------------------

## The extending tip has landed — apply the outcome.
func _land() -> void:
	if _kind in [Kind.ENEMY, Kind.BUBBLE, Kind.TRASH, Kind.ITEM, Kind.PLANT] and not _is_live(_target):
		_whiffed = true  # gone (collected, destroyed, freed) before the tip landed
	match _kind:
		Kind.ENEMY:
			if _is_live(_target):
				if _can_shock(_target):
					_target.shock(SHOCK_DURATION)
				else:
					_target.take_damage(DAMAGE)
			_start_retract()
		Kind.BUBBLE:
			if _is_live(_target):
				_target.pop_from_bullet()
			_start_retract()
		Kind.TRASH:
			if _is_live(_target):
				_hit_trash(_target)
			_start_retract()
		Kind.SOLID, Kind.AIR:
			_state = State.PULLING_PLAYER
			pulling = true
			pulling_player = true
			_reset_pull_tracking()
		Kind.ITEM, Kind.PLANT:
			if not _is_live(_target):
				_start_retract()
				return
			_state = State.PULLING_ITEM
			pulling = true
			_reset_pull_tracking()
			if _kind == Kind.PLANT:
				_target.begin_lance_pull()
		_:
			_start_retract()

func _tick_pull_player(player, origin: Vector2, delta: float) -> void:
	_pull_elapsed += delta
	_draw_line(origin, _tip_point)
	var to_anchor: Vector2 = _anchor - origin
	var dist: float = to_anchor.length()
	if dist <= ARRIVE_DISTANCE:
		player.linear_velocity = Vector2.ZERO
		_end()
		return
	if _is_stuck(dist, delta):
		_end()
		return
	# Capped so the last frame can't overshoot the anchor.
	player.linear_velocity = to_anchor / dist * minf(PULL_SPEED, dist / delta)

func _tick_pull_item(_player, origin: Vector2, delta: float) -> void:
	if not _is_live(_target):
		_end()  # collected, freed, or otherwise gone — the sequence is done
		return
	_pull_elapsed += delta
	var item_pos: Vector2 = _target.global_position
	_draw_line(origin, item_pos)
	# Chrono Stasis freezes the item in place; don't count that as being stuck.
	if AlienTechManager.time_freeze_active:
		return
	var dist: float = origin.distance_to(item_pos)
	if _is_stuck(dist, delta):
		_end()
		return
	if _kind == Kind.PLANT:
		# HealthPlant is a plain Node2D — move it directly.
		_target.global_position = item_pos.move_toward(origin, PULL_SPEED * delta)
	elif dist > 1.0:
		_target.linear_velocity = (origin - item_pos) / dist * PULL_SPEED

func _reset_pull_tracking() -> void:
	_pull_elapsed = 0.0
	_best_dist = INF
	_stuck_timer = 0.0

## True when a pull has stopped making progress (wedged behind geometry, a
## carry-full pickup sitting on the turtle, …) or run far too long.
func _is_stuck(dist: float, delta: float) -> bool:
	if _pull_elapsed > MAX_PULL_TIME:
		return true
	if dist < _best_dist - 1.0:
		_best_dist = dist
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta
	return _stuck_timer > STUCK_TIMEOUT

func _start_retract() -> void:
	_state = State.RETRACTING
	_timer = 0.0

## Ends the whole sequence and lets the cooldown start draining.
func _end() -> void:
	if _kind == Kind.PLANT and is_instance_valid(_target):
		_target.end_lance_pull()
	_state = State.IDLE
	_kind = Kind.NONE
	_target = null
	pulling = false
	pulling_player = false
	if _line and is_instance_valid(_line):
		_line.visible = false
	AlienTechManager.release_cooldown_hold(AlienTechRegistry.MULTI_LANCE, MISS_COOLDOWN if _whiffed else -1.0)
	_whiffed = false

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _draw_line(from: Vector2, to: Vector2) -> void:
	if not _line or not is_instance_valid(_line):
		return
	_line.points = PackedVector2Array([from, to])
	_line.visible = true

## Invincible enemies get shocked instead of damaged. Not while Time Freeze is
## running: the enemy is already frozen, and freezing it a second time would
## make Time Freeze's thaw restore the wrong `freeze` state.
func _can_shock(enemy) -> bool:
	return enemy.has_method("can_be_shocked") and enemy.can_be_shocked() and not AlienTechManager.time_freeze_active

func _is_trash(node) -> bool:
	for group in TRASH_GROUPS:
		if node.is_in_group(group):
			return true
	return false

## Triggers a trash target the way a bullet would.
func _hit_trash(node) -> void:
	if node.is_in_group("trash_items"):
		node.destroy_trash()
	elif node.is_in_group("trash_clusters"):
		node.take_lance_hit(CLUSTER_HITS)
	else:
		node.take_lance_hit()

## Still in the world and not already collected/despawning/destroyed.
func _is_live(node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if node.get("collected") == true or node.get("despawning") == true or node.get("is_destroyed") == true:
		return false
	if node is UFOPiece and (node as UFOPiece).is_carried:
		return false
	return true
