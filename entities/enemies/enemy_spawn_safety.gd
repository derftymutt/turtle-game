# enemy_spawn_safety.gd
class_name EnemySpawnSafety

## Keeps enemies from appearing on top of the turtle. Spawners that pick a
## random point use random_point() to choose it, and — since the turtle keeps
## moving through the spawn telegraph — move_clear() again at the moment the
## enemy actually appears.

## No enemy materialises closer to the turtle than this
const MIN_TURTLE_DISTANCE: float = 56.0

const _PICK_ATTEMPTS: int = 30
const _NUDGE_DIRECTIONS: int = 16

## True when pos is at least `radius` from the turtle (or there is no turtle).
static func is_clear(tree: SceneTree, pos: Vector2, radius: float = MIN_TURTLE_DISTANCE) -> bool:
	var player := tree.get_first_node_in_group("player") as Node2D
	return player == null or pos.distance_to(player.global_position) >= radius

## Random point in the rectangle, at least `radius` from the turtle. If the
## turtle somehow covers the whole area, returns the farthest point tried.
static func random_point(tree: SceneTree, area_min: Vector2, area_max: Vector2,
		radius: float = MIN_TURTLE_DISTANCE) -> Vector2:
	var player := tree.get_first_node_in_group("player") as Node2D
	var best := Vector2.ZERO
	var best_dist: float = -1.0
	for _attempt in _PICK_ATTEMPTS:
		var pos := Vector2(
			randf_range(area_min.x, area_max.x),
			randf_range(area_min.y, area_max.y))
		if player == null:
			return pos
		var dist: float = pos.distance_to(player.global_position)
		if dist >= radius:
			return pos
		if dist > best_dist:
			best_dist = dist
			best = pos
	return best

## pos itself if it is clear of the turtle; otherwise the nearest point on the
## `radius` circle around the turtle that stays inside the rectangle.
static func move_clear(tree: SceneTree, pos: Vector2, area_min: Vector2, area_max: Vector2,
		radius: float = MIN_TURTLE_DISTANCE) -> Vector2:
	var player := tree.get_first_node_in_group("player") as Node2D
	if player == null or pos.distance_to(player.global_position) >= radius:
		return pos
	var center: Vector2 = player.global_position
	var best := pos
	var best_dist: float = INF
	for i in _NUDGE_DIRECTIONS:
		# A hair past the radius so float error can't leave it just inside
		var candidate: Vector2 = center + Vector2.RIGHT.rotated(TAU * i / _NUDGE_DIRECTIONS) * (radius + 1.0)
		if candidate.x < area_min.x or candidate.x > area_max.x \
				or candidate.y < area_min.y or candidate.y > area_max.y:
			continue
		var dist: float = candidate.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	if best_dist == INF:
		# The turtle covers the whole area — take the corner farthest from it
		for corner in [area_min, area_max, Vector2(area_min.x, area_max.y), Vector2(area_max.x, area_min.y)]:
			if best_dist == INF or corner.distance_to(center) > best.distance_to(center):
				best = corner
				best_dist = 0.0
	return best
