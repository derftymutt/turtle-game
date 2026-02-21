# space_debris_group.gd
extends Node2D
class_name SpaceDebrisGroup

## Manages a named group of space debris pieces floating in the sky.
##
## SETUP (in the scene editor):
##   1. Add a SpaceDebrisGroup node to your sky level.
##   2. Add 3 SpaceDebris nodes as CHILDREN of this node.
##      (These are the pre-placed pieces — position them where you want.)
##   3. Set group_label and powerup_type in the Inspector.
##   4. Assign powerup_scene in the Inspector.
##
## BEHAVIOR:
##   - Tracks how many of its child debris pieces are still alive.
##   - When the LAST piece is destroyed, spawns a powerup at that location.
##   - Emits group_cleared so the level / HUD can react (bonus points, fanfare, etc.)
##
## EXPANDABILITY:
##   - Add more powerup types to Powerup.PowerupType and select them here.
##   - Override spawn_powerup() in a subclass for special sky-only powerups.
##   - The group could respawn after a delay if you set respawn_delay > 0.

signal group_cleared(group: SpaceDebrisGroup)

# ── Configuration ─────────────────────────────────────────────────────────
## Human-readable identifier shown in debug output and (optionally) the HUD.
@export var group_label: String = "Group A"

## Which powerup to drop when all pieces in this group are cleared.
@export var powerup_type: Powerup.PowerupType = Powerup.PowerupType.SHIELD

## The powerup scene to instantiate when the group is cleared.
@export var powerup_scene: PackedScene

## Bonus score awarded when the ENTIRE group is cleared (on top of per-piece scores).
@export var clear_bonus: int = 100

## If > 0, the group respawns this many seconds after being cleared.
## Set to 0 to disable respawning (debris is gone for the level).
@export var respawn_delay: float = 0.0

# ── Runtime State ──────────────────────────────────────────────────────────
## All SpaceDebris children, populated in _ready().
var debris_pieces: Array[SpaceDebris] = []

## How many pieces are still alive.
var alive_count: int = 0

## Whether this group has already been cleared (prevents double-firing).
var is_cleared: bool = false

## Position of the last piece destroyed — used for powerup spawn location.
var last_destroyed_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("space_debris_groups")
	_register_children()


func _register_children() -> void:
	"""Find all SpaceDebris children and hook up their destroyed signals."""
	debris_pieces.clear()

	for child in get_children():
		if child is SpaceDebris:
			debris_pieces.append(child)
			child.group_owner = self
			child.debris_destroyed.connect(_on_debris_destroyed)

	alive_count = debris_pieces.size()

	if alive_count == 0:
		push_warning(
			"SpaceDebrisGroup '%s': No SpaceDebris children found! " \
			% group_label +
			"Add SpaceDebris nodes as children of this group."
		)
	else:
		print("☁️  SpaceDebrisGroup '%s' ready — %d pieces" % [group_label, alive_count])


# ── Signal Handlers ────────────────────────────────────────────────────────

func _on_debris_destroyed(debris: SpaceDebris) -> void:
	"""Called every time one of our pieces gets shot."""
	if is_cleared:
		return  # Already cleared — shouldn't happen, but guard against it

	last_destroyed_position = debris.global_position
	alive_count -= 1

	print("☁️  '%s': %d/%d pieces remaining" % [group_label, alive_count, debris_pieces.size()])

	if alive_count <= 0:
		_on_group_cleared()


func _on_group_cleared() -> void:
	"""All pieces are gone — award the player."""
	is_cleared = true

	print("🎉 SpaceDebrisGroup '%s' cleared! Spawning powerup..." % group_label)

	# Bonus score for clearing the whole group
	var hud: HUD = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_score(clear_bonus)

	# Spawn the powerup at the location of the last destroyed piece.
	# The powerup will fall with gravity into the ocean below.
	spawn_powerup(last_destroyed_position)

	# Notify the level (for UI, achievements, etc.)
	group_cleared.emit(self)

	# Optional: respawn after a delay
	if respawn_delay > 0.0:
		get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


# ── Powerup Spawning ───────────────────────────────────────────────────────

func spawn_powerup(spawn_position: Vector2) -> void:
	"""Instantiate and place the reward powerup."""
	if not powerup_scene:
		push_error("SpaceDebrisGroup '%s': powerup_scene not assigned in Inspector!" % group_label)
		return

	var powerup: Powerup = powerup_scene.instantiate()

	# Add to the level root (not as a child of this group) so it persists
	# even if the group node is removed or restructured.
	get_tree().get_first_node_in_group("level").add_child(powerup)

	powerup.global_position = spawn_position
	powerup.powerup_type = powerup_type

	# The powerup.gd already handles falling via gravity_scale,
	# so it will naturally drop down toward the ocean.

	# Play the correct animation if the powerup has one.
	var sprite := powerup.get_node_or_null("AnimatedSprite2D")
	if sprite and sprite is AnimatedSprite2D:
		match powerup_type:
			Powerup.PowerupType.SHIELD:
				sprite.play("shield")
			Powerup.PowerupType.AIR_RESERVE:
				sprite.play("air")
			Powerup.PowerupType.STAMINA_FREEZE:
				sprite.play("stamina")

	print("🎁 Powerup spawned at ", spawn_position, " type: ", Powerup.PowerupType.keys()[powerup_type])


# ── Respawn ────────────────────────────────────────────────────────────────

func _respawn() -> void:
	"""Re-instantiate all debris pieces at their original positions."""
	# We can't simply "un-destroy" the old nodes because they've queue_free'd.
	# Instead, we re-instance from the packed scene referenced on each piece.
	# For now this is a placeholder — full respawn requires storing original
	# transforms and a reference to the debris packed scene.
	# TODO: implement when respawn is needed for the design.
	push_warning("SpaceDebrisGroup '%s': respawn not yet implemented." % group_label)
	is_cleared = false
	alive_count = 0


# ── Public Helpers ─────────────────────────────────────────────────────────

func get_alive_count() -> int:
	return alive_count

func get_total_count() -> int:
	return debris_pieces.size()

func is_group_cleared() -> bool:
	return is_cleared
