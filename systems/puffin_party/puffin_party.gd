extends Node2D
class_name PuffinParty

## PUFFIN PARTY — the bonus earned with GameManager.PUFFIN_PARTY_SKILL_SHOTS
## puffin skill shots. It is not a level of its own: LevelBase adds this scene
## to the level that is about to start, and it plays out one screen above that
## level's sky. The turtle hops from puffin to puffin (PartyPuffin) shooting
## plastic bags (SpaceDebrisGroup pairs); every pair cleared drops a powerup
## that sinks into the level waiting below, to be picked up in normal play.
##
## While the party runs:
##   - the level below is frozen (everything in it but walls, floor, camera,
##     HUD and the turtle is PROCESS_MODE_DISABLED) and its timer is stopped;
##   - the camera is held on the party screen (camera_2d.gd focus_on());
##   - powerups can't be picked up, and never time out on the floor.
##
## It ends when the turtle drops out of the bottom of the party screen (no
## puffin caught it — and once every bag is gone the puffins all leave, so
## that is how it always ends). The level thaws on the spot, `finished` fires
## and the turtle keeps falling, through the sky and into a level that is
## already running: the party replaces the level's usual start (puffin plunge
## or countdown). The camera follows it down.
signal finished

@export_group("Puffins")
@export var puffin_count: int = 10
## Seconds a puffin carries the turtle before launching it on its own
@export var hold_seconds: float = 4.0
## Speed the turtle leaves a puffin at
@export var launch_speed: float = 800.0
@export var launch_action: String = "ufo_windup"
## How fast the aim arrow swings toward where the stick points, in degrees
## per second
@export var aim_turn_degrees: float = 150.0
## Blinking no-damage window for the turtle as it drops into the level
@export var landing_grace_seconds: float = 2.0

## How fast the puffins fly (each picks a speed in this range), bouncing off
## the edges of the party
@export var bounce_speed_min: float = 55.0
@export var bounce_speed_max: float = 95.0

@export_group("Bags")
## Pairs of bags per powerup type (5 types: 5 → 25 pairs, 50 bags)
@export var pairs_per_powerup: int = 5
## How far apart the two bags of a pair start
@export var pair_spread: float = 20.0

@export_group("Stage")
## The party stays this far inside the edges of its screen
@export var edge_margin: float = 26.0
@export var sky_top_color: Color = Color(0.25, 0.55, 0.95, 1.0)
@export var sky_bottom_color: Color = Color(0.62, 0.88, 1.0, 1.0)

const _PUFFIN_SCRIPT = preload("res://systems/puffin_party/party_puffin.gd")
const _GROUP_SCENE = preload("res://systems/space_debris/space_debris_group.tscn")
const _DEBRIS_SCENE = preload("res://systems/space_debris/space_debris.tscn")
const _POWERUP_SCENE = preload("res://entities/collectibles/powerup/powerup.tscn")
## Each powerup type and the bag animation that stands for it
const _BAG_TYPES: Array = [
	[Powerup.PowerupType.SHIELD, &"shield"],
	[Powerup.PowerupType.AIR_RESERVE, &"air"],
	[Powerup.PowerupType.ENERGY_ENDLESS, &"energy"],
	[Powerup.PowerupType.RAPID_FIRE, &"bullet"],
	[Powerup.PowerupType.RANDOM, &"random"],
]
const _SCREEN := Vector2(640.0, 360.0)
## Sky camera height used if the level's camera doesn't say (camera_2d.gd)
const _DEFAULT_SKY_Y: float = -300.0
## The turtle bounces off the sides of the party screen, keeping this
## much of its speed
const _WALL_BOUNCE: float = 0.6
## Past the bottom edge by this much, the turtle has fallen out
const _FALL_OUT_MARGIN: float = 14.0
## After the last bag, before the party ends (lets the last powerup appear)
const _CLEARED_DELAY: float = 1.2
## How long the camera is steered down to the level's sky view before its
## own following takes over again
const _CAMERA_HANDOVER_SECONDS: float = 0.45
const _BACKDROP_LINGER_SECONDS: float = 1.5
const _HINT_SECONDS: float = 5.0

