extends Node
class_name RainbowFishSpawner

## The Rainbow Fish minigame. Opt-in per level: drop rainbow_fish_spawner.tscn
## into the level and tune it in the Inspector.
##
## Killing kill_triggers[n] (± kill_trigger_jitter, rolled each time) enemies
## starts round n. Red spawns first; freeing colour c (in ROYGBIV order)
## spawns colours 2c+1 and 2c+2, so with one fish per colour the live count
## runs 1 → 2 → 3 → 4 → 3 → 2 → 1, and the seventh correct free finishes the
## rainbow. With several fish per colour, all of
## them have to be freed before the colour counts: the earlier ones swim off,
## the last one paints the stripe and brings on the next colours.
##
## A fish is freed by spit or by the turtle hitting it at super speed (a
## plain bump does nothing). Hitting one out of order ends the round, and so
## does the round timer (round_seconds_per_fish × fish_per_color) running out:
## the rainbow dissolves and every trapped fish — the wrong one included —
## dies in place. The next round
## needs the next kill_triggers entry, counted from the failure — after the
## last entry, the minigame is over for this level.

signal round_started
signal round_failed
signal rainbow_completed
## The turtle rode a rainbow current up into the glowing apex — the way into
## the secret level.
signal secret_entrance_reached

const _FISH_SCENE = preload("res://entities/npcs/rainbow_fish/rainbow_fish.tscn")
const _CURRENT_SCENE = preload("res://entities/environment/current/current.tscn")

## Kills needed to start each round, counted from level start for the first
## and from the previous failure after that. Its length caps how many rounds
## the level allows.
@export var kill_triggers: Array[int] = [15, 15, 15]
## Each trigger is rolled at random within ± this many kills (never below 1),
## so the player can't just count kills
@export_range(0, 10) var kill_trigger_jitter: int = 3
## Fish spawned for each colour (bigger levels may want 2)
@export_range(1, 4) var fish_per_color: int = 1
## Points for each fish the turtle shoots free — it's trash cleanup too
@export var free_points: int = 50
## Height of the outer (red) stripe above the surface. The width always spans
## the ocean wall to wall.
@export var arc_height: float = 150.0
## Round time limit per fish_per_color — 1 fish per colour gets this long,
## 2 per colour twice as long. Shown centred on the HUD.
@export var round_seconds_per_fish: float = 30.0
## Seconds added to the round timer for every fish freed in order
@export var seconds_per_free: float = 1.0
## Fish never spawn closer to the turtle than this
@export var spawn_min_player_distance: float = 120.0
## Fish spawn at least this far from the ocean's edges
@export var spawn_edge_margin: float = 24.0

@export_group("Secret Entrance")
## How far below the surface the two rainbow currents start, so the turtle can
## swim into them from the water
@export var entrance_current_depth: float = 32.0
## Current strength — same tuning as the levels' Hydro Funnel currents
@export var entrance_propulsion_force: float = 1600.0
@export var entrance_centering_force: float = 800.0
## Turtle within this distance of the apex glow enters the secret level
@export var entrance_radius: float = 20.0

enum Phase { WAITING, ACTIVE, COMPLETE, OUT_OF_ROUNDS }
var phase: Phase = Phase.WAITING

var kills: int = 0
## This wait's kill target: kill_triggers[rounds_played] ± kill_trigger_jitter,
## rolled when the wait begins (level start or a failure)
var _kills_target: int = -1
## Rounds started so far — indexes kill_triggers
var rounds_played: int = 0
## Next colour that has to be freed
var next_color: int = 0
## Round countdown; only runs while colours are left to free
var time_left: float = 0.0

var _fish: Array[RainbowFish] = []
var _arc: RainbowArc = null
var _entrance_open: bool = false
var _entrance_reached: bool = false

## Ocean interior for spawning and the rainbow's span: x = wall to wall,
## y = surface to floor
var _ocean_rect: Rect2 = Rect2()

func _ready() -> void:
	if kill_triggers.is_empty():
		phase = Phase.OUT_OF_ROUNDS
	_roll_kills_target()
	GameManager.enemy_killed.connect(_on_enemy_killed)

func kills_needed() -> int:
	return _kills_target

func _roll_kills_target() -> void:
	if rounds_played >= kill_triggers.size():
		_kills_target = -1
		return
	var base := kill_triggers[rounds_played]
	_kills_target = maxi(1, base + randi_range(-kill_trigger_jitter, kill_trigger_jitter))

func _on_enemy_killed(_enemy: Node) -> void:
	if phase != Phase.WAITING:
		return
	kills += 1
	if kills >= kills_needed():
		# Deferred: kills land inside physics callbacks (bullet contact, etc.),
		# where bodies and areas can't be added.
		_start_round.call_deferred()

