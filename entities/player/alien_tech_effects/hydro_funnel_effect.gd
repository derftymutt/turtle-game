extends AlienTechEffect
class_name HydroFunnelEffect

## Hydro Funnel — opens hidden OceanCurrent nodes (group "hydro_funnel_currents").
## Hot: manual on/off toggle, no timer, no cooldown gating a fresh press (see
## AlienTechManager's effective-cooldown handling). Cold: active for a fixed
## duration per activation.

var active: bool = false
var _timer: float = 0.0

func activate(_player, _slot_index: int) -> void:
	if AlienTechManager.is_tech_hot(AlienTechRegistry.HYDRO_FUNNEL):
		# Hot: click on, click off — no timer, no cooldown (see _effective_cooldown_max).
		active = not active
		if active:
			AlienTechManager.set_passive_bar(AlienTechRegistry.HYDRO_FUNNEL, 1.0)
		else:
			# Erase rather than zero the override — see the matching note in
			# TurtlePlayer._activate_inertia_dampener() for why that distinction matters.
			AlienTechManager.clear_passive_bar(AlienTechRegistry.HYDRO_FUNNEL)
		return
	active = true
	_timer = AlienTechManager.HYDRO_FUNNEL_ACTIVE_DURATION

func physics_process(player, delta: float) -> void:
	if active and not AlienTechManager.is_tech_hot(AlienTechRegistry.HYDRO_FUNNEL):
		_timer -= delta
		if _timer <= 0.0:
			active = false
	if AlienTechManager.has_tech(AlienTechRegistry.HYDRO_FUNNEL):
		_update_currents(player, active)

## Turns every OceanCurrent in the "hydro_funnel_currents" group on or off to
## match. Each current independently decides whether it's actually allowed to
## turn on right now (e.g. a hydro_funnel_hot_only one refuses unless Hydro
## Funnel is HOT) — see OceanCurrent.turn_on()/turn_off() — so this just
## mirrors the tech's own on/off state uniformly across the whole group.
func _update_currents(player, should_be_active: bool) -> void:
	for current in player.get_tree().get_nodes_in_group("hydro_funnel_currents"):
		if not is_instance_valid(current):
			continue
		if should_be_active:
			current.turn_on()
		else:
			current.turn_off()
