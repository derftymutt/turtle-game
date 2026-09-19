extends AlienTechEffect
class_name FlipperAutomatonEffect

## Flipper Automaton — every flipper in the level fires on its own, cycling
## faster than a finger can, for as long as the effect is active. The cycling
## and the "enemies touching a flipper take damage" part both live in
## FlipperBase (set_automaton()); this class only owns the on/off timing and
## tells the flippers when to start and stop.
## Hot: manual on/off toggle, no timer, no cooldown (see AlienTechManager's
## effective-cooldown handling). Cold: active for a fixed duration.

var active: bool = false
var _timer: float = 0.0

func activate(player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.FLIPPER_AUTOMATON)
	if active:
		# Hot: click on, click off. Cold: the timer decides, presses are ignored.
		if hot:
			_stop(player)
		return
	active = true
	_timer = AlienTechManager.FLIPPER_AUTOMATON_ACTIVE_DURATION
	_set_flippers(player, true)
	if hot:
		AlienTechManager.set_passive_bar(AlienTechRegistry.FLIPPER_AUTOMATON, 1.0)
	player._flash(AlienTechRegistry.get_tech(AlienTechRegistry.FLIPPER_AUTOMATON)["color"], 0.3)

func physics_process(player, delta: float) -> void:
	if not active or AlienTechManager.is_tech_hot(AlienTechRegistry.FLIPPER_AUTOMATON):
		return
	_timer -= delta
	if _timer <= 0.0:
		_stop(player)

## Swapped out mid-effect: hand the flippers back, or they'd keep firing forever.
func on_slots_changed(player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.FLIPPER_AUTOMATON):
		_stop(player)

func _stop(player) -> void:
	active = false
	_timer = 0.0
	_set_flippers(player, false)
	# Erase rather than zero the override — see HydroFunnelEffect.activate().
	AlienTechManager.clear_passive_bar(AlienTechRegistry.FLIPPER_AUTOMATON)

func _set_flippers(player, on: bool) -> void:
	var flippers: Array[Node] = player.get_tree().get_nodes_in_group("flippers")
	for flipper in flippers:
		if flipper is FlipperBase:
			(flipper as FlipperBase).set_automaton(on)
