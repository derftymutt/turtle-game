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
## Set by an intro popup that wants the start prompt to wait until it is
## dismissed (BossIntroPopup) — see hold_start_prompt().
var _start_prompt_held: bool = false

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

	if _wants_start_prompt() and not _start_prompt_held:
		show_start_prompt()

	print("📍 Level %d ready (%s)" % [level_number, scene_file_path])

## Whether the level opens frozen behind "Press any button to start". The
## tutorial and the Academy run their own scripted openings and turn it off.
func _wants_start_prompt() -> bool:
	return true

## An intro popup that is up when the level loads calls this (from its
## LevelManager.level_started / boss_level_started handler) and then
## show_start_prompt() itself once it has been dismissed.
func hold_start_prompt() -> void:
	_start_prompt_held = true

## Freezes the level until the player presses something (LevelStartPrompt).
## Only the game holds still — the level song plays through the wait.
func show_start_prompt() -> void:
	if not _wants_start_prompt():
		get_tree().paused = false
		return
	var prompt := LevelStartPrompt.new()
	# Back to pausing with the game (pause menu, popups) once the level is live
	_sfx_level_song.process_mode = Node.PROCESS_MODE_ALWAYS
	prompt.started.connect(func():
		if is_instance_valid(_sfx_level_song):
			_sfx_level_song.process_mode = Node.PROCESS_MODE_INHERIT
	)
	add_child(prompt)

## Called by turtle when player dies
func on_player_died(final_score: int, death_cause: String = ""):
	GameManager.current_score = final_score

	var level_name = LevelManager.get_current_level_name()
	GameManager.update_high_score(level_name, final_score)

	if game_over_screen:
		game_over_screen.show_game_over(final_score, GameManager.total_score, death_cause)
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
