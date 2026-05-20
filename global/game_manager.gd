# game_manager.gd
extends Node

## Global game state - handles persistent data across levels

const _FloatingScore = preload("res://ui/floating_score/floating_score.gd")

# Set to true to show level-select dev buttons on the main menu
const DEV_MODE: bool = false

# Current run state
var current_score: int = 0   # Level score — resets each level via HUD._ready()
var total_score: int = 0     # Cumulative score across all completed levels this run

# UFO piece carrying state
var is_carrying_piece: bool = false
var carried_piece: Node = null

# Hard mode: health at level entry (-1 = use full health for first level)
var persisted_health: float = -1.0

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
	is_carrying_piece = false
	carried_piece = null
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func load_victory_screen():
	current_score = 0
	is_carrying_piece = false
	carried_piece = null
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menus/victory_screen.tscn")

func reset_game():
	current_score = 0
	total_score = 0
	persisted_health = -1.0
	is_carrying_piece = false
	carried_piece = null
	has_shown_tech_tutorial = false
	first_trash_cluster_spawned = false
	LevelManager.reset_run()
	AlienTechManager.reset_run()

func spawn_floating_score(at_position: Vector2, amount: int) -> void:
	var level := get_tree().get_first_node_in_group("level")
	if not level:
		return
	var fs := _FloatingScore.new()
	level.add_child(fs)
	fs.global_position = at_position
	fs.setup(amount)
