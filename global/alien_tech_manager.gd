extends Node

## Autoload: AlienTechManager
## Manages the player's alien tech run state:
##   - How many tech pieces have been collected this run
##   - Which techs occupy slot A and slot B
##   - Fires signals so HUD, selection screen, and player can react
##   - Cooldown tracking for active (button-press) techs
##
## Add to Project Settings > Autoload as "AlienTechManager" (AFTER AlienTechRegistry)

# ─── Constants ───────────────────────────────────────────────────────────────

const MAX_SLOTS:       int = 2
const PIECES_PER_TECH: int = 1
const CHOICES_OFFERED: int = 1

# ─── Signals ─────────────────────────────────────────────────────────────────

signal piece_collected(current: int, needed: int)
signal selection_ready(choices: Array)
signal tech_slots_changed(slot_a: Dictionary, slot_b: Dictionary)
signal tech_activated(slot_index: int, tech_id: String)
signal tech_cooldown_ready(slot_index: int, tech_id: String)
signal phase_shifter_ammo_changed(current: int, max_ammo: int, recharging: bool)
signal powerup_replicator_changed()

# ─── Run state ───────────────────────────────────────────────────────────────

var pieces_this_threshold: int = 0
var total_pieces_collected: int = 0

var slots: Array[Dictionary] = [{}, {}]
var _cooldowns: Array[float] = [0.0, 0.0]
var _slot_assigned_order: Array[int] = [-1, -1]  # lower = older
var _assignment_counter: int = 0

# Hot/Fried state — 0 = normal, 1 = hot. A tech that's still HOT the next time
# it survives a level transition gets fried (removed). Tracked per slot index
# (not per tech id) so it travels with swap_slots() like everything else here.
var _hot_streak: Array[int] = [0, 0]

const INERTIA_DAMPENER_ACTIVE_DURATION:   float = 3.0
const INERTIA_DAMPENER_COOLDOWN_DURATION: float = 8.0

const DEFLECTOR_SHIELD_ACTIVE_DURATION:   float = 5.0
const DEFLECTOR_SHIELD_COOLDOWN_DURATION: float = 10.0

const TIME_FREEZE_ACTIVE_DURATION:   float = 5.0
const TIME_FREEZE_COOLDOWN_DURATION: float = 10.0

const GRAVITON_HARNESS_ACTIVE_DURATION:   float = 5.0
const GRAVITON_HARNESS_COOLDOWN_DURATION: float = 5.0

const _COOLDOWN_DURATIONS: Dictionary = {
	AlienTechRegistry.INERTIA_DAMPENER: INERTIA_DAMPENER_ACTIVE_DURATION + INERTIA_DAMPENER_COOLDOWN_DURATION,
	AlienTechRegistry.LATERAL_THRUST:   5.0,
	AlienTechRegistry.TRANSPORTER:      8.0,
	AlienTechRegistry.BUMPER_MAGNET:    5.0,
	AlienTechRegistry.DEFLECTOR_SHIELD: DEFLECTOR_SHIELD_ACTIVE_DURATION + DEFLECTOR_SHIELD_COOLDOWN_DURATION,
	AlienTechRegistry.TIME_FREEZE:      TIME_FREEZE_ACTIVE_DURATION + TIME_FREEZE_COOLDOWN_DURATION,
	AlienTechRegistry.SHOCKWAVE:        30.0,
	AlienTechRegistry.GRAVITON_HARNESS: GRAVITON_HARNESS_ACTIVE_DURATION + GRAVITON_HARNESS_COOLDOWN_DURATION,
}

# Techs whose HUD bar should read as two distinct phases — full-color drain
# for the active window, then a greyed-out refill for the cooldown — rather
# than one opaque bar covering the whole active+cooldown span. See
# get_bar_phase(). Add an entry here (plus its own *_ACTIVE_DURATION /
# *_COOLDOWN_DURATION consts) to give another tech the same treatment.
const _TWO_PHASE_BAR_DURATIONS: Dictionary = {
	AlienTechRegistry.INERTIA_DAMPENER: {"active": INERTIA_DAMPENER_ACTIVE_DURATION, "cooldown": INERTIA_DAMPENER_COOLDOWN_DURATION},
	AlienTechRegistry.GRAVITON_HARNESS: {"active": GRAVITON_HARNESS_ACTIVE_DURATION, "cooldown": GRAVITON_HARNESS_COOLDOWN_DURATION},
	AlienTechRegistry.DEFLECTOR_SHIELD: {"active": DEFLECTOR_SHIELD_ACTIVE_DURATION, "cooldown": DEFLECTOR_SHIELD_COOLDOWN_DURATION},
	AlienTechRegistry.TIME_FREEZE:      {"active": TIME_FREEZE_ACTIVE_DURATION,      "cooldown": TIME_FREEZE_COOLDOWN_DURATION},
}

