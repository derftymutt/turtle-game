# level_base.gd
extends Node2D
class_name LevelBase

## Base level class - all levels inherit from this
## Provides shared HUD, GameOver screen, and level management

@export var level_number: int = 1  # Set this in each level's Inspector (1, 2, 3, etc.)

@onready var hud: HUD = $HUD
@onready var game_over_screen: GameOverScreen = $GameOverScreen

func _ready():
	# Ensure game is unpaused
	get_tree().paused = false
	
	# Initialize this level with LevelManager
	LevelManager.start_level(level_number)
	
	print("📍 Level %d ready (%s)" % [level_number, scene_file_path])

## Called by turtle when player dies
func on_player_died(final_score: int):
	# Update GameManager's current score
	GameManager.current_score = final_score
	
	# Update high score for this level
	var level_name = LevelManager.get_current_level_name()
	GameManager.update_high_score(level_name, final_score)
	
	# Show game over screen (no level_name parameter needed!)
	if game_over_screen:
		game_over_screen.show_game_over(final_score)
	else:
		push_warning("No GameOverScreen found! Restarting level...")
		await get_tree().create_timer(2.0).timeout
		LevelManager.restart_current_level()
