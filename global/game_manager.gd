extends Node

## Global game manager - handles level transitions and shared state
## Add this as an Autoload in Project Settings -> Autoload

# Level registry
var levels: Dictionary = {
	"level_1": "res://levels/level_1.tscn",
	"level_2": "res://levels/level_2.tscn",
	#"level_3": "res://levels/level_3.tscn",
}

# Current level info
var current_level: String = ""
var current_score: int = 0

# High scores per level (persists between sessions if you add save/load)
var high_scores: Dictionary = {
	"level_1": 0,
	"level_2": 0,
	"level_3": 0,
}

func _ready():
	print("GameManager initialized")

## Load a level by name
func load_level(level_name: String):
	if not levels.has(level_name):
		push_error("Level not found: ", level_name)
		return
	
	current_level = level_name
	current_score = 0
	
	var level_path = levels[level_name]
	get_tree().change_scene_to_file(level_path)

## Return to main menu
func load_main_menu():
	current_level = ""
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

## Restart current level
func restart_current_level():
	if current_level.is_empty():
		push_warning("No current level to restart")
		return
	
	load_level(current_level)

## Update high score if current score is higher
func update_high_score(level_name: String, score: int):
	if score > high_scores.get(level_name, 0):
		high_scores[level_name] = score
		print("New high score for ", level_name, ": ", score)

## Get high score for a level
func get_high_score(level_name: String) -> int:
	return high_scores.get(level_name, 0)
