extends AlienTechEffect
class_name UrchinTransmogrifyEffect

## Urchin Transmogrify — swaps every sea urchin for a CircularBumper, then
## swaps them back. Each urchin picks its own bumper size via
## SeaUrchin.bumper_size. The bumpers are spawned on activation and freed on
## revert rather than pre-placed in the levels; the urchin itself is only
## stood down (see SeaUrchin.set_transmogrified()). While active the bumpers
## are ordinary members of the "bumpers" group, so Bumper Magnet and Ion
## Exciter treat them like any other.
## Hot: manual on/off toggle, no timer, no cooldown (see AlienTechManager's
## effective-cooldown handling). Cold: reverts on its own after a fixed
## duration, with the bumpers blinking slowly for the last stretch.
## Either way the bumpers blink rapidly right after the swap.

const _BUMPER_SCENE: PackedScene = preload("res://entities/environment/walls/circular_bumper/circular_bumper.tscn")
const _INTRO_BLINK_TIME: float = 0.6   # rapid "transforming" blink after the swap
const _INTRO_BLINK_RATE: float = 20.0
const _OUTRO_BLINK_TIME: float = 1.5   # slow blink before a cold revert
const _OUTRO_BLINK_RATE: float = 8.0
const _BLINK_DIM_ALPHA: float = 0.35

var active: bool = false
var _timer: float = 0.0
var _elapsed: float = 0.0
var _bumper_alpha: float = 1.0
# One {"urchin": SeaUrchin, "bumper": CircularBumper} per swapped urchin.
var _swaps: Array[Dictionary] = []

func activate(player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.URCHIN_TRANSMOGRIFY)
	if active:
		# Hot: click on, click off. Cold: the timer decides, presses are ignored.
		if hot:
			_revert()
		return
	_timer = AlienTechManager.URCHIN_TRANSMOGRIFY_ACTIVE_DURATION
	_elapsed = 0.0
	_swaps.clear()
	for node in player.get_tree().get_nodes_in_group("sea_urchins"):
		var urchin := node as SeaUrchin
		if urchin == null or urchin.is_queued_for_deletion():
			continue
		_swap_in(urchin)
	active = true
	_apply_bumper_alpha(_BLINK_DIM_ALPHA)  # first frame of the intro blink
	if hot:
		AlienTechManager.set_passive_bar(AlienTechRegistry.URCHIN_TRANSMOGRIFY, 1.0)
	player._flash(AlienTechRegistry.get_tech(AlienTechRegistry.URCHIN_TRANSMOGRIFY)["color"], 0.3)

func physics_process(_player, delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.URCHIN_TRANSMOGRIFY)
	if not hot:
		_timer -= delta
		if _timer <= 0.0:
			_revert()
			return

	var alpha: float = 1.0
	if _elapsed < _INTRO_BLINK_TIME:
		alpha = _blink_alpha(_elapsed, _INTRO_BLINK_RATE)
	elif not hot and _timer <= _OUTRO_BLINK_TIME:
		alpha = _blink_alpha(_timer, _OUTRO_BLINK_RATE)
	_apply_bumper_alpha(alpha)

## Swapped out mid-effect: put the urchins back, or they'd stay bumpers forever.
func on_slots_changed(_player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.URCHIN_TRANSMOGRIFY):
		_revert()

func _swap_in(urchin: SeaUrchin) -> void:
	var parent := urchin.get_parent()
	if parent == null:
		return
	var bumper := _BUMPER_SCENE.instantiate() as CircularBumper
	# Preset first: its setter picks the matching radius and sprite. The bumper
	# is a sibling, not a child, because it must never inherit the urchin's
	# rocking rotation (or its hidden state).
	bumper.size_preset = urchin.bumper_size as CircularBumper.SizePreset
	parent.add_child(bumper)
	bumper.global_position = urchin.global_position
	urchin.set_transmogrified(true)
	_swaps.append({"urchin": urchin, "bumper": bumper})

func _revert() -> void:
	for swap in _swaps:
		if is_instance_valid(swap["bumper"]):
			(swap["bumper"] as CircularBumper).queue_free()
		if is_instance_valid(swap["urchin"]):
			(swap["urchin"] as SeaUrchin).set_transmogrified(false)
	_swaps.clear()
	active = false
	_timer = 0.0
	_elapsed = 0.0
	_bumper_alpha = 1.0
	# Erase rather than zero the override — see HydroFunnelEffect.activate().
	AlienTechManager.clear_passive_bar(AlienTechRegistry.URCHIN_TRANSMOGRIFY)

## Full alpha on even half-cycles, dim on odd ones. `t` is any value moving
## through time (elapsed or remaining) — only its phase matters.
func _blink_alpha(t: float, rate: float) -> float:
	return 1.0 if int(t * rate) % 2 == 0 else _BLINK_DIM_ALPHA

## Only touches the bumpers when the value changes, so it doesn't fight
## anything else that fades them (e.g. Phase Shifter) on the frames in between.
func _apply_bumper_alpha(alpha: float) -> void:
	if is_equal_approx(alpha, _bumper_alpha):
		return
	_bumper_alpha = alpha
	for swap in _swaps:
		if is_instance_valid(swap["bumper"]):
			(swap["bumper"] as CircularBumper).modulate.a = alpha
