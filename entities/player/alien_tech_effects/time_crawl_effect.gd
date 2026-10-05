extends AlienTechEffect
class_name TimeCrawlEffect

## Time Crawl — press to slow the whole game for a few seconds, any time. The
## world eases down to DILATION, holds, and eases back up. The turtle slows
## less than everything else: its own clock runs TURTLE_SCALE× faster than
## game time while the crawl is on, so in real time it moves at about
## DILATION × TURTLE_SCALE of its normal pace while the world moves at DILATION.
##
## The faster clock is the same one Stim Shot uses (scale_factor, read by
## TurtlePlayer for kick/shoot cooldowns, sprite speed, drag/buoyancy and
## energy recovery), plus kick strength — Stim Shot only makes the turtle
## kick more often, which doesn't make it cover ground any faster. Launches
## (flipper, bumper, puffer, current) are sped up by part of that factor in
## TurtlePlayer.notify_launch(), so the stronger drag doesn't cut them short:
## LAUNCH_COMPENSATION sets how much of the distance they get back.
##
## The slow-down is global (GameSettings.set_time_crawl(), its own channel so
## it can't fight Temporal Focus's bullet time — the slower of the two wins),
## so the window is timed in REAL seconds, off the physics tick length, not
## the dilated delta. The cooldown is held (see _HOLD_COOLDOWN_TECHS) and runs
## from the end of the crawl, at normal game speed. shutdown() (from
## TurtlePlayer._exit_tree()) guarantees time is never left slowed.
##
## Cold: 5s cooldown. Hot: no cooldown — press again as soon as a crawl ends.

# All durations in real seconds; EASE_IN and EASE_OUT are part of DURATION.
const DURATION: float = 3.0
const EASE_IN: float = 0.3
const EASE_OUT: float = 0.5

const DILATION: float = 0.4       # world speed at full crawl
const TURTLE_SCALE: float = 1.75  # turtle clock vs game time at full crawl (0.4 × 1.75 = 0.7 of normal)
# How much of that speed-up a launch gets: 1.0 = the full factor (the launch
# goes its usual distance), 0.0 = none (it falls well short).
const LAUNCH_COMPENSATION: float = 0.5

var active: bool = false  # read by TechAura
var scale_factor: float = 1.0
var _elapsed: float = 0.0

func activate(player, _slot_index: int) -> void:
	# Hot has no cooldown to refuse a press mid-crawl — the next crawl can only
	# start once this one has ended and time is back to normal.
	if active:
		return
	active = true
	_elapsed = 0.0
	AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_CRAWL, 1.0)
	player._flash(Color(0.55, 0.7, 1.0), 0.3)

func physics_process(_player, _delta: float) -> void:
	if not active:
		return
	_elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if _elapsed >= DURATION:
		_end()
		return
	# 0 = normal speed, 1 = full crawl.
	var depth: float = minf(_elapsed / EASE_IN, (DURATION - _elapsed) / EASE_OUT)
	depth = smoothstep(0.0, 1.0, depth)
	GameSettings.set_time_crawl(lerpf(1.0, DILATION, depth))
	scale_factor = lerpf(1.0, TURTLE_SCALE, depth)
	AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_CRAWL, 1.0 - _elapsed / DURATION)

## Speed multiplier for a launch right now (see TurtlePlayer.notify_launch()).
func launch_scale() -> float:
	return lerpf(1.0, scale_factor, LAUNCH_COMPENSATION)

## Swapped out mid-crawl — don't leave the game slowed for a tech that's gone.
func on_slots_changed(_player) -> void:
	if active and not AlienTechManager.has_tech(AlienTechRegistry.TIME_CRAWL):
		_end()

## Hard stop — the player is leaving the tree.
func shutdown() -> void:
	if active:
		_end()

func _end() -> void:
	active = false
	scale_factor = 1.0
	GameSettings.set_time_crawl(1.0)
	AlienTechManager.clear_passive_bar(AlienTechRegistry.TIME_CRAWL)
	AlienTechManager.release_cooldown_hold(AlienTechRegistry.TIME_CRAWL)