func _start_round() -> void:
	if phase != Phase.WAITING:
		return
	_ocean_rect = _measure_ocean()
	if _ocean_rect.size == Vector2.ZERO:
		return  # no ocean / no turtle — try again on the next kill
	phase = Phase.ACTIVE
	rounds_played += 1
	next_color = 0
	_arc = RainbowArc.new()
	_arc.name = "Rainbow"
	_arc.colors = RainbowFish.COLORS
	_arc.center = Vector2(_ocean_rect.get_center().x, _ocean_rect.position.y)
	_arc.radius = Vector2(_ocean_rect.size.x * 0.5 - 4.0, arc_height)
	_level().add_child(_arc)
	time_left = round_seconds_per_fish * fish_per_color
	_spawn_color(0)
	# Pauses the game until dismissed, so the timer starts once it's read
	RainbowFishPopup.show_round(get_tree())
	round_started.emit()
	print("🌈 Rainbow fish round %d/%d started" % [rounds_played, kill_triggers.size()])

func _spawn_color(index: int) -> void:
	if index >= RainbowFish.COLORS.size():
		return
	for _i in fish_per_color:
		var fish := _FISH_SCENE.instantiate() as RainbowFish
		fish.setup(index, _random_heading())
		fish.is_target = index == next_color
		var level := _level() as Node2D
		var spawn_point := _pick_spawn_point()
		fish.position = level.to_local(spawn_point) if level else spawn_point
		fish.shot.connect(_on_fish_shot)
		fish.tree_exited.connect(func(): _fish.erase(fish))
		_fish.append(fish)
		_level().add_child.call_deferred(fish)

func _process(delta: float) -> void:
	if phase != Phase.ACTIVE or next_color >= RainbowFish.COLORS.size():
		return
	time_left = maxf(0.0, time_left - delta)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_rainbow_timer(time_left, RainbowFish.COLORS[next_color])
	if time_left <= 0.0:
		print("🌈 Rainbow fish round timed out")
		_fail()

func _on_fish_shot(fish: RainbowFish) -> void:
	if phase != Phase.ACTIVE:
		return
	if fish.color_index != next_color:
		print("🌈 Wrong colour: %s hit, needed %s" % [RainbowFish.COLOR_NAMES[fish.color_index], RainbowFish.COLOR_NAMES[next_color]])
		_fail()  # still trapped, so it dies in place with the rest
		return
	_award_points(fish)
	time_left += seconds_per_free
	if seconds_per_free > 0.0:
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.flash_rainbow_timer()
	var color := fish.color_index
	# Every fish of the colour has to be freed — all but the last swim off,
	# and the last one paints the stripe
	for other in _fish:
		if other != fish and is_instance_valid(other) and other.is_trapped() and other.color_index == color:
			fish.swim_away()
			return
	next_color += 1
	fish.release(_arc)
	if next_color >= RainbowFish.COLORS.size():
		_win()
	_refresh_targets()
	# Deferred: we're inside the bullet's contact callback
	_spawn_color.call_deferred(color * 2 + 1)
	_spawn_color.call_deferred(color * 2 + 2)

## The last colour is freed — won. Its stripe is still being painted, but the
## entrance opens right away: making the player wait out the painting could
## cost them their life.
func _win() -> void:
	phase = Phase.COMPLETE
	_hide_timer()
	print("🌈 Rainbow complete!")
	rainbow_completed.emit()
	_open_secret_entrance()

# ---------------------------------------------------------------------------
# SECRET ENTRANCE
# ---------------------------------------------------------------------------

## Two OceanCurrents, one per end of the rainbow: each starts under the water
## below its end, climbs to the surface and rides the middle of the rainbow
## band up to the apex, where the entrance glows.
func _open_secret_entrance() -> void:
	if not is_instance_valid(_arc):
		return
	_arc.open_portal()
	for from_left in [true, false]:
		var current := _CURRENT_SCENE.instantiate() as OceanCurrent
		current.name = "RainbowCurrentLeft" if from_left else "RainbowCurrentRight"
		current.propulsion_force = entrance_propulsion_force
		current.centering_force = entrance_centering_force
		current.lateral_damping = 1.0
		current.current_width = _arc.band_width()
		# The apex trigger catches the turtle — no fling at the end
		current.exit_impulse = 0.0
		current.exit_zone_length = 8.0
		current.show_debug_arrows = false
		# Denser, brighter bubbles than a normal current — they have to read
		# over the rainbow's colours
		current.current_color = Color(1.0, 1.0, 1.0, 0.95)
		current.particles_per_emitter = 16
		current.particle_spread = current.current_width * 0.35
		current.get_node("Path2D").curve = _entrance_curve(from_left)
		current.modulate.a = 0.0
		_level().add_child(current)
		current.position = Vector2.ZERO
		current.create_tween().tween_property(current, "modulate:a", 1.0, 0.8)
	_entrance_open = true

