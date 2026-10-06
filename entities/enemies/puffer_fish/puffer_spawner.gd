extends Node2D
class_name PufferSpawner

## Spawns puffer fish in batches, spread across the spawn area, so there are
## usually several around to chain super-speed ejects through. Batches are
## slow (≈ every spawn_interval ± spawn_interval_jitter seconds), and each is
## trimmed so the level never has more than max_alive puffers at once.

@export var puffer_scene: PackedScene

@export_group("Batches")
## Puffers per batch (fewer if the batch would go over max_alive)
@export var batch_size: int = 5
## Most puffers alive in the level at once, counting ones still spawning in
@export var max_alive: int = 10
@export var spawn_interval: float = 40.0
## Each wait is spawn_interval ± this, so batches don't land on a fixed beat
@export var spawn_interval_jitter: float = 6.0
## Spawn a batch as soon as the level starts instead of after the first wait
@export var spawn_on_start: bool = true
## Delay between each puffer of a batch appearing
@export var stagger: float = 0.15

@export_group("Placement")
## World-space rectangle puffers spawn in. The default y band matches
## PufferFish's preferred depth (40–160px below a surface at y = -126).
@export var spawn_area_min: Vector2 = Vector2(-280, -80)
@export var spawn_area_max: Vector2 = Vector2(280, 30)
## Minimum distance from other puffers (alive or in this batch)
@export var min_spacing: float = 50.0
## Minimum distance from the turtle, so nothing pops in on top of it
@export var min_player_distance: float = 80.0
## Clearance from walls/bumpers/flippers around a spawn point
@export var wall_clearance: float = 14.0

const _PLACEMENT_ATTEMPTS: int = 25
const _WARNING_COLOR: Color = Color(1.0, 0.85, 0.2, 0.7)

var _spawn_timer: Timer
## Puffers mid-spawn-animation — counted against max_alive so two batches
## can't both fill the same free slots.
var _pending: int = 0

func _ready() -> void:
	add_to_group("spawners")
	if not puffer_scene:
		push_error("PufferSpawner: puffer_scene not assigned!")
		return

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	if spawn_on_start:
		spawn_batch.call_deferred()
	_restart_timer()

func _restart_timer() -> void:
	var wait := spawn_interval + randf_range(-spawn_interval_jitter, spawn_interval_jitter)
	_spawn_timer.start(maxf(1.0, wait))

func _on_spawn_timer_timeout() -> void:
	spawn_batch()
	_restart_timer()

func _alive_count() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("puffers"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.get("state") != PufferFish.State.DYING:
			count += 1
	return count

func spawn_batch() -> void:
	if not puffer_scene:
		return
	var count := mini(batch_size, max_alive - _alive_count() - _pending)
	if count <= 0:
		return

	var taken: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("puffers"):
		taken.append((node as Node2D).global_position)
	var player := get_tree().get_first_node_in_group("player") as Node2D

	var positions: Array[Vector2] = []
	for i in count:
		var pos: Variant = _find_spawn_position(taken, player)
		if pos == null:
			continue  # area too crowded — skip rather than spawn inside something
		positions.append(pos)
		taken.append(pos)

	_pending += positions.size()
	for i in positions.size():
		_spawn_one(positions[i], i * stagger)

func _find_spawn_position(taken: Array[Vector2], player: Node2D) -> Variant:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = wall_clearance
	query.shape = circle
	query.collision_mask = 1  # walls, bumpers, flippers

	for attempt in _PLACEMENT_ATTEMPTS:
		var pos := Vector2(
			randf_range(spawn_area_min.x, spawn_area_max.x),
			randf_range(spawn_area_min.y, spawn_area_max.y))
		if player and pos.distance_to(player.global_position) < min_player_distance:
			continue
		var crowded := false
		for other in taken:
			if pos.distance_to(other) < min_spacing:
				crowded = true
				break
		if crowded:
			continue
		query.transform = Transform2D(0.0, pos)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		return pos
	return null

func _spawn_one(pos: Vector2, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	for i in 2:
		_create_warning_ripple(pos)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(0.3).timeout

	_pending -= 1
	# The coroutine outlived a Time Freeze starting, or the level is going away
	if AlienTechManager.time_freeze_active or not is_inside_tree():
		return

	# The turtle may have swum onto the spot during the warning — pick again
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and pos.distance_to(player.global_position) < min_player_distance:
		var taken: Array[Vector2] = []
		for node in get_tree().get_nodes_in_group("puffers"):
			taken.append((node as Node2D).global_position)
		var new_pos: Variant = _find_spawn_position(taken, player)
		if new_pos == null:
			return
		pos = new_pos

	# Position before add_child — PufferFish takes its patrol center from
	# global_position in _ready()
	var puffer := puffer_scene.instantiate() as Node2D
	var parent := get_parent() as Node2D
	puffer.position = parent.to_local(pos) if parent else pos
	get_parent().add_child(puffer)

	# Fade/grow in
	puffer.modulate.a = 0.0
	var sprite := puffer.get_node_or_null("AnimatedSprite2D") as Node2D
	# Fades in even while the level is held by the start prompt
	var tween := puffer.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(puffer, "modulate:a", 1.0, 0.3)
	if sprite:
		sprite.scale = Vector2.ONE * 0.2
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.35)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _create_warning_ripple(pos: Vector2) -> void:
	var ripple := Node2D.new()
	get_parent().add_child(ripple)
	ripple.global_position = pos

	var circle := ColorRect.new()
	circle.color = _WARNING_COLOR
	circle.size = Vector2(10, 10)
	circle.position = Vector2(-5, -5)
	ripple.add_child(circle)

	var tween := ripple.create_tween().set_parallel(true)
	tween.tween_property(circle, "size", Vector2(50, 50), 0.8)
	tween.tween_property(circle, "position", Vector2(-25, -25), 0.8)
	tween.tween_property(circle, "color:a", 0.0, 0.8)
	tween.finished.connect(ripple.queue_free)
