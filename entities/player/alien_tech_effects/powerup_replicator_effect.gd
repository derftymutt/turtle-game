extends AlienTechEffect
class_name PowerupReplicatorEffect

## Powerup Replicator — stores the next powerup collected instead of
## applying it, then replays it on a long-press of its slot button (a tap
## instead cycles which stored powerup type is "next" via
## AlienTechManager.cycle_replicator_selection()). Input handling for this
## tech's hold-vs-tap distinction lives entirely here (called from
## TurtlePlayer's input loop) since it doesn't fit the normal
## dispatch-on-press pattern every other tech uses.
##
## `using_replicator` is read directly by TurtlePlayer.apply_powerup() to
## guard against re-storing a powerup while the replicator is replaying one.

const LONG_PRESS: float = 0.5

var using_replicator: bool = false
var _held_slot: int = -1
var _press_timer: float = 0.0
var _long_pressed: bool = false

## Called from TurtlePlayer._on_alien_tech_activated() if the tech_activated
## signal ever fires for this tech (it doesn't under normal input — see
## handle_input() below — but this keeps the effect consistent with every
## other tech's dispatch entry point).
func activate(player, _slot_index: int) -> void:
	var stored := AlienTechManager.consume_replicated_powerup()
	if stored >= 0:
		using_replicator = true
		player.apply_powerup(stored)
		using_replicator = false

## Replicator: tap = cycle selection, long-press = activate selected.
## Called from TurtlePlayer's input loop instead of going through
## AlienTechManager.try_activate_slot(), since it needs to distinguish
## tap from hold rather than firing once on press.
func handle_input(player, slot_index: int, action: String, delta: float) -> void:
	if Input.is_action_just_pressed(action):
		_held_slot = slot_index
		_press_timer = 0.0
		_long_pressed = false
	if _held_slot != slot_index:
		return
	if Input.is_action_pressed(action):
		_press_timer += delta
		if not _long_pressed and _press_timer >= LONG_PRESS:
			_long_pressed = true
			activate(player, slot_index)
	if Input.is_action_just_released(action):
		if not _long_pressed:
			AlienTechManager.cycle_replicator_selection()
		_held_slot = -1

func on_slots_changed(_player) -> void:
	_held_slot = -1
	_long_pressed = false
