extends RefCounted
class_name AirSystem

## Air / oxygen system behavior (experimental, toggleable) — drains
## underwater, refills at the surface, pulses the whole HUD layer red in a
## warning state, and flashes the air bar once for the air-reserve powerup
## pickup.
##
## Stateless w.r.t. HUD: every method takes `hud` as a parameter and reads/
## writes its air_enabled, max_air, current_air, air_warning, air_bar,
## sfx_low_air fields directly (mirroring the AlienTechEffect convention in
## entities/player/alien_tech_effects/) rather than owning its own copy of
## that state — air_bubble.gd and turtle_player.gd read and write
## hud.max_air / hud.current_air directly, so those fields have to keep
## living on HUD itself. This class only owns the flash/pulse timing state
## below, which nothing outside hud.gd touches.

var hud_layer_flash_speed: float = 5.0
var _pulse_timer: float = 0.0

const FLASH_PERIOD: float = 0.15
const FLASH_COLOR := Color(1.0, 1.0, 0.4, 1.0)
var _flash_remaining: float = 0.0
var _flash_timer: float = 0.0

## Update air display.
func update(hud, air: float, max_a: float) -> void:
	if not hud.air_enabled:
		return

	hud.current_air = air
	hud.max_air = max_a

	if not hud.air_bar:
		return
	hud.air_bar.max_value = max_a
	hud.air_bar.value = air

	# Warning state
	if air <= hud.air_warning_threshold:
		if not hud.air_warning:
			hud.air_warning = true
			_pulse_timer = 0.0
			if hud.sfx_low_air:
				hud.sfx_low_air.play()
			hud.low_air_warning_changed.emit(true)
	else:
		var was_warning: bool = hud.air_warning
		hud.air_warning = false
		if hud.sfx_low_air and hud.sfx_low_air.playing:
			hud.sfx_low_air.stop()
		hud.air_bar.modulate = Color.CYAN
		if was_warning:
			hud.low_air_warning_changed.emit(false)

## Drain air while underwater. Returns true if out of air (for damage/warning).
func drain(hud, delta: float) -> bool:
	if not hud.air_enabled:
		return false
	var new_air: float = max(0.0, hud.current_air - hud.air_drain_rate * delta)
	update(hud, new_air, hud.max_air)
	return new_air <= 0.0

## Refill air at the surface.
func refill(hud, delta: float) -> void:
	if not hud.air_enabled:
		return
	var new_air: float = min(hud.max_air, hud.current_air + hud.air_refill_rate * delta)
	update(hud, new_air, hud.max_air)

## Flash the air bar a few times — one-shot feedback for the (instant, no
## duration) air reserve powerup.
func flash_bar(hud, duration: float = 1.0) -> void:
	if not hud.air_enabled:
		return
	_flash_remaining = duration
	_flash_timer = 0.0

## Drives the full-screen warning pulse (hud_container tint + danger_overlay
## alpha) and the air bar's one-shot flash. Called every frame from
## HUD._process — the pulse block runs first, then the one-shot flash
## overrides air_bar's modulate on top of it, same order as the original.
func process(hud, delta: float) -> void:
	if hud.air_warning and hud.air_enabled and hud.hud_container:
		_pulse_timer += delta * hud_layer_flash_speed
		var pulse: float = (sin(_pulse_timer) + 1.0) / 2.0
		hud.hud_container.modulate = Color.WHITE.lerp(Color(1.0, 0.3, 0.3, 1.0), pulse)
		if hud.danger_overlay:
			hud.danger_overlay.color = Color(0.15, 0.0, 0.0, pulse * 0.5)
		if hud.air_bar:
			hud.air_bar.modulate = Color.CYAN
	else:
		if hud.hud_container:
			hud.hud_container.modulate = Color.WHITE
		if hud.danger_overlay:
			hud.danger_overlay.color = Color(0, 0, 0, 0)
		_pulse_timer = 0.0

	if _flash_remaining > 0.0 and hud.air_bar:
		_flash_remaining -= delta
		_flash_timer += delta
		var flash_on := int(_flash_timer / FLASH_PERIOD) % 2 == 0
		hud.air_bar.modulate = Color.WHITE if flash_on else FLASH_COLOR
		if _flash_remaining <= 0.0:
			_flash_timer = 0.0
