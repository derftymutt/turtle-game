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
	
	# DEBUG: Print CanvasLayer info
	if hud:
		print("HUD Layer: ", hud.layer)
		print("HUD Offset: ", hud.offset)
		print("HUD Follow Viewport: ", hud.follow_viewport_enabled)
		print("HUD Transform: ", hud.transform)
	
	if game_over_screen:
		print("GameOver Layer: ", game_over_screen.layer)
		print("GameOver Offset: ", game_over_screen.offset)
		print("GameOver Follow Viewport: ", game_over_screen.follow_viewport_enabled)
		print("GameOver Transform: ", game_over_screen.transform)
	
	print("Level loaded: ", level_name)
	

## Called by turtle when player dies
func on_player_died(final_score: int):
	# Update high score
	GameManager.update_high_score(level_name, final_score)
	
	# Show game over screen
	if game_over_screen:
		game_over_screen.show_game_over(final_score, level_name)
