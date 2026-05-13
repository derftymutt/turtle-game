# game_manager.gd
extends Node

## Global game state - handles persistent data across levels

# Set to true to show level-select dev buttons on the main menu
const DEV_MODE: bool = false

# Current run state
var current_score: int = 0   # Level score — resets each level via HUD._ready()
var total_score: int = 0     # Cumulative score across all completed levels this run

# UFO piece carrying state
var is_carrying_piece: bool = false
var carried_piece: Node = null

# High scores per level (persists between sessions if you add save/load)
var high_scores: Dictionary = {
	"level_1": 0,
	"level_2": 0,
	"level_3": 0,
	"level_4": 0,
	"level_5": 0,
}

func _ready():
	print("🎮 GameManager initialized")

func update_high_score(level_name: String, score: int):
	if score > high_scores.get(level_name, 0):
		high_scores[level_name] = score
		print("⭐ New high score for %s: %d" % [level_name, score])

func get_high_score(level_name: String) -> int:
	return high_scores.get(level_name, 0)

func load_main_menu():
	current_score = 0
	is_carrying_piece = false
	carried_piece = null
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func load_victory_screen():
	current_score = 0
	is_carrying_piece = false
	carried_piece = null
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menus/victory_screen.tscn")

func reset_game():
	current_score = 0
	total_score = 0
	is_carrying_piece = false
	carried_piece = null
	LevelManager.reset_run()
	AlienTechManager.reset_run()
