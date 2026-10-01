extends AlienTechEffect
class_name CosmicMeditationEffect

## Cosmic Meditation — tap the slot button to suspend the turtle in place,
## wherever it is (ocean physics off, velocity held at zero), and recharge
## energy at the fast wall/surface rate. Refused at full energy.
##
## Cold: no shooting while meditating; it ends by itself once energy is full.
## Hot: shooting allowed, and it never ends on its own — once energy is full
## the turtle stays suspended until the player swims (any direction), which
## breaks it and thrusts normally that same frame. Concentration can't be
## broken before full energy, hot or cold: swim input is swallowed until then.
##
## Either way real damage ends it immediately (cancel_on_damage()) and costs
## HEARTS_LOST_ON_HIT hearts instead of one (applied in
## TurtlePlayer.take_damage()), and the 4s cooldown runs from the end: it's a held cooldown (see
## AlienTechManager._HOLD_COOLDOWN_TECHS) released by _end(). `active` is read
## directly by TurtlePlayer (sprite modulate, ocean-physics suppression, fast
## recharge, shooting block).

const MOVE_DEADZONE: float = 0.1
const HEARTS_LOST_ON_HIT: int = 2

var active: bool = false
var _hot: bool = false    # latched at activation so heat changing mid-meditation can't alter it

func activate(player, _slot_index: int) -> void:
	var hud = player.hud
	# Nothing to recharge: refuse. try_activate_slot() already seeded the held
	# cooldown on press, so zero it — a refused press must cost nothing.
	if hud == null or not hud.energy_enabled or hud.current_energy >= hud.max_energy:
		AlienTechManager.release_cooldown_hold(AlienTechRegistry.COSMIC_MEDITATION, 0.0)
		return
	active = true
	_hot = AlienTechManager.is_tech_hot(AlienTechRegistry.COSMIC_MEDITATION)
	_hold(player)
	player._flash(Color(0.75, 0.5, 1.0), 0.3)

func physics_process(player, _delta: float) -> void:
	if not active:
		return
	_hold(player)
	var hud = player.hud
	if hud == null:
		_end(player)
		return
	AlienTechManager.set_passive_bar(AlienTechRegistry.COSMIC_MEDITATION, hud.current_energy / hud.max_energy)
	if not _hot and hud.current_energy >= hud.max_energy:
		_end(player)

## Called by TurtlePlayer with the frame's movement input, before it thrusts.
## Returns true while meditation should swallow the input (no swimming).
## Hot, at full energy: swim input breaks meditation and is let through.
## (Activation is refused at full energy, so a direction held through the
## press can never break it instantly.)
func blocks_movement(player, movement_input: Vector2) -> bool:
	if not active:
		return false
	var hud = player.hud
	var full: bool = hud != null and hud.current_energy >= hud.max_energy
	if _hot and full and movement_input.length() > MOVE_DEADZONE:
		_end(player)
		return false
	return true

## True while meditation forbids spitting (cold only).
func blocks_shooting() -> bool:
	return active and not _hot

func cancel_on_damage(player) -> void:
	if active:
		_end(player)

func on_slots_changed(player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.COSMIC_MEDITATION):
		_end(player)

func _hold(player) -> void:
	player.linear_velocity = Vector2.ZERO
	player.angular_velocity = 0.0

func _end(_player) -> void:
	active = false
	# Drop the energy-fill override so the HUD bar reads the cooldown that
	# starts draining now.
	AlienTechManager.clear_passive_bar(AlienTechRegistry.COSMIC_MEDITATION)
	AlienTechManager.release_cooldown_hold(AlienTechRegistry.COSMIC_MEDITATION)
