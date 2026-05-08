# level_manager.gd
extends Node

## Manages level progression, piece collection, and scene transitions

signal piece_delivered(pieces_collected, pieces_needed)
signal level_complete
signal level_started(level_number)
signal boss_level_started(level_number)

# Level progression
var current_level_number: int = 1
var pieces_collected: int = 0
var pieces_needed: int = 3
var attempt_count: int = 1  # How many attempts on the current level
var alien_tech_pieces_collected: int = 0  # Persists across retries; resets only on new level
var flora_hidden_budget: int = -1          # Rolled once per level; -1 = not yet rolled

# Level scene registry
var level_scenes: Dictionary = {
	1: "res://levels/level_1.tscn",
	2: "res://levels/level_2.tscn",
	3: "res://levels/level_3.tscn",
	4: "res://levels/level_4.tscn",
	5: "res://levels/level_5.tscn",
	# Add more as you create them
}

# Piece requirements per level
var pieces_needed_by_level: Dictionary = {
	1: 3,
	2: 3,
	3: 3,
	4: 3
	# etc...
}

# Performance bonus constants
const FIRST_TRY_BONUS: int = 300
const MAX_TIME_BONUS: int = 300
const VARIETY_BONUS_PER_TECH: int = 75

# Boss levels — completion is triggered by defeating the boss, not delivering pieces
var boss_levels: Dictionary = {
	5: true,
	# Add future boss levels here
}

func _ready():
	print("🎮 LevelManager initialized")

func is_boss_level(level_number: int = -1) -> bool:
	"""Returns true if the given level (or current level) is a boss level"""
	var lvl := level_number if level_number >= 0 else current_level_number
	return lvl in boss_levels

func start_level(level_number: int):
	"""Initialize a new level (called after scene loads)"""
	current_level_number = level_number
	pieces_collected = 0

	if is_boss_level(level_number):
		pieces_needed = 0
		level_started.emit(level_number)
		boss_level_started.emit(level_number)
		print("🦈 Level %d started! Boss level — defeat the boss!" % level_number)
		return

	# Set piece requirement for this level
	if level_number in pieces_needed_by_level:
		pieces_needed = pieces_needed_by_level[level_number]
	else:
		# Default scaling: +1 piece every 2 levels
		pieces_needed = 3 + int(level_number / 2)

	level_started.emit(level_number)
	print("🌊 Level %d started! Collect %d UFO pieces" % [level_number, pieces_needed])

	# Emit initial piece count to update HUD (0/x)
	piece_delivered.emit(0, pieces_needed)

func boss_defeated():
	"""Called by a boss enemy when it dies — triggers level completion"""
	if not is_boss_level():
		push_warning("boss_defeated() called on non-boss level %d!" % current_level_number)
		return
	print("💥 Boss defeated! Level %d complete!" % current_level_number)
	complete_level()

func deliver_piece():
	"""Called by UFOWorkshop when a piece is delivered"""
	if not GameManager.is_carrying_piece:
		push_warning("Tried to deliver piece but not carrying one!")
		return
	
	pieces_collected += 1
	piece_delivered.emit(pieces_collected, pieces_needed)
	
	print("✨ Piece delivered! Progress: %d/%d" % [pieces_collected, pieces_needed])
	
	# Check win condition
	if pieces_collected >= pieces_needed:
		complete_level()

func complete_level():
	"""Trigger level completion sequence"""
	level_complete.emit()
	print("🚀 Level %d complete! Assembling UFO..." % current_level_number)

	# Freeze HUD timer immediately so time_remaining stays accurate for bonus calc
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("freeze_timer"):
		hud.freeze_timer()

	# Compute per-level performance bonuses
	var time_bonus: int = 0
	if hud and hud.get("timer_enabled"):
		time_bonus = int(floor(hud.time_remaining / hud.level_time_limit * MAX_TIME_BONUS))
	var first_try_bonus: int = FIRST_TRY_BONUS if attempt_count == 1 else 0

	# Accumulate level score + per-level bonuses into run total
	GameManager.total_score += GameManager.current_score + time_bonus + first_try_bonus

	print("📊 Level bonuses — Time: +%d, First Try: +%d" % [time_bonus, first_try_bonus])

	# Update high score for completed level
	var level_name = "level_%d" % current_level_number
	GameManager.update_high_score(level_name, GameManager.current_score)

	# Show level complete screen
	_show_level_complete_screen(time_bonus, first_try_bonus)
	# Progression is now driven by the player pressing "Next Level" on the completion screen

func _show_level_complete_screen(time_bonus: int, first_try_bonus: int):
	var level_complete_screen = get_tree().get_first_node_in_group("level_complete_screen")
	if level_complete_screen and level_complete_screen.has_method("show_completion"):
		level_complete_screen.show_completion(
			current_level_number,
			GameManager.current_score,
			GameManager.total_score,
			time_bonus,
			first_try_bonus,
			AlienTechManager.get_variety_count(),
			pieces_collected,
			pieces_needed,
			attempt_count
		)
	else:
		print("⚠️ No LevelCompleteScreen found in scene. Add one to levels for visual feedback!")

func load_next_level():
	"""Load the next level scene"""
	var next_level = current_level_number + 1
	
	if next_level in level_scenes:
		load_level(next_level)
	else:
		var variety_bonus = AlienTechManager.get_variety_count() * VARIETY_BONUS_PER_TECH
		GameManager.total_score += variety_bonus
		print("🎉 Game complete! Variety bonus: +%d (%d unique techs). Final score: %d" % [
			variety_bonus, AlienTechManager.get_variety_count(), GameManager.total_score
		])
		GameManager.load_main_menu()

func load_level(level_number: int):
	"""Load a specific level scene"""
	if not level_number in level_scenes:
		push_error("Level %d not found in level_scenes!" % level_number)
		return

	# Reset attempts only when loading a genuinely new level (not a retry)
	if level_number != current_level_number:
		attempt_count = 1
		alien_tech_pieces_collected = 0
		flora_hidden_budget = -1
	current_level_number = level_number
	pieces_collected = 0  # Reset for new level
	
	var level_path = level_scenes[level_number]
	print("📂 Loading level %d: %s" % [level_number, level_path])
	
	# Reset carrying state between levels
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	
	get_tree().change_scene_to_file(level_path)

func restart_current_level():
	"""Restart the current level (for game over)"""
	attempt_count += 1
	load_level(current_level_number)

func get_or_roll_flora_budget(min_count: int, max_count: int) -> int:
	if flora_hidden_budget < 0:
		flora_hidden_budget = randi_range(min_count, max_count)
		print("🌿 Flora tech budget rolled: %d (range %d–%d)" % [flora_hidden_budget, min_count, max_count])
	return flora_hidden_budget

func record_alien_tech_collected():
	alien_tech_pieces_collected += 1
	print("🌿 Flora tech banked: %d/%d collected this level" % [alien_tech_pieces_collected, alien_tech_pieces_collected])

func get_current_level_name() -> String:
	"""Get current level identifier for high scores"""
	return "level_%d" % current_level_number

func get_level_name_for_number(level_num: int) -> String:
	"""Convert level number to level name (for high scores)"""
	return "level_%d" % level_num
