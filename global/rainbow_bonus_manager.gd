# rainbow_bonus_manager.gd
extends Node

## Takes the turtle into the bonus rainbow level and back.
##
## The level the turtle came from isn't saved and reloaded — it's frozen and
## set aside (detached from the tree) while the bonus level is the current
## scene, then put back as it was: UFO pieces, score, health, level timer,
## enemies and all. Only what crosses over is synced by hand: hearts and score
## go in and come back, a carried UFO piece is held back from the bonus turtle.
##
## Things to know about a detached level:
##  - Its nodes still receive signals from autoloads. Handlers that touch the
##    tree check is_inside_tree() first (TurtlePlayer, TechAura,
##    AlienTechSelectionScreen).
##  - SceneTreeTimers keep running, so the level is disabled and given a
##    second (the fade to white) for in-flight awaits to finish before it's
##    detached.

signal bonus_started
## `score_gained` = points scored inside the bonus level.
signal bonus_finished(score_gained: int)

const BONUS_SCENE_PATH := "res://levels/bonus/rainbow_bonus_level.tscn"
const _FADE_IN_TIME := 1.0
const _FADE_OUT_TIME := 0.5
## Invulnerable this long after coming back — the turtle drops from the
## rainbow into whatever's below
const RETURN_GRACE_TIME := 2.5

var active: bool = false

var _level: Node = null
var _bonus: Node = null
var _on_return: Callable
var _finishing: bool = false
var _start_score: int = 0
var _saved_carried: Array = []
var _level_camera: Camera2D = null

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 120
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(1, 1, 1, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)

## Leaves the current level for the bonus rainbow level. `on_return` runs once
## the level is back in the tree (RainbowFishSpawner uses it to close the
## entrance and let go of the turtle).
func enter(on_return: Callable = Callable()) -> void:
	if active:
		return
	active = true
	_finishing = false
	_on_return = on_return
	_level = get_tree().current_scene
	# Freeze it (spawners stop starting new work; physics bodies leave the
	# world) and give in-flight timers the fade to finish while still in tree.
	_level.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade_to(1.0, _FADE_IN_TIME)

	var turtle = get_tree().get_first_node_in_group("player")
	var hud = get_tree().get_first_node_in_group("hud")
	var hearts: int = turtle.current_hearts if turtle else -1
	_start_score = hud.current_score if hud else GameManager.current_score
	_level_camera = get_viewport().get_camera_2d()
	_saved_carried = GameManager.carried_pieces.duplicate()
	GameManager.clear_carried_pieces()

	get_tree().root.remove_child(_level)

	# The bonus turtle reads its starting hearts from persisted_hearts
	var persisted := GameManager.persisted_hearts
	GameManager.persisted_hearts = hearts
	_bonus = (load(BONUS_SCENE_PATH) as PackedScene).instantiate()
	get_tree().root.add_child(_bonus)
	get_tree().current_scene = _bonus
	GameManager.persisted_hearts = persisted
	# A fresh HUD zeroes the score — carry the level's score in. Seeding
	# current_score first means update_score() doesn't see a jump from 0 (which
	# would count as crossing the trash-cluster score thresholds).
	var bonus_hud = get_tree().get_first_node_in_group("hud")
	if bonus_hud:
		bonus_hud.current_score = _start_score
		bonus_hud.update_score(_start_score)
	_bonus.tree_exited.connect(_on_bonus_left_tree)
	get_tree().paused = false
	bonus_started.emit()
	await _fade_to(0.0, _FADE_OUT_TIME)

## Ends the bonus level and puts the original level back. Called by the bonus
## level when the turtle falls out the bottom or dies.
func finish() -> void:
	if not active or _finishing or not _bonus:
		return
	_finishing = true
	await _fade_to(1.0, _FADE_OUT_TIME)

	var bonus_turtle = get_tree().get_first_node_in_group("player")
	var bonus_hud = get_tree().get_first_node_in_group("hud")
	var hearts: int = maxi(1, bonus_turtle.current_hearts) if bonus_turtle else 1
	var score: int = bonus_hud.current_score if bonus_hud else _start_score

	_bonus.tree_exited.disconnect(_on_bonus_left_tree)
	get_tree().root.remove_child(_bonus)
	_bonus.queue_free()
	_bonus = null

	get_tree().root.add_child(_level)
	get_tree().current_scene = _level
	_level.process_mode = Node.PROCESS_MODE_INHERIT

	var turtle = get_tree().get_first_node_in_group("player")
	var hud = get_tree().get_first_node_in_group("hud")
	for piece in _saved_carried:
		if is_instance_valid(piece):
			GameManager.add_carried_piece(piece)
	_saved_carried.clear()
	if turtle:
		turtle.current_hearts = hearts
		turtle.grant_grace_iframes(RETURN_GRACE_TIME)
		# Slots may have changed in the bonus level (a tech picked up)
		turtle._on_alien_tech_slots_changed_player(AlienTechManager.slots[0], AlienTechManager.slots[1])
	if hud:
		hud.update_hearts(hearts)
		hud.update_score(score)
		hud._tech_slots.refresh()
	if is_instance_valid(_level_camera):
		_level_camera.make_current()
	get_tree().paused = false
	_level = null
	active = false
	if _on_return.is_valid():
		_on_return.call()
	bonus_finished.emit(score - _start_score)
	await _fade_to(0.0, _FADE_OUT_TIME)

## The bonus scene went away some other way (restart / main menu from the
## pause menu) — the set-aside level goes with it.
func _on_bonus_left_tree() -> void:
	if is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_bonus = null
	_saved_carried.clear()
	active = false
	_fade_rect.color.a = 0.0

func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, duration)
	await tween.finished
