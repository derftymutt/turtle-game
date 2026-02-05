extends Node

## Global game settings that persist across scenes
## This autoload stores player preferences like control schemes

# Control settings
var thrust_inverted: bool = false

# Add this to Project Settings > Autoload as "GameSettings"

func _ready():
	# Load saved settings if you add save/load later
	pass

func set_thrust_inverted(inverted: bool):
	thrust_inverted = inverted
	# Notify all active turtle players to update
	get_tree().call_group("player", "_on_settings_changed")
