# boss_intro_popup.gd
extends CanvasLayer
class_name BossIntroPopup

## Full-screen warning shown when a boss level starts, on top of the loaded
## level and after its transition cut scene has finished. Pauses the game
## until dismissed by any input, same convention as the level transition
## cutscene's "press any key to continue" prompt.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	LevelManager.boss_level_started.connect(_on_boss_level_started)

func _on_boss_level_started(_level_number: int) -> void:
	visible = true
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var is_dismiss_input: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if is_dismiss_input:
		get_viewport().set_input_as_handled()
		visible = false
		get_tree().paused = false
