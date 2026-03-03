# sky_star_seeder.gd
extends Node2D
class_name SkyStarSeeder

## Seeds the sky with collectible stars at level start.
## Monitors how many remain; when the count drops to the respawn threshold,
## it reseeds back up to initial_count — one star at a time, in quick succession.

@export var sky_star_scene: PackedScene

@export_group("Seeding Settings")
## How many stars to place when the level starts (and after each reseed)
@export var initial_count: int = 10
## When this many stars remain, trigger a reseed back to initial_count
@export var respawn_threshold: int = 3
## Seconds to wait between spawning each individual star during a reseed
@export var respawn_stagger_delay: float = 0.15

@export_group("Sky Region")
@export var sky_min_x: float = -260.0
@export var sky_max_x: float = 260.0
@export var sky_min_y: float = -400.0
@export var sky_max_y: float = -200.0

## Minimum pixel distance between any two sky stars to prevent overlap
@export var min_spacing: float = 40.0

# -- Runtime state --
var active_stars: Array[Node] = []
var current_count: int = 0
var reseeding: bool = false

func _ready():
	if not sky_star_scene:
		push_error("SkyStarSeeder: No sky_star_scene assigned!")
		return

	# Wait one frame for the level to fully initialise before seeding
	await get_tree().create_timer(0.2).timeout
	_seed_sky(initial_count)

# ---------------------------------------------------------------------------
# Seeding
# ---------------------------------------------------------------------------

func _seed_sky(count: int) -> void:
	print("🌟 SkyStarSeeder: Seeding sky with %d stars..." % count)
	for i in count:
		_spawn_star()
	print("✓ SkyStarSeeder: Done — %d sky stars placed." % current_count)

func _spawn_star() -> void:
	if not sky_star_scene:
		return

	var star: Node = sky_star_scene.instantiate()
	get_parent().add_child(star)

	star.global_position = _get_spaced_sky_position()
	active_stars.append(star)
	current_count += 1

	# Listen for when this star gets collected
	if star.has_signal("star_collected"):
		star.star_collected.connect(_on_star_collected)

# ---------------------------------------------------------------------------
# Respawning
# ---------------------------------------------------------------------------

func _on_star_collected() -> void:
	current_count -= 1
	print("🌟 SkyStarSeeder: Star collected — remaining: %d (threshold: %d)" \
		% [current_count, respawn_threshold])

	if current_count <= respawn_threshold and not reseeding:
		_start_reseed()

func _start_reseed() -> void:
	reseeding = true
	var stars_to_add: int = initial_count - current_count
	print("🌟 SkyStarSeeder: Reseeding — adding %d stars one by one..." % stars_to_add)

	for i in stars_to_add:
		await get_tree().create_timer(respawn_stagger_delay).timeout

		# Prune freed references before each spawn so position checks are accurate
		active_stars = active_stars.filter(func(s): return is_instance_valid(s))

		_spawn_star()

	reseeding = false
	print("✓ SkyStarSeeder: Reseed complete — %d sky stars active." % current_count)

# ---------------------------------------------------------------------------
# Position helpers
# ---------------------------------------------------------------------------

func _get_spaced_sky_position() -> Vector2:
	"""Return a random sky position that doesn't overlap any existing sky star."""
	# Build a fresh list of occupied positions from valid, uncollected stars
	var occupied: Array[Vector2] = []
	for star in active_stars:
		if is_instance_valid(star) and not star.collected:
			occupied.append(star.global_position)

	var max_attempts: int = 40
	for attempt in max_attempts:
		var candidate := Vector2(
			randf_range(sky_min_x, sky_max_x),
			randf_range(sky_min_y, sky_max_y)
		)
		if _is_position_valid(candidate, occupied):
			return candidate

	# Fallback: return a random position even if spacing isn't ideal
	push_warning("SkyStarSeeder: Could not find a non-overlapping position after %d attempts." \
		% max_attempts)
	return Vector2(randf_range(sky_min_x, sky_max_x), randf_range(sky_min_y, sky_max_y))

func _is_position_valid(pos: Vector2, occupied: Array[Vector2]) -> bool:
	for occ in occupied:
		if pos.distance_to(occ) < min_spacing:
			return false
	return true

# ---------------------------------------------------------------------------
# Editor visualisation
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect_pos  := Vector2(sky_min_x, sky_min_y)
	var rect_size := Vector2(sky_max_x - sky_min_x, sky_max_y - sky_min_y)
	# Filled tint
	draw_rect(Rect2(rect_pos, rect_size), Color(1.0, 1.0, 0.2, 0.12))
	# Outline
	draw_rect(Rect2(rect_pos, rect_size), Color(1.0, 1.0, 0.2, 0.85), false, 1.5)
	# Spacing guide dots along the top
	var step: float = min_spacing
	var x: float = sky_min_x
	while x <= sky_max_x:
		draw_circle(Vector2(x, sky_min_y + (sky_max_y - sky_min_y) * 0.5),
			min_spacing * 0.5, Color(1.0, 1.0, 0.2, 0.08))
		x += step
