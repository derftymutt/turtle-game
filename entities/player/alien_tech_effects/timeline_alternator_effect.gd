extends AlienTechEffect
class_name TimelineAlternatorEffect

## Timeline Alternator — hops the UFO Workshop to one of the other spots it was
## placed in this level (see UFOWorkshop.timeline_positions), and reseeds every
## SeaUrchinGroup's random layout. Both shake/fade via TimelineHop.
## Cold: the workshop hops to a random spot and the urchins reseed; after a
## fixed duration both go back to how they were.
## Hot: every press is a one-way hop — the workshop to the spot closest to the
## turtle, the urchins to a fresh random layout. No timer, no return trip, no
## cooldown (see AlienTechManager's _HOT_NO_BAR_TECHS).
## Urchins are left alone while Urchin Transmogrify has them as bumpers; a cold
## return that lands then waits for the transmogrify to end.
## No-op in levels with nothing to move.

var active: bool = false
var _timer: float = 0.0
var _home: Vector2 = Vector2.ZERO
var _home_set: bool = false
# SeaUrchinGroup -> its layout before a cold hop, to restore when it ends.
var _urchin_homes: Dictionary = {}
var _urchin_restore_pending: bool = false

func activate(player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.TIMELINE_ALTERNATOR)
	if active:
		return  # cold: the timer decides, presses are ignored
	var hopped := _hop_workshop(player, hot)
	var reseeded := _reseed_urchins(player, hot)
	if not (hopped or reseeded):
		return
	if not hot:
		active = true
		_timer = AlienTechManager.TIMELINE_ALTERNATOR_ACTIVE_DURATION
	player._flash(AlienTechRegistry.get_tech(AlienTechRegistry.TIMELINE_ALTERNATOR)["color"], 0.3)

func physics_process(player, delta: float) -> void:
	if _urchin_restore_pending:
		_restore_urchins(player)
	if not active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_stop(player)

## Swapped out mid-effect: send everything home, or it'd stay moved forever.
func on_slots_changed(player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.TIMELINE_ALTERNATOR):
		_stop(player)

## Returns false when there's no workshop or nowhere else for it to go.
func _hop_workshop(player, hot: bool) -> bool:
	var workshop := _find_workshop(player)
	if workshop == null:
		return false
	var alternates: Array[Vector2] = workshop.get_alternate_positions()
	if alternates.is_empty():
		return false
	var target: Vector2 = alternates.pick_random()
	if hot:
		var turtle_pos: Vector2 = player.global_position
		for pos in alternates:
			if pos.distance_to(turtle_pos) < target.distance_to(turtle_pos):
				target = pos
	else:
		_home = workshop.global_position
		_home_set = true
	workshop.hop_to(target)
	return true

## Returns false when no urchin layout changed. Skipped entirely while Urchin
## Transmogrify is active: its bumpers stand in for specific urchins, and
## swapping those urchins out from under it would strand the bumpers.
func _reseed_urchins(player, hot: bool) -> bool:
	if _transmogrify_active(player):
		return false
	var any := false
	for node in player.get_tree().get_nodes_in_group("sea_urchin_groups"):
		var group := node as SeaUrchinGroup
		if group == null:
			continue
		var before := group.get_layout()
		if group.reseed():
			any = true
			if not hot:
				_urchin_homes[group] = before
	return any

## Fades every group reseeded by the last cold hop back to its old layout —
## or, while Urchin Transmogrify is active, keeps it pending until it isn't.
func _restore_urchins(player) -> void:
	if _transmogrify_active(player):
		_urchin_restore_pending = not _urchin_homes.is_empty()
		return
	for group in _urchin_homes:
		if is_instance_valid(group):
			(group as SeaUrchinGroup).restore_layout(_urchin_homes[group])
	_urchin_homes.clear()
	_urchin_restore_pending = false

func _transmogrify_active(player) -> bool:
	return player._tech_effects[AlienTechRegistry.URCHIN_TRANSMOGRIFY].active

func _stop(player) -> void:
	active = false
	_timer = 0.0
	if _home_set:
		_home_set = false
		var workshop := _find_workshop(player)
		if workshop:
			workshop.hop_to(_home)
	_restore_urchins(player)

func _find_workshop(player) -> UFOWorkshop:
	for node in player.get_tree().get_nodes_in_group("workshop"):
		if node is UFOWorkshop and is_instance_valid(node) and not node.is_queued_for_deletion():
			return node
	return null
