extends Node2D
class_name LevelBase

## Base level class - all levels inherit from this
## Provides shared HUD, GameOver screen, and level management

@export var level_name: String = "level_1"  # Set this in each level's Inspector

@onready var hud: HUD = $HUD
@onready var game_over_screen: GameOverScreen = $GameOverScreen

func _ready():
	# Register this level with GameManager
	GameManager.current_level = level_name
	
	# Ensure game is unpaused
	get_tree().paused = false

## Called by turtle when player dies
func on_player_died(final_score: int):
	# Update high score
	GameManager.update_high_score(level_name, final_score)
	
	# Show game over screen
	if game_over_screen:
		game_over_screen.show_game_over(final_score, level_name)
