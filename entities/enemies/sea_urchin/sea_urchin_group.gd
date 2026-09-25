# sea_urchin_group.gd
extends Node2D
class_name SeaUrchinGroup

## Container for a level's seeded sea urchins.
## Place every candidate urchin as a child of this node. On load, `active_count`
## of them are kept (chosen at random) and the rest are benched, so each
## run of the level gets a different urchin layout. Works like the UFO Workshop
## election, but keeps a subset instead of exactly one.
## Benched urchins stay in the tree (hidden and out of play, see
## SeaUrchin.set_benched()) so Timeline Alternator can reseed() the layout.

## How many urchins stay active this load. -1 (or any value >= the number of
## children) keeps them all.
@export var active_count: int = -1

## A reseed rolls until the new layout differs from the old one; this caps the
## rolls so a group whose layouts are nearly all the same can't spin forever.
const _MAX_RESEED_ROLLS: int = 8

var _active: Array[SeaUrchin] = []
var _reseed_tween: Tween

func _ready() -> void:
	add_to_group("sea_urchin_groups")
	# Children are already ready by the time the parent's _ready() runs.
	var urchins := _candidates()
	if active_count < 0 or active_count >= urchins.size():
		_active = urchins
		return

	urchins.shuffle()
	_active = urchins.slice(0, active_count)
	# Stand the rest down immediately so they can't be seen, collide, or show
	# up in group lookups ("enemies", "sea_urchins").
	for urchin in urchins.slice(active_count):
		urchin.set_benched(true)

	var kept: PackedStringArray = []
	for urchin in _active:
		kept.append(urchin.name)
	print("🦔 Sea Urchins: %d candidates, kept %s" % [urchins.size(), ", ".join(kept)])

## Timeline Alternator: pick a fresh random layout of the same size. Urchins
## leaving it shake and fade out, then the arrivals shake and fade in (see
## TimelineHop). Urchins in both layouts don't move. Returns false (and does
## nothing) when every candidate is always active.
func reseed() -> bool:
	var urchins := _candidates()
	if active_count < 0 or active_count >= urchins.size():
		return false
	var new_active: Array[SeaUrchin] = []
	for _roll in _MAX_RESEED_ROLLS:
		urchins.shuffle()
		new_active = urchins.slice(0, active_count)
		if new_active.any(func(u: SeaUrchin) -> bool: return u not in _active):
			break
	return _transition_to(new_active)

## The current layout, for handing back to restore_layout() later.
func get_layout() -> Array[SeaUrchin]:
	return _active.duplicate()

## Timeline Alternator's cold hop ending: fade back to a layout saved with
## get_layout(), the same way reseed() fades to a new one.
func restore_layout(layout: Array[SeaUrchin]) -> void:
	var valid: Array[SeaUrchin] = []
	for urchin in layout:
		if is_instance_valid(urchin) and urchin.get_parent() == self:
			valid.append(urchin)
	_transition_to(valid)

## Fades from the current layout to `new_active`. Returns false if nothing
## actually changes.
func _transition_to(new_active: Array[SeaUrchin]) -> bool:
	# Finish any transition still mid-fade before starting another.
	if _reseed_tween and _reseed_tween.is_valid():
		_reseed_tween.kill()
	_settle()

	var old_active := _active
	var leaving := old_active.filter(func(u: SeaUrchin) -> bool: return u not in new_active)
	var arriving := new_active.filter(func(u: SeaUrchin) -> bool: return u not in old_active)
	_active = new_active
	if leaving.is_empty() and arriving.is_empty():
		return false

	_reseed_tween = create_tween().set_parallel(true)
	# Leaving: out of play from the first frame, but still drawn for the fade.
	# A mutated urchin stays hidden throughout — its bumper is what's on
	# screen, and UrchinMutationEffect.on_urchins_reseeded() hops that instead.
	for urchin in leaving:
		urchin.set_benched(true)
		urchin.visible = not urchin.is_mutated()
		TimelineHop.shake_fade(_reseed_tween, urchin, urchin.sprite, false)
	_reseed_tween.chain().tween_callback(func() -> void:
		for urchin in arriving:
			if is_instance_valid(urchin) and not urchin.is_mutated():
				urchin.visible = true)
	# Arriving: drawn while fading in, but only harmful once fully there.
	for urchin in arriving:
		TimelineHop.shake_fade(_reseed_tween, urchin, urchin.sprite, true)
	_reseed_tween.chain().tween_callback(_settle)
	return true

## Snap every urchin to its final state for the current layout — used when a
## reseed finishes, and to cut one short when another starts mid-fade.
func _settle() -> void:
	for urchin in _candidates():
		urchin.set_benched(urchin not in _active)
		urchin.modulate.a = 1.0
		if urchin.sprite:
			urchin.sprite.position.x = 0.0

func _candidates() -> Array[SeaUrchin]:
	var result: Array[SeaUrchin] = []
	for child in get_children():
		if child is SeaUrchin and not child.is_queued_for_deletion():
			result.append(child)
	return result