## The TurtlePlayer (no class_name; see PuffinLauncher)
var turtle: RigidBody2D = null

var _level: Node = null
var _camera: Camera2D = null
var _rect: Rect2 = Rect2()
var _holder: PartyPuffin = null
var _puffins: Array[PartyPuffin] = []
var _bag_groups: Array[SpaceDebrisGroup] = []
var _bags: Node2D = null
var _groups_left: int = 0
var _running: bool = false
var _cleared_timer: float = -1.0
## [node, process_mode it had] for everything frozen in the level
var _frozen: Array = []
var _party_powerups: Array[Powerup] = []
var _hud_state: Dictionary = {}
var _hint: CanvasLayer = null

# ---------------------------------------------------------------------------
# START
# ---------------------------------------------------------------------------

## Sets the party up over `level` and starts it. Call right after adding this
## node to the level, before the level has run a frame.
func start(level: Node) -> void:
	_level = level
	turtle = get_tree().get_first_node_in_group("player") as RigidBody2D
	if turtle == null:
		push_warning("PuffinParty: no turtle — skipping the party")
		finished.emit()
		queue_free()
		return
	global_position = Vector2.ZERO
	z_index = -1  # the backdrop sits behind everything it holds
	get_tree().paused = false

	# One screen above the top of the level's sky
	_camera = get_viewport().get_camera_2d()
	var sky_y: float = _DEFAULT_SKY_Y
	var center_x: float = 0.0
	if _camera:
		center_x = _camera.global_position.x
		var camera_sky = _camera.get("sky_locked_y")
		if camera_sky != null:
			sky_y = camera_sky
	var center := Vector2(center_x, sky_y - _SCREEN.y)
	_rect = Rect2(center - _SCREEN * 0.5, _SCREEN)
	queue_redraw()

	_freeze_level()
	_level.child_entered_tree.connect(_on_level_child_entered)
	if _camera:
		_camera.global_position = center
		if _camera.has_method("focus_on"):
			_camera.focus_on(center)
		_camera.force_update_scroll()

	_spawn_bags()
	_spawn_puffins()
	_show_hint()
	_running = true

## Everything in the level that isn't needed up here stops dead: enemies,
## spawners, flippers, the works. Floor and walls stay (falling powerups land
## on them), as do the camera, the HUD and menus, the music and the turtle.
func _freeze_level() -> void:
	for child in _level.get_children():
		if child == self or child == turtle:
			continue
		if child is CanvasLayer or child is Camera2D or child is AudioStreamPlayer or child is TileMapLayer or child is Ocean:
			continue
		if child.name == &"WorldSafetyBoundaries":
			continue
		_frozen.append([child, child.process_mode])
		child.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		# No level clock, and no trash bags drifting into the frozen ocean
		_hud_state = {
			"timer": hud.timer_system.active,
			"score_clusters": hud.score_clusters_enabled,
			"freebie_clusters": hud.freebie_clusters_enabled,
		}
		hud.timer_system.active = false
		hud.score_clusters_enabled = false
		hud.freebie_clusters_enabled = false

## Pairs of bags, `pairs_per_powerup` of each type, on a jittered grid.
func _spawn_bags() -> void:
	_bags = Node2D.new()
	_bags.z_index = 1
	add_child(_bags)
	var types: Array = []
	for entry in _BAG_TYPES:
		for i in pairs_per_powerup:
			types.append(entry)
	types.shuffle()
	var area: Rect2 = flight_bounds()
	var columns: int = ceili(sqrt(float(types.size()) * area.size.x / area.size.y))
	var rows: int = ceili(float(types.size()) / float(columns))
	var cell := Vector2(area.size.x / columns, area.size.y / rows)
	for i in types.size():
		var column: int = i % columns
		@warning_ignore("integer_division")
		var row: int = i / columns
		var spot: Vector2 = area.position + Vector2((column + 0.5) * cell.x, (row + 0.5) * cell.y)
		spot += Vector2(randf_range(-0.25, 0.25) * cell.x, randf_range(-0.25, 0.25) * cell.y)
		var group: SpaceDebrisGroup = _GROUP_SCENE.instantiate()
		group.group_label = "Party %d" % (i + 1)
		group.powerup_type = types[i][0]
		group.powerup_scene = _POWERUP_SCENE
		# The two bags go in before the group enters the tree: it counts its
		# children in _ready()
		for side in [-0.5, 0.5]:
			var bag: SpaceDebris = _DEBRIS_SCENE.instantiate()
			bag.position = spot + Vector2(side * pair_spread, randf_range(-4.0, 4.0))
			bag.debris_animation = types[i][1]
			group.add_child(bag)
		group.group_cleared.connect(_on_group_cleared)
		_bags.add_child(group)
		_bag_groups.append(group)
	_groups_left = _bag_groups.size()