var _passive_bar_ratios: Dictionary = {}

var time_freeze_active: bool = false

# Variety tracking — acts as a set; keys are tech IDs currently "alive" this run
# Grows when a tech is assigned, shrinks when death penalty removes one,
# re-grows if that tech is later reacquired
var _live_unique_techs: Dictionary = {}

# ─── Powerup Replicator state ────────────────────────────────────────────────

var powerup_replicator_slots: Array[int] = [-1, -1, -1]  # -1 = empty; 4-wide during a hot batch
var powerup_replicator_selected: int = 0                   # which slot is highlighted
var powerup_replicator_hot_uses_remaining: int = 0          # >0 only mid hot-batch

# ─── Phase Shifter ammo ──────────────────────────────────────────────────────

const PHASE_SHIFTER_MAX_AMMO: int = 10
const PHASE_SHIFTER_RECHARGE_TIME: float = 10.0

var phase_shifter_ammo: int = PHASE_SHIFTER_MAX_AMMO
var phase_shifter_recharging: bool = false
var phase_shifter_recharge_timer: float = 0.0

# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready():
	print("👽 AlienTechManager initialized")

# ─── Process (cooldown ticking) ──────────────────────────────────────────────

func _process(delta: float):
	for i in MAX_SLOTS:
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = max(0.0, _cooldowns[i] - delta)
			if _cooldowns[i] == 0.0:
				var tech_id = slots[i].get("id", "")
				if tech_id != "":
					tech_cooldown_ready.emit(i, tech_id)

	if phase_shifter_recharging:
		phase_shifter_recharge_timer -= delta
		if phase_shifter_recharge_timer <= 0.0:
			phase_shifter_recharging = false
			phase_shifter_ammo = PHASE_SHIFTER_MAX_AMMO
			phase_shifter_ammo_changed.emit(phase_shifter_ammo, PHASE_SHIFTER_MAX_AMMO, false)

# ─── Piece collection ────────────────────────────────────────────────────────

func collect_piece():
	# The tutorial spawns a trash bag purely as target practice; don't let the
	# alien tech it hides advance progression or pop the selection screen.
	if LevelManager.is_tutorial:
		return
	pieces_this_threshold += 1
	total_pieces_collected += 1
	piece_collected.emit(pieces_this_threshold, PIECES_PER_TECH)
	print("👽 Alien tech piece: %d/%d" % [pieces_this_threshold, PIECES_PER_TECH])
	if pieces_this_threshold >= PIECES_PER_TECH:
		_trigger_selection()

func _trigger_selection():
	pieces_this_threshold = 0
	var owned_ids: Array[String] = []
	for slot in slots:
		if not slot.is_empty():
			owned_ids.append(slot["id"])
	var choices = AlienTechRegistry.get_random_choices(CHOICES_OFFERED, owned_ids)
	if choices.is_empty():
		print("👽 No new techs available — player owns everything!")
		return
	selection_ready.emit(choices)

# ─── Tech selection / slot management ────────────────────────────────────────

func assign_tech(tech_id: String, slot_index: int):
	var tech = AlienTechRegistry.get_tech(tech_id)
	if tech.is_empty():
		return
	slots[slot_index] = tech
	_cooldowns[slot_index] = 0.0
	_slot_assigned_order[slot_index] = _assignment_counter
	_assignment_counter += 1
	_hot_streak[slot_index] = 0  # a freshly-picked tech always starts cold
	_live_unique_techs[tech_id] = true
	print("👽 Slot %s assigned: %s" % [_slot_letter(slot_index), tech["name"]])
	tech_slots_changed.emit(slots[0], slots[1])

func clear_slot(slot_index: int):
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return
	slots[slot_index] = {}
	_cooldowns[slot_index] = 0.0
	_slot_assigned_order[slot_index] = -1
	_hot_streak[slot_index] = 0
	tech_slots_changed.emit(slots[0], slots[1])

func has_tech(tech_id: String) -> bool:
	for slot in slots:
		if slot.get("id", "") == tech_id:
			return true
	return false

func is_tech_active(tech_id: String) -> bool:
	return has_tech(tech_id)

# ─── Hot / Fried ─────────────────────────────────────────────────────────────

