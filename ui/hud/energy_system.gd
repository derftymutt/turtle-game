extends RefCounted
class_name EnergySystem

## Energy system behavior (experimental, toggleable) — thrust cost, wall-
## bonus recovery, the low-health "desperation" recovery multiplier, and the
## wall-recovery pulse / blink visual feedback.
##
## Stateless w.r.t. HUD: every method takes `hud` as a parameter and reads/
## writes its energy_enabled, current_energy, max_energy, wall_recovery_active,
## level_completing fields directly (mirroring the AlienTechEffect convention
## in entities/player/alien_tech_effects/), since those fields are read and
## written directly by several external files (air_bubble.gd, bullet.gd,
## laser_bullet.gd, turtle_player.gd, shockwave_effect.gd,
## tutorial_director.gd) and have to keep living on HUD itself. This class
## only owns the pulse/blink timing state below, which nothing outside
## hud.gd touches. Also reads hud._hearts (HeartsDisplay) for the
## desperation multiplier's health ratio.

var pulse_timer: float = 0.0
var pulse_speed: float = 8.0

const BLINK_PERIOD_MSEC: int = 200
const BLINK_LOW_ALPHA: float = 0.25
var blinking: bool = false

## Update energy display.
func update(hud, energy: float, max_en: float) -> void:
	if not hud.energy_enabled:
		return

	hud.current_energy = energy
	hud.max_energy = max_en

	if not hud.energy_bar:
		return
	hud.energy_bar.max_value = max_en
	hud.energy_bar.value = energy

	# Only update color if NOT actively recovering from wall (wall recovery
	# has its own pulsing color in process()).
	if not hud.wall_recovery_active:
		if energy / max_en > 0.5:
			hud.energy_bar.modulate = Color.WHITE
		elif energy / max_en > 0.2:
			hud.energy_bar.modulate = Color.ORANGE
		else:
			hud.energy_bar.modulate = Color.RED

## Try to use energy for a thrust.
func try_thrust(hud) -> bool:
	if not hud.energy_enabled:
		return true
	if hud.current_energy >= hud.energy_threshold:
		hud.current_energy -= hud.energy_per_thrust
		update(hud, hud.current_energy, hud.max_energy)
		return true
	return false

## Recover energy over time.
func recover(hud, delta: float, touching_wall: bool = false) -> void:
	if not hud.energy_enabled:
		return

	# Track if we're getting wall bonus
	hud.wall_recovery_active = touching_wall

	var desperation_mult := 1.0
	if hud.desperation_enabled and hud._hearts.max_hearts > 0:
		var health_ratio: float = float(hud._hearts.current) / float(hud._hearts.max_hearts)
		if health_ratio < hud.desperation_threshold:
			var t: float = 1.0 - (health_ratio / hud.desperation_threshold)
			desperation_mult = lerp(1.0, hud.desperation_max_multiplier, t)

	var recovery: float = hud.energy_recovery_rate * desperation_mult * delta
	if touching_wall:
		recovery += hud.energy_wall_bonus * delta

	hud.current_energy = min(hud.max_energy, hud.current_energy + recovery)
	update(hud, hud.current_energy, hud.max_energy)

	# Sound: play while wall recovery is active, energy isn't full, and level isn't completing
	if hud.sfx_energy_charge:
		var should_play: bool = hud.wall_recovery_active and hud.current_energy < hud.max_energy and not hud.level_completing
		if should_play and not hud.sfx_energy_charge.playing:
			hud.sfx_energy_charge.play()
		elif not should_play and hud.sfx_energy_charge.playing:
			hud.sfx_energy_charge.stop()

## Called by UFOWorkshop on final piece delivery — silences any active sounds immediately.
func begin_level_completion(hud) -> void:
	hud.level_completing = true
	if hud.sfx_energy_charge and hud.sfx_energy_charge.playing:
		hud.sfx_energy_charge.stop()

## Check if player can thrust (has enough energy).
func can_thrust(hud) -> bool:
	if not hud.energy_enabled:
		return true
	return hud.current_energy >= hud.energy_threshold

## Blink the energy bar and its icon for the duration of an active energy powerup.
func set_blinking(hud, active: bool) -> void:
	blinking = active
	if not active:
		if hud.energy_bar:
			hud.energy_bar.modulate.a = 1.0
		if hud.energy_icon:
			hud.energy_icon.modulate.a = 1.0

## Drives the wall-recovery pulse and the blink overlay. Called every frame
## from HUD._process — the pulse block runs first (falling back to a normal
## update() when not recovering), then the blink overlay applies on top,
## same order as the original.
func process(hud, delta: float) -> void:
	if hud.wall_recovery_active and hud.energy_bar:
		pulse_timer += delta * pulse_speed
		var pulse: float = (sin(pulse_timer) + 1.0) / 2.0

		var base_color := Color.WHITE
		var energy_ratio: float = hud.current_energy / hud.max_energy
		if energy_ratio <= 0.2:
			base_color = Color.RED
		elif energy_ratio <= 0.5:
			base_color = Color.ORANGE

		var recovery_color := base_color.lerp(Color.GOLD, pulse * 0.7)
		hud.energy_bar.modulate = recovery_color
	else:
		pulse_timer = 0.0
		update(hud, hud.current_energy, hud.max_energy)

	if blinking and hud.energy_bar:
		var blink_on := int(Time.get_ticks_msec() / BLINK_PERIOD_MSEC) % 2 == 0
		var a := 1.0 if blink_on else BLINK_LOW_ALPHA
		hud.energy_bar.modulate.a = a
		if hud.energy_icon:
			hud.energy_icon.modulate.a = a
