extends AlienTechEffect
class_name IonExciterEffect

## Ion Exciter — doubles the launch speed the turtle gets from flippers and
## circular bumpers while active. Read directly by FlipperBase.hit_body() and
## CircularBumper._apply_bumper_force()/apply_launch_force() via
## TurtlePlayer.is_ion_exciter_active(), the same way Bumper Magnet's
## is_magnet_attached_to() is read.
## Hot: manual on/off toggle, no timer, no cooldown gating a fresh press (see
## AlienTechManager's effective-cooldown handling). Cold: active for a fixed
## duration per activation.

var active: bool = false
var _timer: float = 0.0

func activate(_player, _slot_index: int) -> void:
	if AlienTechManager.is_tech_hot(AlienTechRegistry.ION_EXCITER):
		# Hot: click on, click off — no timer, no cooldown (see _effective_cooldown_max).
		active = not active
		if active:
			AlienTechManager.set_passive_bar(AlienTechRegistry.ION_EXCITER, 1.0)
		else:
			# Erase rather than zero the override — see the matching note in
			# HydroFunnelEffect.activate() for why that distinction matters.
			AlienTechManager.clear_passive_bar(AlienTechRegistry.ION_EXCITER)
		return
	active = true
	_timer = AlienTechManager.ION_EXCITER_ACTIVE_DURATION

func physics_process(_player, delta: float) -> void:
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.ION_EXCITER):
		_timer -= delta
		if _timer <= 0.0:
			active = false

## Ion Exciter's timed cold window has no idea the tech was unequipped mid-effect
## — stop it here so a swapped-out slot doesn't keep doubling launch speed.
func on_slots_changed(_player) -> void:
	if not AlienTechManager.has_tech(AlienTechRegistry.ION_EXCITER):
		active = false
		_timer = 0.0
