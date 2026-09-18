extends AlienTechEffect
class_name StimShotEffect

## Stim Shot — speeds up the turtle's own clock, not its strength: shoot/
## thrust cooldowns recover faster, the sprite animates faster, and ocean
## drag/buoyancy are rescaled to match, all without changing thrust_strength
## or bullet_speed. scale_factor/energy_recovery_scale/active are read
## directly by TurtlePlayer in _physics_process() (thrust_timer/shoot_timer
## decay, AnimatedSprite2D.speed_scale, energy recovery) and
## apply_ocean_effects() (drag/buoyancy), the same way other effects expose
## plain public state.
##
## Ocean drag is applied as a flat per-tick multiply (linear_velocity *=
## drag) rather than being delta-scaled like everything else here — it has no
## idea the turtle is on a faster clock. Raising it to scale_factor's power
## keeps the *relative* decay-per-turtle-second the same as at 1x; without
## that the extra thrusts a faster clock allows would just pile up as extra
## "slippery" momentum instead of reading as one smoothly faster turtle.
## Buoyancy is scaled by the same factor for the same reason — an ambient
## force integrated by the engine's own fixed tick, not by our local clock.
##
## Energy recovery gets its own, more generous multiplier rather than just
## matching scale_factor 1:1. A 1:1 match only keeps the drain:recovery
## *ratio* the same as normal play — but that ratio is already tuned tight
## by design (you're meant to touch a wall to sustain it), and Stim Shot's
## whole point is nonstop fast movement away from walls, so 1:1 still reads
## as "runs out too fast." ENERGY_RECOVERY_BOOST pushes recovery further
## ahead of drain so the tech is actually sustainable at speed.
##
## Balancing cost: air drains at AIR_DRAIN_MULT while active — a tech this
## strong (faster reflexes AND cheap movement) needs a real downside, and a
## harder air clock (versus, say, a flat energy tax) keeps pressure on the
## player to actually surface rather than just camping near a wall.

const COLD_SCALE: float = 1.6
const HOT_SCALE: float = 2.0
const ENERGY_RECOVERY_BOOST: float = 1.7  # on top of scale_factor, not instead of it
const AIR_DRAIN_MULT: float = 4.0  # flat, same whether hot or cold

var active: bool = false
var scale_factor: float = 1.0
var energy_recovery_scale: float = 1.0
var air_drain_scale: float = 1.0
var _timer: float = 0.0
var _duration: float = 0.0

func activate(player, _slot_index: int) -> void:
	active = true
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.STIM_SHOT)
	scale_factor = HOT_SCALE if hot else COLD_SCALE
	energy_recovery_scale = scale_factor * ENERGY_RECOVERY_BOOST
	air_drain_scale = AIR_DRAIN_MULT
	_duration = AlienTechManager.STIM_SHOT_ACTIVE_DURATION * (2.0 if hot else 1.0)
	_timer = _duration
	AlienTechManager.set_passive_bar(AlienTechRegistry.STIM_SHOT, 1.0)
	player._flash(Color(1.0, 0.85, 0.3), 0.3)

func physics_process(_player, delta: float) -> void:
	if not active:
		return
	_timer -= delta
	AlienTechManager.set_passive_bar(AlienTechRegistry.STIM_SHOT, max(0.0, _timer / _duration))
	if _timer <= 0.0:
		_deactivate()

## Stim Shot's timed window has no idea the tech was unequipped mid-effect —
## stop it here so a swapped-out slot doesn't keep the turtle sped up.
func on_slots_changed(_player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.STIM_SHOT):
		_deactivate()

func _deactivate() -> void:
	active = false
	scale_factor = 1.0
	energy_recovery_scale = 1.0
	air_drain_scale = 1.0
	AlienTechManager.clear_passive_bar(AlienTechRegistry.STIM_SHOT)
