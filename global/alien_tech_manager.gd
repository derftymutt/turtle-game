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
signal powerup_replicator_changed(stored_type: int)  # -1 = empty

# ─── Run state ───────────────────────────────────────────────────────────────

var pieces_this_threshold: int = 0
var total_pieces_collected: int = 0

var slots: Array[Dictionary] = [{}, {}]
var _cooldowns: Array[float] = [0.0, 0.0]
var _slot_assigned_order: Array[int] = [-1, -1]  # lower = older
var _assignment_counter: int = 0

const INERTIA_DAMPENER_ACTIVE_DURATION:   float = 3.0
const INERTIA_DAMPENER_COOLDOWN_DURATION: float = 8.0

const DEFLECTOR_SHIELD_ACTIVE_DURATION:   float = 5.0
const DEFLECTOR_SHIELD_COOLDOWN_DURATION: float = 10.0

const TIME_FREEZE_ACTIVE_DURATION:   float = 5.0
const TIME_FREEZE_COOLDOWN_DURATION: float = 10.0

const _COOLDOWN_DURATIONS: Dictionary = {
	AlienTechRegistry.INERTIA_DAMPENER: INERTIA_DAMPENER_ACTIVE_DURATION + INERTIA_DAMPENER_COOLDOWN_DURATION,
	AlienTechRegistry.LATERAL_THRUST:   5.0,
	AlienTechRegistry.TRANSPORTER:      8.0,
	AlienTechRegistry.BUMPER_MAGNET:    5.0,
	AlienTechRegistry.DEFLECTOR_SHIELD: DEFLECTOR_SHIELD_ACTIVE_DURATION + DEFLECTOR_SHIELD_COOLDOWN_DURATION,
	AlienTechRegistry.TIME_FREEZE:      TIME_FREEZE_ACTIVE_DURATION + TIME_FREEZE_COOLDOWN_DURATION,
	AlienTechRegistry.SHOCKWAVE:        30.0,
}

var _passive_bar_ratios: Dictionary = {}

var time_freeze_active: bool = false

# Variety tracking — acts as a set; keys are tech IDs currently "alive" this run
# Grows when a tech is assigned, shrinks when death penalty removes one,
# re-grows if that tech is later reacquired
var _live_unique_techs: Dictionary = {}

# ─── Powerup Replicator state ────────────────────────────────────────────────

var powerup_replicator_stored: int = -1  # -1 = empty

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
	_live_unique_techs[tech_id] = true
	print("👽 Slot %s assigned: %s" % [_slot_letter(slot_index), tech["name"]])
	tech_slots_changed.emit(slots[0], slots[1])

func clear_slot(slot_index: int):
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return
	slots[slot_index] = {}
	_cooldowns[slot_index] = 0.0
	_slot_assigned_order[slot_index] = -1
	tech_slots_changed.emit(slots[0], slots[1])

func has_tech(tech_id: String) -> bool:
	for slot in slots:
		if slot.get("id", "") == tech_id:
			return true
	return false

func is_tech_active(tech_id: String) -> bool:
	return has_tech(tech_id)

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
	_cooldowns[slot_index] = _COOLDOWN_DURATIONS.get(tech["id"], 0.0)
	tech_activated.emit(slot_index, tech["id"])
	print("👽 Activated: %s (slot %s)" % [tech["name"], _slot_letter(slot_index)])
	return true

func get_cooldown_ratio(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return 0.0
	var tech = slots[slot_index]
	if tech.is_empty():
		return 0.0
	var tech_id = tech.get("id", "")
	if _passive_bar_ratios.has(tech_id):
		return 1.0 - _passive_bar_ratios[tech_id]
	var max_cd = _COOLDOWN_DURATIONS.get(tech_id, 0.0)
	if max_cd <= 0.0:
		return 0.0
	return _cooldowns[slot_index] / max_cd

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
	_passive_bar_ratios.clear()
	_live_unique_techs.clear()
	phase_shifter_ammo = PHASE_SHIFTER_MAX_AMMO
	phase_shifter_recharging = false
	phase_shifter_recharge_timer = 0.0
	powerup_replicator_stored = -1
	print("👽 AlienTechManager: Run reset")

# ─── Phase Shifter ───────────────────────────────────────────────────────────

func consume_phase_bullet() -> bool:
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
	tech_slots_changed.emit(slots[0], slots[1])

func _slot_letter(index: int) -> String:
	match index:
		0: return "L"
		1: return "R"
		_: return "?"

# ─── Powerup Replicator ──────────────────────────────────────────────────────

func store_replicated_powerup(powerup_type: int):
	powerup_replicator_stored = powerup_type
	powerup_replicator_changed.emit(powerup_type)

func consume_replicated_powerup() -> int:
	var stored := powerup_replicator_stored
	powerup_replicator_stored = -1
	powerup_replicator_changed.emit(-1)
	return stored
