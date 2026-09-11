# game_manager.gd
extends Node

## Global game state - handles persistent data across levels

const _FloatingScore = preload("res://ui/floating_score/floating_score.gd")

# Set to true to show level-select dev buttons on the main menu
const DEV_MODE: bool = true

# Current run state
var current_score: int = 0   # Level score — resets each level via HUD._ready()
var total_score: int = 0     # Cumulative score across all completed levels this run

# UFO piece carrying state
# `carried_piece` stays the most-recently-picked-up piece for back-compat with
# single-piece call sites (thrust weight check, kick animation, etc.) that only
# care whether *something* is being carried. `carried_pieces` is the real list —
# normally holds at most 1, or 2 while Graviton Harness is hot (see
# max_carry_capacity()). Always go through add_carried_piece()/remove_carried_piece()
# so the two stay in sync.
var is_carrying_piece: bool = false
var carried_piece: Node = null
var carried_pieces: Array = []

# Exact heart count carried into the next level (-1 = start full, e.g. level 1)
var persisted_hearts: int = -1

# Tutorial flags — reset each run
var has_shown_tech_tutorial: bool = false
var first_trash_cluster_spawned: bool = false

# High scores per level (persists between sessions if you add save/load)
var high_scores: Dictionary = {
	"level_1": 0,
	"level_2": 0,
	"level_3": 0,
	"level_4": 0,
	"level_5": 0,
}

func _ready():
	print("🎮 GameManager initialized")

func _input(event: InputEvent) -> void:
	if not DEV_MODE:
		return
	if event.is_action_pressed("dev_screenshot"):
		_take_screenshot()
		get_viewport().set_input_as_handled()

func _take_screenshot() -> void:
	var image := get_viewport().get_texture().get_image()
	var dir := OS.get_user_data_dir() + "/screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := dir + "/screenshot_%s.png" % timestamp
	image.save_png(path)
	print("📸 Screenshot saved: ", path)

func update_high_score(level_name: String, score: int):
	if score > high_scores.get(level_name, 0):
		high_scores[level_name] = score
		print("⭐ New high score for %s: %d" % [level_name, score])

func get_high_score(level_name: String) -> int:
	return high_scores.get(level_name, 0)

func load_main_menu():
	current_score = 0
	clear_carried_pieces()
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func load_victory_screen():
	current_score = 0
	clear_carried_pieces()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menus/victory_screen.tscn")

func reset_game():
	current_score = 0
	total_score = 0
	persisted_hearts = -1
	clear_carried_pieces()
	has_shown_tech_tutorial = false
	first_trash_cluster_spawned = false
	LevelManager.reset_run()
	AlienTechManager.reset_run()

## Hot Graviton Harness lets the turtle carry 2 UFO parts at once instead of 1.
func max_carry_capacity() -> int:
	if AlienTechManager.is_tech_hot(AlienTechRegistry.GRAVITON_HARNESS):
		return 2
	return 1

func can_carry_more_pieces() -> bool:
	return carried_pieces.size() < max_carry_capacity()

func add_carried_piece(piece: Node) -> void:
	if piece in carried_pieces:
		return
	carried_pieces.append(piece)
	carried_piece = piece
	is_carrying_piece = true

func remove_carried_piece(piece: Node) -> void:
	carried_pieces.erase(piece)
	is_carrying_piece = carried_pieces.size() > 0
	carried_piece = carried_pieces.back() if is_carrying_piece else null

func clear_carried_pieces() -> void:
	is_carrying_piece = false
	carried_piece = null
	carried_pieces.clear()

func spawn_floating_score(at_position: Vector2, amount: int) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if not level:
		return
	var fs := _FloatingScore.new()
	level.add_child(fs)
	fs.global_position = at_position
	fs.setup(amount)
