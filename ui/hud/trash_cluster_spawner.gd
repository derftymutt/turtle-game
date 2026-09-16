extends RefCounted
class_name TrashClusterSpawner

## Trash cluster spawning — driven by score thresholds
## (CLUSTER_SCORE_THRESHOLDS) and, in the gaps between them, a randomized
## "freebie" timer so trash bags still trickle in during low-scoring
## stretches. Every spawn (score-based or freebie) resets the freebie timer,
## so freebies only ever fill quiet stretches and stay infrequent.
##
## Stateless w.r.t. HUD: every method takes `hud` as a parameter, both to
## read its freebie_* export tuning and level_completing flag, and because
## spawning needs hud.get_tree()/get_viewport() — Node-only calls a
## RefCounted can't make on its own — mirroring the AlienTechEffect
## convention used elsewhere in this refactor.

const TRASH_CLUSTER_SCENE = preload("res://entities/collectibles/trash_cluster/trash_cluster.tscn")
const CLUSTER_SCORE_THRESHOLDS: Array[int] = [200, 500, 800, 1200, 1600]
var _cluster_threshold_index: int = 0

var _freebie_elapsed: float = 0.0
var _freebie_next_time: float = 0.0
var _any_cluster_spawned: bool = false

## Arms the first freebie timer. Call once from HUD._ready().
func start(hud) -> void:
	_schedule_next_freebie(hud)

func _schedule_next_freebie(hud) -> void:
	_freebie_elapsed = 0.0
	if _any_cluster_spawned:
		_freebie_next_time = maxf(5.0, hud.freebie_interval + randf_range(-hud.freebie_interval_jitter, hud.freebie_interval_jitter))
	else:
		_freebie_next_time = maxf(5.0, hud.freebie_first_delay + randf_range(-hud.freebie_first_jitter, hud.freebie_first_jitter))

## Only spawn a cluster when score is actually increasing past a milestone.
## Called from HUD.update_score().
func on_score_updated(hud, new_score: int, previous_score: int) -> void:
	if new_score > previous_score and _cluster_threshold_index < CLUSTER_SCORE_THRESHOLDS.size() and new_score >= CLUSTER_SCORE_THRESHOLDS[_cluster_threshold_index]:
		_cluster_threshold_index += 1
		spawn(hud)

## Ticks the freebie timer (score-independent). Called every frame from
## HUD._process().
func process_freebie(hud, delta: float) -> void:
	if not hud.freebie_clusters_enabled or hud.level_completing:
		return
	_freebie_elapsed += delta
	if _freebie_elapsed >= _freebie_next_time:
		spawn(hud)

func spawn(hud) -> void:
	if hud.level_completing:
		return
	# Any cluster (score-based or freebie) pushes the next freebie out, so trash
	# bags stay rare and freebies only fill quiet, low-scoring stretches.
	_any_cluster_spawned = true
	_schedule_next_freebie(hud)
	var scene = hud.get_tree().current_scene
	if not scene:
		return
	var cluster = TRASH_CLUSTER_SCENE.instantiate()
	cluster.is_first_cluster = not GameManager.first_trash_cluster_spawned
	GameManager.first_trash_cluster_spawned = true
	var inv = hud.get_viewport().get_canvas_transform().affine_inverse()
	var screen_size = hud.get_viewport().get_visible_rect().size
	var spawn_y = screen_size.y * randf_range(0.3, 0.78)
	cluster.max_y = (inv * Vector2(0.0, screen_size.y * 0.82)).y
	if randf() > 0.5:
		# Spawn from right, drift left
		cluster.drift_speed = -38.0
		scene.add_child(cluster)
		cluster.global_position = inv * Vector2(screen_size.x + 55, spawn_y)
	else:
		# Spawn from left, drift right
		cluster.drift_speed = 38.0
		scene.add_child(cluster)
		cluster.global_position = inv * Vector2(-55, spawn_y)
	# Clamp spawn position and drift to the ocean band (below the surface)
	var ocean = hud.get_tree().get_first_node_in_group("ocean")
	var min_world_y = -116.0  # 10px below default surface_y of -126
	if ocean:
		min_world_y = ocean.surface_y + 10.0
	cluster.min_y = min_world_y
	cluster.global_position.y = max(cluster.global_position.y, min_world_y)
	print("👾 Trash cluster spawned at score %d" % hud.current_score)
