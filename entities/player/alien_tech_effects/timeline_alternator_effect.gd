extends AlienTechEffect
class_name TimelineAlternatorEffect

## Timeline Alternator — hops the UFO Workshop to one of the other spots it was
## placed in this level (see UFOWorkshop.timeline_positions). The shake/fade
## itself lives in UFOWorkshop.hop_to().
## Cold: hops to a random spot, active for a fixed duration, then hops home.
## Hot: every press is a one-way hop to the spot closest to the turtle — no
## timer, no return trip, no cooldown (see AlienTechManager's _HOT_NO_BAR_TECHS).
## No-op in levels with no workshop or only one workshop spot.

var active: bool = false
var _timer: float = 0.0
var _home: Vector2 = Vector2.ZERO

func activate(player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.TIMELINE_ALTERNATOR)
	if active:
		return  # cold: the timer decides, presses are ignored
	var workshop := _find_workshop(player)
	if workshop == null:
		return
	var alternates: Array[Vector2] = workshop.get_alternate_positions()
	if alternates.is_empty():
		return
	var target: Vector2 = alternates.pick_random()
	if hot:
		var turtle_pos: Vector2 = player.global_position
		for pos in alternates:
			if pos.distance_to(turtle_pos) < target.distance_to(turtle_pos):
				target = pos
	if not hot:
		_home = workshop.global_position
		active = true
		_timer = AlienTechManager.TIMELINE_ALTERNATOR_ACTIVE_DURATION
	workshop.hop_to(target)
	player._flash(AlienTechRegistry.get_tech(AlienTechRegistry.TIMELINE_ALTERNATOR)["color"], 0.3)

func physics_process(player, delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_stop(player)

## Swapped out mid-effect: send the workshop home, or it'd stay moved forever.
func on_slots_changed(player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.TIMELINE_ALTERNATOR):
		_stop(player)

func _stop(player) -> void:
	active = false
	_timer = 0.0
	var workshop := _find_workshop(player)
	if workshop:
		workshop.hop_to(_home)

func _find_workshop(player) -> UFOWorkshop:
	for node in player.get_tree().get_nodes_in_group("workshop"):
		if node is UFOWorkshop and is_instance_valid(node) and not node.is_queued_for_deletion():
			return node
	return null