func is_slot_hot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	return not slots[slot_index].is_empty() and _hot_streak[slot_index] == 1

func is_tech_hot(tech_id: String) -> bool:
	var idx := get_slot_index_for_tech(tech_id)
	return idx != -1 and is_slot_hot(idx)

## Used by SaveManager to restore hot state after assign_tech() (which always
## resets a slot to cold, since normal reassignment should start fresh).
func set_slot_hot(slot_index: int, hot: bool) -> void:
	if slot_index < 0 or slot_index >= MAX_SLOTS or slots[slot_index].is_empty():
		return
	_hot_streak[slot_index] = 1 if hot else 0

## Called once per real level transition (between-levels cutscene), before the
## next level loads. A tech that was already HOT gets fried (removed); a tech
## that was normal and still equipped becomes HOT for the level about to start.
## Returns {hot: [tech dicts], fried: [tech dicts]} for the cutscene to display.
func advance_level_transition() -> Dictionary:
	var hot: Array[Dictionary] = []
	var fried: Array[Dictionary] = []
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			continue
		if _hot_streak[i] == 1:
			var tech := slots[i]
			fried.append(tech)
			print("👽 AlienTechManager: %s got fried and was lost!" % tech.get("name", ""))
			clear_slot(i)
		else:
			_hot_streak[i] = 1
			hot.append(slots[i])
			print("👽 AlienTechManager: %s is now HOT" % slots[i].get("name", ""))
	if not hot.is_empty() or not fried.is_empty():
		tech_slots_changed.emit(slots[0], slots[1])
	return {"hot": hot, "fried": fried}

# ─── Active tech firing ──────────────────────────────────────────────────────

func try_activate_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	var tech = slots[slot_index]
	if tech.is_empty():
		return false
	if not tech.get("needs_input", false):
		return false
	if _cooldowns[slot_index] > 0.0:
		print("👽 %s on cooldown: %.1fs remaining" % [tech["name"], _cooldowns[slot_index]])
		return false
	_cooldowns[slot_index] = _effective_cooldown_max(slot_index, tech["id"])
	tech_activated.emit(slot_index, tech["id"])
	print("👽 Activated: %s (slot %s)" % [tech["name"], _slot_letter(slot_index)])
	return true

## The cooldown ceiling for a slot, adjusted for hot overrides. Shared by
## try_activate_slot() (to seed the timer) and get_cooldown_ratio() (to
## normalize it), so the two never disagree about what "full" means.
func _effective_cooldown_max(slot_index: int, tech_id: String) -> float:
	var base: float = _COOLDOWN_DURATIONS.get(tech_id, 0.0)
	if not is_slot_hot(slot_index):
		return base
	match tech_id:
		AlienTechRegistry.LATERAL_THRUST, AlienTechRegistry.TRANSPORTER, \
		AlienTechRegistry.SHOCKWAVE, AlienTechRegistry.INERTIA_DAMPENER, \
		AlienTechRegistry.BUMPER_MAGNET, AlienTechRegistry.GRAVITON_HARNESS:
			return 0.0  # hot: no cooldown
		AlienTechRegistry.TIME_FREEZE:
			# Hot: active duration doubled, post-active recovery halved.
			return (TIME_FREEZE_ACTIVE_DURATION * 2.0) + (TIME_FREEZE_COOLDOWN_DURATION * 0.5)
		AlienTechRegistry.DEFLECTOR_SHIELD:
			# Hot: active duration unchanged (only radius grows), recovery halved.
			return DEFLECTOR_SHIELD_ACTIVE_DURATION + (DEFLECTOR_SHIELD_COOLDOWN_DURATION * 0.5)
		_:
			return base

