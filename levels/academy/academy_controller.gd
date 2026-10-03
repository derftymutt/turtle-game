# academy_controller.gd
extends LevelBase
class_name AcademyController

## Root node of the UFO Repair Turtle Academy level. Extends LevelBase so the
## HUD, pause menu and alien tech flow behave exactly as in a normal level;
## scoring, saving and level progression are suppressed by
## LevelManager.is_tutorial (the shared "training mode" flag).
##
## The left third of the screen is out of play: the ocean's left wall sits at
## the edge of the AcademyPanel (academy_panel.gd), which holds the agenda and
## the instructor's dialogue. The course itself is run by AcademyDirector
## (academy_director.gd), which adds game elements as the lessons progress.

## The turtle died and has already been put back at the spawn point. The
## director restarts whatever challenge was running.
signal player_respawned

var _player_spawn := Vector2.ZERO

## Deaths put the turtle back this far under the ocean surface (at the start
## point's x) rather than at the surface start point, where the crocodile
## patrols and would catch it again straight away.
const RESPAWN_DEPTH := 40.0

func _ready() -> void:
	super._ready()
	# Safety net: if the scene is launched directly (F6) instead of via
	# LevelManager.load_academy(), still flag training mode so nothing tries
	# to score or advance levels.
	LevelManager.is_tutorial = true
	var turtle := get_node_or_null("TurtlePlayer")
	if turtle is Node2D:
		_player_spawn = (turtle as Node2D).global_position

## Called by the turtle when it dies. The academy has no game over — put the
## player back at the spawn point, fully healed, with a moment of invulnerability.
func on_player_died(final_score: int, death_cause: String = "") -> void:
	if not LevelManager.is_tutorial:
		super.on_player_died(final_score, death_cause)
		return
	_respawn_player()
	player_respawned.emit()

func _respawn_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	# A carried piece is let go where the turtle died rather than teleporting along.
	for piece in GameManager.carried_pieces.duplicate():
		if is_instance_valid(piece) and piece.has_method("drop_piece"):
			piece.drop_piece()
	if p is Node2D:
		var spot := _player_spawn
		var ocean := get_tree().get_first_node_in_group("ocean")
		if ocean:
			spot.y = float(ocean.get("surface_y")) + RESPAWN_DEPTH
		(p as Node2D).global_position = spot
	if p is RigidBody2D:
		(p as RigidBody2D).linear_velocity = Vector2.ZERO
		(p as RigidBody2D).angular_velocity = 0.0
	if p.has_method("restore_hearts"):
		p.restore_hearts(99)  # clamps to full; also refreshes the HUD hearts
	if p.has_method("grant_grace_iframes"):
		p.grant_grace_iframes(2.5)