## Path for one entrance current, in level space.
func _entrance_curve(from_left: bool) -> Curve2D:
	var level := _level() as Node2D
	var curve := Curve2D.new()
	var start: Vector2 = _arc.band_point(0.0 if from_left else 1.0)
	var points: Array[Vector2] = [start + Vector2(0.0, entrance_current_depth)]
	const STEPS := 24
	for i in STEPS + 1:
		var t := 0.5 * i / STEPS
		points.append(_arc.band_point(t if from_left else 1.0 - t))
	for p in points:
		curve.add_point(level.to_local(p) if level else p)
	return curve

func _physics_process(_delta: float) -> void:
	if not _entrance_open or not is_instance_valid(_arc):
		return
	var player := get_tree().get_first_node_in_group("player") as RigidBody2D
	if not player:
		return
	if _entrance_reached:
		# Holds the turtle in the entrance until the secret level takes over
		player.global_position = _arc.apex()
		player.linear_velocity = Vector2.ZERO
		return
	if player.global_position.distance_to(_arc.apex()) < entrance_radius:
		_entrance_reached = true
		print("🌈 Secret entrance reached!")
		secret_entrance_reached.emit()

## Pulses the fish of the colour that has to be freed next.
func _refresh_targets() -> void:
	for fish in _fish:
		if is_instance_valid(fish):
			fish.is_target = fish.color_index == next_color

func _hide_timer() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.hide_rainbow_timer()

func _award_points(fish: RainbowFish) -> void:
	if free_points <= 0:
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_score(free_points)
	GameManager.spawn_floating_score(fish.global_position, free_points)

func _fail() -> void:
	phase = Phase.OUT_OF_ROUNDS if rounds_played >= kill_triggers.size() else Phase.WAITING
	kills = 0
	_roll_kills_target()
	# Copy first: the fish leave _fish as they're freed
	var doomed := _fish.duplicate()
	for fish in doomed:
		if not is_instance_valid(fish):
			continue
		if fish.is_trapped():
			fish.die_in_place()
		elif fish.is_painting():
			fish.vanish()  # freed and on its way — its stripe is gone
	if is_instance_valid(_arc):
		_arc.dissolve()
	_arc = null
	_hide_timer()
	round_failed.emit()
	if phase == Phase.OUT_OF_ROUNDS:
		print("🌈 No rainbow fish rounds left this level")

# ---------------------------------------------------------------------------
# PLACEMENT
# ---------------------------------------------------------------------------

func _level() -> Node:
	return get_tree().get_first_node_in_group("level")

## Wall-to-wall, surface-to-floor rectangle around the turtle's part of the
## ocean, found by casting for ocean walls (RainbowFish.is_ocean_wall).
func _measure_ocean() -> Rect2:
	var ocean: Ocean = get_tree().get_first_node_in_group("ocean")
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not ocean or not player or not _level():
		return Rect2()
	var world := player.get_world_2d()
	const REACH := 2000.0
	# Walls measured just under the surface, where interior wall tiles are
	# least likely to cut the span short
	var across := Vector2(player.global_position.x, ocean.surface_y + 12.0)
	var left := _wall_distance(world, across, Vector2.LEFT, REACH, 320.0)
	var right := _wall_distance(world, across, Vector2.RIGHT, REACH, 320.0)
	var down := _wall_distance(world, across, Vector2.DOWN, REACH, ocean.floor_y - across.y)
	var floor_y := minf(across.y + down, ocean.floor_y)
	return Rect2(across.x - left, ocean.surface_y, left + right, floor_y - ocean.surface_y)

func _wall_distance(world: World2D, from: Vector2, dir: Vector2, reach: float, fallback: float) -> float:
	var hit := RainbowFish.find_ocean_wall_hit(world, from, dir * reach)
	if hit.is_empty():
		return fallback
	return from.distance_to(hit.position)

func _pick_spawn_point() -> Vector2:
	var area := _ocean_rect.grow(-spawn_edge_margin)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var space := get_viewport().world_2d.direct_space_state
	var point_query := PhysicsPointQueryParameters2D.new()
	point_query.collision_mask = 1
	var best := area.get_center()
	var best_dist := -1.0
	for _i in 24:
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		point_query.position = p
		var in_wall := false
		for hit in space.intersect_point(point_query, 8):
			if RainbowFish.is_ocean_wall(hit.collider):
				in_wall = true
				break
		if in_wall:
			continue
		var dist := INF
		if is_instance_valid(player):
			dist = p.distance_to(player.global_position)
		if dist >= spawn_min_player_distance:
			return p
		if dist > best_dist:  # nothing far enough yet — remember the furthest
			best_dist = dist
			best = p
	return best

## A diagonal-ish heading — never within 20° of straight across or straight
## up/down, so it doesn't bounce back and forth along one axis forever.
func _random_heading() -> Vector2:
	var quadrant := randi() % 4
	var ang := deg_to_rad(randf_range(20.0, 70.0)) + quadrant * PI * 0.5
	return Vector2.RIGHT.rotated(ang)
