extends Node

## Global game settings that persist across scenes and sessions

const SETTINGS_PATH = "user://settings.json"

# Control settings
var thrust_inverted: bool = false

# Difficulty
var hard_mode: bool = false

func _ready():
	_load_settings()

func _load_settings():
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Dictionary:
		thrust_inverted = result.get("thrust_inverted", false)
		hard_mode = result.get("hard_mode", false)

func _save_settings():
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"thrust_inverted": thrust_inverted,
			"hard_mode": hard_mode,
		}))
		file.close()

func set_thrust_inverted(inverted: bool):
	thrust_inverted = inverted
	_save_settings()
	get_tree().call_group("player", "_on_settings_changed")

func set_hard_mode(enabled: bool):
	hard_mode = enabled
	_save_settings()
