# tutorial_controller.gd
extends LevelBase
class_name TutorialController

## Root node of the tutorial level. Extends LevelBase so the HUD, pause menu and
## game-over screen all behave exactly as in a normal level; scoring and level
## progression are suppressed by LevelManager.is_tutorial.
##
## The scripted lesson sequence itself lives on the TutorialUI CanvasLayer
## (tutorial_director.gd), which runs with process_mode = ALWAYS so its prompts
## survive the pauses between beats.

var _player_spawn := Vector2.ZERO

func _ready() -> void:
	super._ready()
	# Safety net: if the scene is launched directly (F6) instead of via
	# LevelManager.load_tutorial(), still flag tutorial mode so nothing tries
	# to score or advance levels.
	LevelManager.is_tutorial = true
	var turtle := get_node_or_null("TurtlePlayer")
	if turtle is Node2D:
		_player_spawn = (turtle as Node2D).global_position

## Called by the turtle when it dies. In the tutorial there's no fail state —
## just put the player back where they started, fully healed, with a moment of
## invulnerability so they aren't instantly re-hit.
func on_player_died(final_score: int) -> void:
	if not LevelManager.is_tutorial:
		super.on_player_died(final_score)
		return
	_respawn_player()

func _respawn_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p is Node2D:
		(p as Node2D).global_position = _player_spawn
	if p is RigidBody2D:
		(p as RigidBody2D).linear_velocity = Vector2.ZERO
		(p as RigidBody2D).angular_velocity = 0.0
	if p.has_method("restore_hearts"):
		p.restore_hearts(99)  # clamps to full; also refreshes the HUD hearts
	p.set("_contact_iframes_active", true)
	p.set("_contact_iframes_timer", 2.5)
