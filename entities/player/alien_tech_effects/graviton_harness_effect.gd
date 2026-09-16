extends AlienTechEffect
class_name GravitonHarnessEffect

## Graviton Harness — nullifies a carried UFO piece's weight while active.
## Hot: always weightless (no timer, no cooldown gating a press — see
## is_weightless()). Cold: weightless for a fixed duration per activation.

var active: bool = false
var _timer: float = 0.0

func activate(_player, _slot_index: int) -> void:
	active = true
	_timer = AlienTechManager.GRAVITON_HARNESS_ACTIVE_DURATION

func physics_process(_player, delta: float) -> void:
	# Hot is always weightless via is_weightless() regardless of this timer,
	# so a press while hot (no cooldown gating it) is a harmless no-op.
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.GRAVITON_HARNESS):
		_timer -= delta
		if _timer <= 0.0:
			active = false

## True whenever a carried UFO piece's weight should be ignored: the cold
## timed activation is running, or the tech is hot (always active).
func is_weightless(_player) -> bool:
	return active or AlienTechManager.is_tech_hot(AlienTechRegistry.GRAVITON_HARNESS)
