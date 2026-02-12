# game_manager.gd
extends Node

## Global game state - handles persistent data across levels
## Add this as an Autoload in Project Settings -> Autoload

# Current run state
var current_score: int = 0

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
	# Add more as needed
}

func _ready():
	print("🎮 GameManager initialized")
	#load_main_menu()

## Update high score if current score is higher
func update_high_score(level_name: String, score: int):
	if score > high_scores.get(level_name, 0):
		high_scores[level_name] = score
		print("⭐ New high score for %s: %d" % [level_name, score])
		# TODO: Save to file here if you want persistence

## Get high score for a level
func get_high_score(level_name: String) -> int:
	return high_scores.get(level_name, 0)

## Return to main menu
func load_main_menu():
	current_score = 0
	is_carrying_piece = false
	carried_piece = null
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

## Reset game state (for new game from menu)
func reset_game():
	current_score = 0
	is_carrying_piece = false
	carried_piece = null
