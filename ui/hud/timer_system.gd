extends RefCounted
class_name TimerSystem

## Level countdown timer — counts down from a level's time limit, flashes red
## as it nears zero, and reports expiry so HUD can emit its own time_expired
## signal (a RefCounted can't be the thing external code calls
## hud.time_expired.connect() on, so HUD still owns that signal).

var enabled: bool = true
var time_remaining: float = 0.0
var active: bool = false
var expired: bool = false

var _label: Label = null
var _time_limit: float = 180.0
var _flash_timer: float = 0.0

## Wires the countdown to `label` (may be null) and starts it if `timer_enabled`.
func start(label: Label, time_limit: float, timer_enabled: bool) -> void:
	_label = label
	_time_limit = time_limit
	enabled = timer_enabled
	if _label:
		_label.visible = timer_enabled
	if timer_enabled:
		time_remaining = time_limit
		active = true
		_update_display()

## Ticks the countdown. Returns true the frame it just hit zero, so the
## caller can emit its own time_expired signal.
func process(delta: float) -> bool:
	if not active:
		return false
	time_remaining = max(0.0, time_remaining - delta)
	if time_remaining <= 10.0:
		_flash_timer += delta * 6.0
	_update_display()
	if time_remaining <= 0.0:
		active = false
		expired = true
		return true
	return false

func _update_display() -> void:
	if not _label:
		return
	var mins := int(time_remaining) / 60
	var secs := int(time_remaining) % 60
	_label.text = "%d:%02d" % [mins, secs]
	if time_remaining > 30.0:
		_label.modulate = Color.WHITE
	elif time_remaining > 10.0:
		_label.modulate = Color.YELLOW
	else:
		var pulse := (sin(_flash_timer) + 1.0) / 2.0
		_label.modulate = Color.WHITE.lerp(Color.RED, 0.5 + pulse * 0.5)

## Stop the countdown immediately (e.g. on final piece delivery), preserving
## time_remaining for a bonus calculation.
func freeze() -> void:
	active = false
