extends Node2D
class_name RainbowBonusLevel

## The bonus rainbow level: inside the rainbow, seven screens tall, red at the
## top to violet at the bottom. Reached by riding a rainbow current into the
## glowing apex after the Rainbow Fish minigame (RainbowBonusManager swaps it
## in and back out).
##
## The turtle starts at the bottom of the launch current running up the right
## edge (walled off from the play area) and is shot out into red at the top.
## Every lost "ball" drops it a colour; falling out the bottom of violet — or
## dying — ends the level, after a summary of the fruit collected.
##
## Fruit: every bounce off a CircularBumper spawns a Fruit somewhere in the
## upper half of that bumper's colour band, worth Fruit.BASE_POINTS × the
## band's level value (red 7 … violet 1). Points are tallied here and paid out
## on the summary screen.
##
## Sky physics everywhere: the scene's Ocean sits far below violet, so the
## turtle is always "in the air" (TurtlePlayer's normal sky gravity and drag).
##
## Coordinates: x = -320..320, y = 0 (top of red) .. 7 × 360 (bottom of violet).

const SCREEN_SIZE := Vector2(640, 360)
const SCREEN_COUNT := 7
const _FRUIT_SCENE = preload("res://entities/collectibles/fruit/fruit.tscn")

## How far below violet the turtle falls before the level ends
@export var fall_out_margin: float = 40.0

@export_group("Fruit")
## A new fruit never spawns closer to the turtle than this
@export var fruit_min_turtle_distance: float = 120.0
## Uncollected fruit allowed in one band at a time (0 = no limit)
@export var max_fruit_per_band: int = 0
## Spawn area inset from the side walls
@export var fruit_edge_margin: float = 20.0
## Spawn area starts this far below the top of the band — enough to clear the
## HUD bar, which covers the top of red when the camera is at the top
@export var fruit_top_margin: float = 56.0
## Keeps fruit out of the launch lane on the right (x beyond this)
@export var fruit_max_x: float = 270.0

@export_group("Current Shutdown")
## Every this many seconds one colour's currents (ladders and nets) switch
## off for good, so the level gets harder the longer the turtle lasts.
## 0 = never.
@export var current_shutdown_interval: float = 30.0
## The currents flicker for this long before they go
@export var current_shutdown_warning: float = 3.0
## Nodes whose OceanCurrent children are switched off, in order — one per
## interval. Orange first, working down to violet.
@export var current_shutdown_order: Array[String] = [
	"Orange Currents", "Yellow Currents", "Green Currents",
	"Blue Currents", "Indigo Currents", "Violet Currents",
]

## Default launch current path (level space): up the right-edge lane from
## below violet, curving left over the top of LaunchWall into red.
const DEFAULT_LAUNCH_PATH: Array[Vector2] = [
	Vector2(304, 2600), Vector2(304, 110), Vector2(294, 64), Vector2(262, 44), Vector2(210, 40),
]

var _ended: bool = false
## Per band (0 = red … 6 = violet): fruit collected and points earned
var _fruit_counts: Array[int] = []
var _fruit_points: Array[int] = []
## Uncollected fruit per band
var _live_fruit: Array[int] = []
## Seconds played, and how many entries of current_shutdown_order are gone
var _shutdown_clock: float = 0.0
var _shutdown_index: int = 0

## Runs before the children's _ready, so OceanCurrent builds its collision and
## bubbles from the curve. Fills in the launch path if the scene has none —
## an editor save can drop a curve override on an instanced Path2D, which left
## the turtle sitting at the bottom of an inert current.
func _enter_tree() -> void:
	var path := get_node_or_null("LaunchCurrent/Path2D") as Path2D
	if path and (path.curve == null or path.curve.point_count < 2):
		var curve := Curve2D.new()
		for p in DEFAULT_LAUNCH_PATH:
			curve.add_point(p)
		path.curve = curve

func _ready() -> void:
	add_to_group("level")
	get_tree().paused = false
	for i in SCREEN_COUNT:
		_fruit_counts.append(0)
		_fruit_points.append(0)
		_live_fruit.append(0)
	for bumper in get_tree().get_nodes_in_group("circular_bumpers"):
		if bumper.has_signal("player_bounced"):
			bumper.player_bounced.connect(_on_bumper_bounced)

