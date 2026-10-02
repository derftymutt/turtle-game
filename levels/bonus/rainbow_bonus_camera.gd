extends Camera2D
class_name RainbowBonusCamera

## Follows the turtle up and down the bonus rainbow level, held to the
## level's width and height (one screen wide, so it never moves sideways).

func _ready() -> void:
	var level := get_parent() as RainbowBonusLevel
	var height: float = level.level_height() if level else RainbowBonusLevel.SCREEN_SIZE.y * RainbowBonusLevel.SCREEN_COUNT
	var half_w := RainbowBonusLevel.SCREEN_SIZE.x * 0.5
	limit_left = int(-half_w)
	limit_right = int(half_w)
	limit_top = 0
	limit_bottom = int(height)
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0
	_follow()
	reset_smoothing()
	make_current()

func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		global_position = Vector2(0.0, player.global_position.y)
