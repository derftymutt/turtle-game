# level_base.gd
extends Node2D
class_name LevelBase

## Base level class - all levels inherit from this
## Provides shared HUD, GameOver screen, and level management

@export var level_number: int = 1  # Set this in each level's Inspector (1, 2, 3, etc.)

@onready var hud: HUD = $HUD
@onready var game_over_screen: GameOverScreen = $GameOverScreen
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var _sfx_level_song: AudioStreamPlayer = $SfxLevelSong

var _level_song_base_volume: float

func _ready():
	# Ensure game is unpaused
	get_tree().paused = false

	# Store normal volume for ducking
	_level_song_base_volume = _sfx_level_song.volume_db

	# Loop the level music and stop it when the level completes
	_sfx_level_song.finished.connect(func(): _sfx_level_song.play())
	LevelManager.level_complete.connect(func():
		if is_instance_valid(_sfx_level_song):
			_sfx_level_song.stop()
	, CONNECT_ONE_SHOT)

	# Duck level song during low-air warning
	hud.low_air_warning_changed.connect(_on_low_air_warning_changed)

	# Initialize this level with LevelManager
	LevelManager.start_level(level_number)

	print("📍 Level %d ready (%s)" % [level_number, scene_file_path])

## Called by turtle when player dies
func on_player_died(final_score: int):
	GameManager.current_score = final_score

	var level_name = LevelManager.get_current_level_name()
	GameManager.update_high_score(level_name, final_score)

	if game_over_screen:
		game_over_screen.show_game_over(final_score, GameManager.total_score)
	else:
		push_warning("No GameOverScreen found! Restarting level...")
		await get_tree().create_timer(2.0).timeout
		LevelManager.restart_current_level()

## Duck level music during low-air warning, restore when safe
func _on_low_air_warning_changed(is_warning: bool) -> void:
	if not is_instance_valid(_sfx_level_song):
		return
	var target_db := _level_song_base_volume - (15.0 if is_warning else 0.0)
	var tween := create_tween()
	tween.tween_property(_sfx_level_song, "volume_db", target_db, 0.6)