## Colour band at `y` (0 = red at the top … 6 = violet).
func band_at(y: float) -> int:
	return clampi(int(floor(y / SCREEN_SIZE.y)), 0, SCREEN_COUNT - 1)

## Score multiplier for a band: red 7 … violet 1.
func level_value(band: int) -> int:
	return SCREEN_COUNT - band

# ---------------------------------------------------------------------------
# FRUIT
# ---------------------------------------------------------------------------

func _on_bumper_bounced(bumper: Node2D) -> void:
	if _ended:
		return
	var band := band_at(bumper.global_position.y)
	if max_fruit_per_band > 0 and _live_fruit[band] >= max_fruit_per_band:
		return
	var spot: Variant = _pick_fruit_spot(band)
	if spot == null:
		return
	var fruit := _FRUIT_SCENE.instantiate() as Fruit
	fruit.setup(band, level_value(band))
	fruit.position = to_local(spot)
	fruit.fruit_collected.connect(_on_fruit_collected)
	_live_fruit[band] += 1
	# Deferred: the bounce comes from the bumper's HitArea physics callback
	add_child.call_deferred(fruit)

## Random point in the upper half of `band`, at least
## fruit_min_turtle_distance from the turtle and not inside anything solid.
## null if no spot was found.
func _pick_fruit_spot(band: int) -> Variant:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var top := band * SCREEN_SIZE.y + fruit_top_margin
	var bottom := band * SCREEN_SIZE.y + SCREEN_SIZE.y * 0.5
	var left := -SCREEN_SIZE.x * 0.5 + fruit_edge_margin
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	query.shape = circle
	query.collision_mask = 1 | 16  # walls, bumpers, flippers
	for _i in 24:
		var p := Vector2(randf_range(left, fruit_max_x), randf_range(top, bottom))
		if player and p.distance_to(player.global_position) < fruit_min_turtle_distance:
			continue
		query.transform = Transform2D(0.0, p)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		return p
	return null

func _on_fruit_collected(fruit: Fruit) -> void:
	_live_fruit[fruit.band] = maxi(0, _live_fruit[fruit.band] - 1)
	_fruit_counts[fruit.band] += 1
	_fruit_points[fruit.band] += fruit.point_value

func fruit_total() -> int:
	var total := 0
	for pts in _fruit_points:
		total += pts
	return total

func level_height() -> float:
	return SCREEN_SIZE.y * SCREEN_COUNT

func _physics_process(delta: float) -> void:
	if _ended:
		return
	_update_current_shutdown(delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.y > level_height() + fall_out_margin:
		_end()

## Starts the next colour's currents flickering `current_shutdown_warning`
## seconds ahead of its turn, so they go dark right on the interval.
func _update_current_shutdown(delta: float) -> void:
	if current_shutdown_interval <= 0.0 or _shutdown_index >= current_shutdown_order.size():
		return
	_shutdown_clock += delta
	var warning: float = minf(current_shutdown_warning, current_shutdown_interval)
	if _shutdown_clock < current_shutdown_interval * (_shutdown_index + 1) - warning:
		return
	var group := get_node_or_null(current_shutdown_order[_shutdown_index])
	_shutdown_index += 1
	if group == null:
		return
	for child in group.get_children():
		if child is OceanCurrent:
			child.shut_down(warning)

## TurtlePlayer calls this when it dies — the bonus level just ends.
func on_player_died(_final_score: int, _death_cause: String = "") -> void:
	_end()

func _end() -> void:
	if _ended:
		return
	_ended = true
	# Completing the level earns a rainbow heart (worth 2 HP) for the rest of
	# the run; RainbowBonusManager restores full health on the way back
	var heart_gained := GameManager.grant_rainbow_heart()
	# Deferred: can be reached from a physics callback (the turtle dying)
	_show_summary.call_deferred(heart_gained)

func _show_summary(heart_gained: bool) -> void:
	RainbowBonusSummary.show_summary(get_tree(), _fruit_counts, _fruit_points, heart_gained, _on_summary_done)

## Summary dismissed: pay out the fruit (the bonus HUD's score is what
## RainbowBonusManager carries back) and leave.
func _on_summary_done() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_score(fruit_total())
	if RainbowBonusManager.active:
		RainbowBonusManager.finish()
	else:
		# Run on its own from the editor (F6) — just go again
		print("🌈 Bonus rainbow level over (run standalone — restarting)")
		get_tree().paused = false
		get_tree().reload_current_scene.call_deferred()
