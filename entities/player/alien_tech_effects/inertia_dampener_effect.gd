extends AlienTechEffect
class_name InertiaDampenerEffect

## Inertia Dampener — lets the turtle swim freely in air (treated as shallow
## ocean) and clamps underwater buoyancy to the shallow zone. Read directly
## by TurtlePlayer.apply_ocean_effects() and apply_thrust() as a plain flag,
## since both hot and cold share the same on/off semantics here (unlike
## techs where hot means "always on" regardless of this flag).
## Hot: manual on/off toggle, no timer, no cooldown gating a fresh press.
## Cold: active for a fixed duration per activation.

var active: bool = false
var _timer: float = 0.0

func activate(_player, _slot_index: int) -> void:
	if AlienTechManager.is_tech_hot(AlienTechRegistry.INERTIA_DAMPENER):
		# Hot: click on, click off — no timer, no cooldown (see _get_effective_cooldown).
		active = not active
		if active:
			AlienTechManager.set_passive_bar(AlienTechRegistry.INERTIA_DAMPENER, 1.0)
		else:
			# Erase the override entirely rather than setting it to 0.0 — a
			# present-but-zero entry still reads as get_bar_phase()'s
			# "active" (see _passive_bar_ratios.has(tech_id) there), which
			# kept the label blinking forever after the first toggle-on.
			# Clearing it falls through to the hot "ready" branch instead.
			AlienTechManager.clear_passive_bar(AlienTechRegistry.INERTIA_DAMPENER)
		return
	active = true
	_timer = AlienTechManager.INERTIA_DAMPENER_ACTIVE_DURATION

func physics_process(_player, delta: float) -> void:
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.INERTIA_DAMPENER):
		_timer -= delta
		if _timer <= 0.0:
			active = false