func _spawn_puffins() -> void:
	var area: Rect2 = flight_bounds()
	var center: Vector2 = area.get_center()
	for i in puffin_count:
		var puffin: PartyPuffin = _PUFFIN_SCRIPT.new()
		puffin.party = self
		puffin.velocity = Vector2.from_angle(randf() * TAU) * randf_range(bounce_speed_min, bounce_speed_max)
		puffin.position = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		# The one that starts with the turtle: top middle
		if i == 0:
			puffin.position = Vector2(center.x, area.position.y + 30.0)
		add_child(puffin)
		_puffins.append(puffin)
	# The first puffin starts with the turtle in its feet
	turtle.global_position = _puffins[0].global_position + PartyPuffin.TURTLE_OFFSET
	turtle.linear_velocity = Vector2.ZERO
	_puffins[0].hold()

func _show_hint() -> void:
	_hint = CanvasLayer.new()
	_hint.layer = 5
	add_child(_hint)
	var label := Label.new()
	label.text = "Puffin Party!  Aim, then %s to hop  -  shoot the bags!" % ("A" if GameSettings.using_gamepad else "Z")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(_SCREEN.x, 16.0)
	label.position = Vector2(0.0, _SCREEN.y - 26.0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	_hint.add_child(label)
	var tween := create_tween()
	tween.tween_interval(_HINT_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_hint.queue_free)

# ---------------------------------------------------------------------------
# PUFFIN CALLBACKS / QUERIES
# ---------------------------------------------------------------------------

## Where puffins and bags may be: the party screen, less a margin.
func flight_bounds() -> Rect2:
	return _rect.grow(-edge_margin)

## True while no puffin has the turtle.
func turtle_is_loose() -> bool:
	return _running and _holder == null

func on_puffin_caught(puffin: PartyPuffin) -> void:
	_holder = puffin
	# The move stick aims while held; it mustn't swim
	turtle.set("swim_locked", true)

func on_puffin_launched(puffin: PartyPuffin, direction: Vector2) -> void:
	if _holder == puffin:
		_holder = null
	_puffins.erase(puffin)
	turtle.set("swim_locked", false)
	turtle.linear_velocity = direction * launch_speed

# ---------------------------------------------------------------------------
# RUNNING
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _running or not is_instance_valid(turtle):
		return
	if _holder == null:
		# Loose: the sides are walls and the bottom is the way out. The top
		# is open sky — a launch that goes over it just arcs back down.
		var position_now: Vector2 = turtle.global_position
		var velocity: Vector2 = turtle.linear_velocity
		if (position_now.x < _rect.position.x + 8.0 and velocity.x < 0.0) or (position_now.x > _rect.end.x - 8.0 and velocity.x > 0.0):
			velocity.x = -velocity.x * _WALL_BOUNCE
		turtle.linear_velocity = velocity
		if position_now.y > _rect.end.y + _FALL_OUT_MARGIN:
			_end()
			return
	_herd_bags()
	if _cleared_timer >= 0.0:
		_cleared_timer -= delta
		if _cleared_timer < 0.0 and not _puffins.is_empty():
			_send_puffins_home()

## Bags wander on their own; one that strays to the edge is turned back in.
func _herd_bags() -> void:
	var area: Rect2 = flight_bounds()
	for group in _bag_groups:
		if not is_instance_valid(group):
			continue
		for bag in group.debris_pieces:
			if is_instance_valid(bag) and not bag.is_destroyed and not area.has_point(bag.global_position):
				bag.current_wander = (area.get_center() - bag.global_position).normalized() * bag.drift_speed

func _on_group_cleared(_group: SpaceDebrisGroup) -> void:
	_groups_left -= 1
	if _groups_left <= 0 and _cleared_timer < 0.0:
		_cleared_timer = _CLEARED_DELAY

## A powerup dropped by a cleared pair (SpaceDebrisGroup adds it to the level).
## It is for the level, not for now: can't be picked up until the party is
## over, and waits on the floor as long as it takes.
func _on_level_child_entered(child: Node) -> void:
	var powerup := child as Powerup
	if powerup == null:
		return
	powerup.disable_floor_despawn = true
	_party_powerups.append(powerup)
	_set_powerup_collectable.call_deferred(powerup, false)

func _set_powerup_collectable(powerup: Powerup, collectable: bool) -> void:
	if not is_instance_valid(powerup):
		return
	var area := powerup.get_node_or_null("Area2D") as Area2D
	if area:
		area.set_deferred("monitoring", collectable)

# ---------------------------------------------------------------------------
# END
# ---------------------------------------------------------------------------

## Every bag is gone: nothing left to do up here. The puffins fly off —
## dropping the turtle if one has it — and the fall ends the party as usual.
func _send_puffins_home() -> void:
	_holder = null
	turtle.set("swim_locked", false)
	for puffin in _puffins:
		if is_instance_valid(puffin):
			puffin.leave()
	_puffins.clear()

## The turtle has dropped out of the bottom of the party: the level below
## comes alive at once and the turtle simply keeps falling into it — no
## plunge, no countdown. The camera follows it down.
func _end() -> void:
	if not _running:
		return
	_running = false
	if _level.child_entered_tree.is_connected(_on_level_child_entered):
		_level.child_entered_tree.disconnect(_on_level_child_entered)

	_send_puffins_home()
	if is_instance_valid(_hint):
		_hint.queue_free()
	if is_instance_valid(_bags):
		create_tween().tween_property(_bags, "modulate:a", 0.0, 0.4)

	_thaw_level()
	for powerup in _party_powerups:
		_set_powerup_collectable(powerup, true)
	# Dropping in from above everything: a moment's grace for the landing
	turtle.call("grant_grace_iframes", landing_grace_seconds)
	finished.emit()

	# Down to the level's own sky view, then back to the camera's usual
	# following (sky while the turtle is up there, ocean once it's in)
	if _camera and _camera.has_method("focus_on"):
		var sky_view := Vector2(_rect.get_center().x, _rect.get_center().y + _SCREEN.y)
		_camera.focus_on(sky_view)
		await get_tree().create_timer(_CAMERA_HANDOVER_SECONDS, false).timeout
		if is_instance_valid(_camera):
			_camera.release_focus()
	# The backdrop stays until the camera has left it behind
	await get_tree().create_timer(_BACKDROP_LINGER_SECONDS, false).timeout
	queue_free()

func _thaw_level() -> void:
	for entry in _frozen:
		if is_instance_valid(entry[0]):
			entry[0].process_mode = entry[1]
	_frozen.clear()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and not _hud_state.is_empty():
		hud.timer_system.active = _hud_state.timer
		hud.score_clusters_enabled = _hud_state.score_clusters
		hud.freebie_clusters_enabled = _hud_state.freebie_clusters
	_hud_state.clear()

## Never leave the level frozen if the party is torn down some other way.
func _exit_tree() -> void:
	if not _frozen.is_empty() and is_instance_valid(_level) and not _level.is_queued_for_deletion():
		_thaw_level()

# ---------------------------------------------------------------------------
# BACKDROP
# ---------------------------------------------------------------------------

## The level's own sky art stops at the top of its sky; this is the sky above
## that: plain bands, darker toward the top.
func _draw() -> void:
	if not _rect.has_area():
		return
	var bands: int = 12
	var band_height: float = _rect.size.y / bands
	for i in bands:
		var color: Color = sky_top_color.lerp(sky_bottom_color, float(i) / float(bands - 1))
		draw_rect(Rect2(_rect.position.x, _rect.position.y + i * band_height, _rect.size.x, band_height + 1.0), color)
