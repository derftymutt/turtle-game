# level_manager.gd
extends Node

## Manages level progression, piece collection, and scene transitions

signal piece_delivered(pieces_collected, pieces_needed)
signal level_complete
signal level_started(level_number)

# Level progression
var current_level_number: int = 1
var pieces_collected: int = 0
var pieces_needed: int = 3

# Level scene registry
var level_scenes: Dictionary = {
	1: "res://levels/level_1.tscn",
	2: "res://levels/level_2.tscn",
	3: "res://levels/level_3.tscn",
	# Add more as you create them
}

# Piece requirements per level
var pieces_needed_by_level: Dictionary = {
	1: 3,
	2: 4,
	3: 5,
	# etc...
}

func _ready():
	print("🎮 LevelManager initialized")

func start_level(level_number: int):
	"""Initialize a new level (called after scene loads)"""
	current_level_number = level_number
	pieces_collected = 0
	
	# Set piece requirement for this level
	if level_number in pieces_needed_by_level:
		pieces_needed = pieces_needed_by_level[level_number]
	else:
		# Default scaling: +1 piece every 2 levels
		pieces_needed = 3 + int(level_number / 2)
	
	level_started.emit(level_number)
	print("🌊 Level %d started! Collect %d UFO pieces" % [level_number, pieces_needed])

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
	
	# Update high score for completed level
	var level_name = "level_%d" % current_level_number
	GameManager.update_high_score(level_name, GameManager.current_score)
	
	# TODO: Spawn assembled UFO, play animation
	# For now, transition to next level after delay
	await get_tree().create_timer(2.0).timeout
	load_next_level()

func load_next_level():
	"""Load the next level scene"""
	var next_level = current_level_number + 1
	
	if next_level in level_scenes:
		load_level(next_level)
	else:
		print("🎉 Game complete! No more levels.")
		# TODO: Load credits/end screen
		GameManager.load_main_menu()

func load_level(level_number: int):
	"""Load a specific level scene"""
	if not level_number in level_scenes:
		push_error("Level %d not found in level_scenes!" % level_number)
		return
	
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
	load_level(current_level_number)

func get_current_level_name() -> String:
	"""Get current level identifier for high scores"""
	return "level_%d" % current_level_number

func get_level_name_for_number(level_num: int) -> String:
	"""Convert level number to level name (for high scores)"""
	return "level_%d" % level_num
