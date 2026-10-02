extends Node2D
class_name RainbowBonusLevel

## The bonus rainbow level: inside the rainbow, seven screens tall, red at the
## top to violet at the bottom. Reached by riding a rainbow current into the
## glowing apex after the Rainbow Fish minigame (RainbowBonusManager swaps it
## in and back out).
##
## The turtle starts at the bottom of the launch current running up the right
## edge (walled off from the play area) and is shot out into red at the top.
## Every lost "ball" drops it a colour; falling out the bottom of violet — or
## dying — ends the level.
##
## Sky physics everywhere: the scene's Ocean sits far below violet, so the
## turtle is always "in the air" (TurtlePlayer's normal sky gravity and drag).
##
## Coordinates: x = -320..320, y = 0 (top of red) .. 7 × 360 (bottom of violet).

const SCREEN_SIZE := Vector2(640, 360)
const SCREEN_COUNT := 7

## How far below violet the turtle falls before the level ends
@export var fall_out_margin: float = 40.0

var _ended: bool = false

func _ready() -> void:
	add_to_group("level")
	get_tree().paused = false

func level_height() -> float:
	return SCREEN_SIZE.y * SCREEN_COUNT

func _physics_process(_delta: float) -> void:
	if _ended:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and player.global_position.y > level_height() + fall_out_margin:
		_end()

## TurtlePlayer calls this when it dies — the bonus level just ends.
func on_player_died(_final_score: int, _death_cause: String = "") -> void:
	_end()

func _end() -> void:
	if _ended:
		return
	_ended = true
	if RainbowBonusManager.active:
		RainbowBonusManager.finish()
	else:
		# Run on its own from the editor (F6) — just go again
		print("🌈 Bonus rainbow level over (run standalone — restarting)")
		get_tree().reload_current_scene.call_deferred()
