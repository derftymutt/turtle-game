extends AlienTechEffect
class_name DermalRegenEffect

## Dermal Regenerator — heals hearts. Tap the slot button to start a
## CHANNEL_DURATION-second channel that heals HEARTS (hot: a full heal
## instead). The turtle is shocked for the whole channel (no moving,
## shooting or other tech, via the same suspend_control() stun the electric
## eel uses) and drops any UFO part it is carrying. Real damage cancels the
## channel and the heal never happens (see cancel_on_damage()). The 30s
## cooldown only starts when the heal lands: it is a held cooldown (see
## AlienTechManager._HOLD_COOLDOWN_TECHS), released on completion and zeroed
## on a cancel. `active` is read directly by TurtlePlayer for its
## sprite-modulate priority chain.

const HEARTS: int = 2
const CHANNEL_DURATION: float = 1.0
# The stun outlasts the channel slightly so a physics-frame of drift can't
# hand control back before _complete()/_cancel() releases it explicitly.
const STUN_PADDING: float = 0.1

var active: bool = false
var _timer: float = 0.0
var _hot: bool = false    # latched at activation so heat changing mid-channel can't alter the heal

func activate(player, _slot_index: int) -> void:
	# Nothing to heal: refuse. try_activate_slot() already seeded the held
	# cooldown on press, so zero it — a refused press must cost nothing.
	if player.current_hearts >= player.MAX_HEARTS:
		AlienTechManager.release_cooldown_hold(AlienTechRegistry.DERMAL_REGEN, 0.0)
		return
	active = true
	_hot = AlienTechManager.is_tech_hot(AlienTechRegistry.DERMAL_REGEN)
	_timer = 0.0
	_drop_carried_pieces(player)
	player.suspend_control(CHANNEL_DURATION + STUN_PADDING)

func physics_process(player, delta: float) -> void:
	if not active:
		return
	_timer += delta
	AlienTechManager.set_passive_bar(AlienTechRegistry.DERMAL_REGEN, _timer / CHANNEL_DURATION)
	if _timer >= CHANNEL_DURATION:
		_complete(player)

func _complete(player) -> void:
	player.restore_hearts(player.MAX_HEARTS if _hot else HEARTS)
	# Drop the channel-progress override so the HUD bar reads the cooldown that
	# starts draining now.
	AlienTechManager.clear_passive_bar(AlienTechRegistry.DERMAL_REGEN)
	AlienTechManager.release_cooldown_hold(AlienTechRegistry.DERMAL_REGEN)
	_end_channel(player)

func _cancel(player) -> void:
	AlienTechManager.clear_passive_bar(AlienTechRegistry.DERMAL_REGEN)
	# Failed heal: no cooldown, the slot is usable again immediately.
	AlienTechManager.release_cooldown_hold(AlienTechRegistry.DERMAL_REGEN, 0.0)
	_end_channel(player)

func _end_channel(player) -> void:
	active = false
	_timer = 0.0
	player.end_control_suspension()

func cancel_on_damage(player) -> void:
	if active:
		_cancel(player)

## Intentional drop (long pickup grace) — the stun is shorter than the grace,
## so the part can't be snatched straight back while the turtle is helpless.
func _drop_carried_pieces(player) -> void:
	if not GameManager.is_carrying_piece:
		return
	for piece in GameManager.carried_pieces.duplicate():
		if is_instance_valid(piece):
			piece.drop_piece(true)
	player.get_node("SfxUfoDrop").play()

## 0..1 channel progress, for TurtlePlayer's sprite-modulate pulse speed.
func progress() -> float:
	return _timer / CHANNEL_DURATION
