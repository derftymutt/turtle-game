extends AlienTechEffect
class_name DermalRegenEffect

## Dermal Regenerator — heals hearts, once per level. Hot: instant full
## heal, no channel to interrupt. Cold: hold the slot button for
## CHANNEL_DURATION seconds to heal HEARTS; releasing early or taking
## damage cancels the channel (see cancel_on_damage()). `active` is read
## directly by TurtlePlayer for its sprite-modulate priority chain.

const HEARTS: int = 2
const CHANNEL_DURATION: float = 1.0

var active: bool = false
var _timer: float = 0.0
var _slot: int = -1
var _used: bool = false   # true after one successful heal per level

func activate(player, slot_index: int) -> void:
	if _used:
		return
	if AlienTechManager.is_tech_hot(AlienTechRegistry.DERMAL_REGEN):
		# Hot: instant, full heal — no channel, so nothing to interrupt.
		player.restore_hearts(player.MAX_HEARTS)
		_used = true
		AlienTechManager.set_passive_bar(AlienTechRegistry.DERMAL_REGEN, 0.0)
		return
	active = true
	_timer = 0.0
	_slot = slot_index

func physics_process(player, delta: float) -> void:
	if not active:
		return
	var action := "tech_slot_left" if _slot == 0 else "tech_slot_right"
	if not Input.is_action_pressed(action):
		_cancel()
		return
	_timer += delta
	AlienTechManager.set_passive_bar(AlienTechRegistry.DERMAL_REGEN, _timer / CHANNEL_DURATION)
	if _timer >= CHANNEL_DURATION:
		_complete(player)

func _complete(player) -> void:
	player.restore_hearts(HEARTS)
	_used = true
	# Leave passive bar at 0.0 (spent) so HUD shows bar-empty + dimmed label
	# until the player re-spawns or the level resets.
	AlienTechManager.set_passive_bar(AlienTechRegistry.DERMAL_REGEN, 0.0)
	active = false
	_timer = 0.0
	_slot = -1

func _cancel() -> void:
	AlienTechManager.clear_passive_bar(AlienTechRegistry.DERMAL_REGEN)
	active = false
	_timer = 0.0
	_slot = -1

func cancel_on_damage(_player) -> void:
	if active:
		_cancel()

## 0..1 channel progress, for TurtlePlayer's sprite-modulate pulse speed.
func progress() -> float:
	return _timer / CHANNEL_DURATION