func get_cooldown_ratio(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return 0.0
	var tech = slots[slot_index]
	if tech.is_empty():
		return 0.0
	var tech_id = tech.get("id", "")
	if _passive_bar_ratios.has(tech_id):
		return 1.0 - _passive_bar_ratios[tech_id]
	var max_cd = _effective_cooldown_max(slot_index, tech_id)
	if max_cd <= 0.0:
		return 0.0
	return _cooldowns[slot_index] / max_cd

## Two-phase bar reading for techs listed in _TWO_PHASE_BAR_DURATIONS (an
## "activate for N seconds, then M seconds before it can fire again" tech).
## Derived purely from _cooldowns[slot_index], which already counts down
## from (active + cooldown) to 0 — no per-frame bookkeeping needed elsewhere.
## Returns {"phase": "active"|"cooldown"|"ready"|"none", "ratio": float}:
##   "active":   still mid-effect. ratio 1.0 (just activated) → 0.0 (effect over).
##   "cooldown": effect over, recharging. ratio 0.0 (just ended) → 1.0 (ready)
##               — continuous with where "active" left off, no jump.
##   "ready":    fully recovered (or hot, which has no cooldown at all).
##   "none":     this tech isn't in _TWO_PHASE_BAR_DURATIONS; caller should
##               fall back to the plain get_cooldown_ratio() bar.
func get_bar_phase(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return {"phase": "none", "ratio": 0.0}
	var tech_id: String = slots[slot_index].get("id", "")
	if not _TWO_PHASE_BAR_DURATIONS.has(tech_id):
		return {"phase": "none", "ratio": 0.0}
	# A tech can override its own bar directly (e.g. hot Inertia Dampener's
	# manual on/off toggle, via set_passive_bar) — respect that first, full
	# color either way since it's not really a "cooldown" in that state.
	if _passive_bar_ratios.has(tech_id):
		return {"phase": "active", "ratio": _passive_bar_ratios[tech_id]}
	if is_slot_hot(slot_index):
		return {"phase": "ready", "ratio": 1.0}  # hot: no cooldown for these techs
	var remaining: float = _cooldowns[slot_index]
	if remaining <= 0.0:
		return {"phase": "ready", "ratio": 1.0}
	var durations: Dictionary = _TWO_PHASE_BAR_DURATIONS[tech_id]
	var active_dur: float = durations["active"]
	var cooldown_dur: float = durations["cooldown"]
	if remaining > cooldown_dur:
		var active_ratio: float = (remaining - cooldown_dur) / active_dur if active_dur > 0.0 else 0.0
		return {"phase": "active", "ratio": clamp(active_ratio, 0.0, 1.0)}
	var cooldown_ratio: float = 1.0 - (remaining / cooldown_dur) if cooldown_dur > 0.0 else 1.0
	return {"phase": "cooldown", "ratio": clamp(cooldown_ratio, 0.0, 1.0)}

func set_passive_bar(tech_id: String, ratio: float):
	_passive_bar_ratios[tech_id] = clamp(ratio, 0.0, 1.0)

func clear_passive_bar(tech_id: String):
	_passive_bar_ratios.erase(tech_id)

func tech_has_bar(tech_id: String) -> bool:
	return _COOLDOWN_DURATIONS.has(tech_id)

# ─── Run lifecycle ───────────────────────────────────────────────────────────

func get_variety_count() -> int:
	return _live_unique_techs.size()

func reset_run():
	pieces_this_threshold = 0
	total_pieces_collected = 0
	slots = [{}, {}]
	_cooldowns = [0.0, 0.0]
	_slot_assigned_order = [-1, -1]
	_assignment_counter = 0
	_hot_streak = [0, 0]
	_passive_bar_ratios.clear()
	_live_unique_techs.clear()
	phase_shifter_ammo = PHASE_SHIFTER_MAX_AMMO
	phase_shifter_recharging = false
	phase_shifter_recharge_timer = 0.0
	powerup_replicator_slots = [-1, -1, -1]
	powerup_replicator_selected = 0
	powerup_replicator_hot_uses_remaining = 0
	print("👽 AlienTechManager: Run reset")

# ─── Phase Shifter ───────────────────────────────────────────────────────────

func consume_phase_bullet() -> bool:
	if is_tech_hot(AlienTechRegistry.PHASE_SHIFTER):
		return true  # hot: unlimited ammo, no recharge
	if phase_shifter_recharging or phase_shifter_ammo <= 0:
		return false
	phase_shifter_ammo -= 1
	if phase_shifter_ammo <= 0:
		phase_shifter_recharging = true
		phase_shifter_recharge_timer = PHASE_SHIFTER_RECHARGE_TIME
	phase_shifter_ammo_changed.emit(phase_shifter_ammo, PHASE_SHIFTER_MAX_AMMO, phase_shifter_recharging)
	return true

func get_slot_index_for_tech(tech_id: String) -> int:
	for i in MAX_SLOTS:
		if slots[i].get("id", "") == tech_id:
			return i
	return -1

# ─── Death penalty ───────────────────────────────────────────────────────────

## If the player dies with both slots filled, removes the oldest tech and returns
## its display name. Returns "" if fewer than 2 slots are occupied.
func remove_oldest_tech() -> String:
	var filled: Array[int] = []
	for i in MAX_SLOTS:
		if not slots[i].is_empty():
			filled.append(i)
	if filled.size() < 2:
		return ""
	var oldest := filled[0]
	for i in filled.slice(1):
		if _slot_assigned_order[i] < _slot_assigned_order[oldest]:
			oldest = i
	var tech_name: String = slots[oldest].get("name", "")
	var tech_id: String = slots[oldest].get("id", "")
	clear_slot(oldest)
	_live_unique_techs.erase(tech_id)
	print("👽 AlienTechManager: Lost oldest tech on death: %s" % tech_name)
	return tech_name

# ─── Helpers ─────────────────────────────────────────────────────────────────

func find_empty_slot() -> int:
	for i in MAX_SLOTS:
		if slots[i].is_empty():
			return i
	return -1

func swap_slots() -> void:
	var temp_slot := slots[0]
	slots[0] = slots[1]
	slots[1] = temp_slot
	var temp_cd := _cooldowns[0]
	_cooldowns[0] = _cooldowns[1]
	_cooldowns[1] = temp_cd
	var temp_order := _slot_assigned_order[0]
	_slot_assigned_order[0] = _slot_assigned_order[1]
	_slot_assigned_order[1] = temp_order
	var temp_hot := _hot_streak[0]
	_hot_streak[0] = _hot_streak[1]
	_hot_streak[1] = temp_hot
	tech_slots_changed.emit(slots[0], slots[1])

func _slot_letter(index: int) -> String:
	match index:
		0: return "L"
		1: return "R"
		_: return "?"

# ─── Powerup Replicator ──────────────────────────────────────────────────────
#
# Cold: each pickup stores one copy of that specific type into the next empty
# of the (unused 4th) slot, cycle/long-press as usual.
# Hot: a pickup ignores its own type and instead fills all 4 slots with one of
# each powerup type — "wild" choices — and grants exactly 2 uses. Picking a
# slot consumes it normally, but the moment the 2nd use of the batch is spent,
# the whole carousel force-clears even if unclaimed options remain. A pickup
# mid-batch restarts a fresh batch of 2 rather than stacking.

const REPLICATOR_HOT_USES_PER_BATCH: int = 2
const _REPLICATOR_ALL_TYPES: Array[int] = [0, 1, 2, 3]  # Shield, Air Reserve, Energy Freeze, Rapid Fire

func store_replicated_powerup(powerup_type: int):
	if is_tech_hot(AlienTechRegistry.POWERUP_REPLICATOR):
		powerup_replicator_slots = _REPLICATOR_ALL_TYPES.duplicate()
		powerup_replicator_selected = 0
		powerup_replicator_hot_uses_remaining = REPLICATOR_HOT_USES_PER_BATCH
		powerup_replicator_changed.emit()
		return
	for i in powerup_replicator_slots.size():
		if powerup_replicator_slots[i] < 0:
			powerup_replicator_slots[i] = powerup_type
			# If current selection is empty, point it at the new slot
			if powerup_replicator_slots[powerup_replicator_selected] < 0:
				powerup_replicator_selected = i
			powerup_replicator_changed.emit()
			return
	# All slots full — drop the powerup (player still got the effect)

func cycle_replicator_selection():
	var filled: Array[int] = []
	for i in powerup_replicator_slots.size():
		if powerup_replicator_slots[i] >= 0:
			filled.append(i)
	if filled.size() <= 1:
		return
	var cur_pos := filled.find(powerup_replicator_selected)
	if cur_pos < 0:
		cur_pos = 0
	powerup_replicator_selected = filled[(cur_pos + 1) % filled.size()]
	powerup_replicator_changed.emit()

func consume_replicated_powerup() -> int:
	var idx := powerup_replicator_selected
	var stored := powerup_replicator_slots[idx]
	if stored < 0:
		return -1
	powerup_replicator_slots[idx] = -1

	if powerup_replicator_hot_uses_remaining > 0:
		powerup_replicator_hot_uses_remaining -= 1
		if powerup_replicator_hot_uses_remaining <= 0:
			# Batch spent — clear everything, even options never picked, and
			# drop back to the canonical 3-slot cold size until the next pickup.
			powerup_replicator_slots = [-1, -1, -1]
			powerup_replicator_selected = 0
			powerup_replicator_changed.emit()
			return stored

	# Auto-select leftmost remaining filled slot
	powerup_replicator_selected = 0
	for i in powerup_replicator_slots.size():
		if powerup_replicator_slots[i] >= 0:
			powerup_replicator_selected = i
			break
	powerup_replicator_changed.emit()
	return stored
