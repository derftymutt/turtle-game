extends Node2D
class_name TechAura

## Glow radiating from the turtle into the water on the screen-left side when
## tech slot A is filled and screen-right for slot B (a full ring with both),
## so equipped techs read at a glance on the player, not just in the HUD. Hot
## slots mix red/yellow fire into their side, and a side brightens from
## base_strength to active_strength while its tech is actually in effect
## (always, for passive and hot always-on techs). A side disappears entirely
## while its tech is recharging and can't be used. Playtest placeholder for
## eventual real sprites — all the look lives in tech_aura.gdshader.
##
## Runtime child of TurtlePlayer. Keeps itself screen-aligned (the body spins
## freely) and polls AlienTechManager every frame, since hot state can change
## without a slot-change signal.

const HALF_SIZE: float = 20.0
const FADE_SPEED: float = 4.0  # per second — ~0.25s ease when a side turns on/off
const ACTIVE_FADE_SPEED: float = 8.0  # per second — snappier, so short activations still read
# Techs with no duration (instant fire, a Phase Shifter shot, a Replicator
# use) brighten their side for this long instead.
const INSTANT_PULSE: float = 0.4

var _rect: ColorRect
var _mat: ShaderMaterial
var _left_on: float = 0.0
var _right_on: float = 0.0
var _left_hot: float = 0.0
var _right_hot: float = 0.0
var _left_active: float = 0.0
var _right_active: float = 0.0
var _pulse: Array[float] = [0.0, 0.0]

func _ready() -> void:
	name = "TechAura"
	# Just under the turtle sprite (absolute z 15), above motion trails (10).
	z_as_relative = false
	z_index = 14
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://entities/player/tech_aura.gdshader")
	_mat.set_shader_parameter("half_size", HALF_SIZE)
	_rect = ColorRect.new()
	_rect.size = Vector2(HALF_SIZE, HALF_SIZE) * 2.0
	_rect.position = -Vector2(HALF_SIZE, HALF_SIZE)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	# Method callables (not lambdas) so these autoload connections are dropped
	# automatically when this player's aura is freed.
	AlienTechManager.tech_activated.connect(_on_tech_activated)
	AlienTechManager.phase_shifter_ammo_changed.connect(_on_phase_shifter_ammo_changed)
	AlienTechManager.powerup_replicator_changed.connect(_on_powerup_replicator_changed)
	_sync(0.0, true)

func _process(delta: float) -> void:
	# global_rotation = 0 cancels the body's spin (rotation = 0 would not).
	global_rotation = 0.0
	_sync(delta, false)

func _sync(delta: float, snap: bool) -> void:
	var step := 1.0 if snap else FADE_SPEED * delta
	var active_step := 1.0 if snap else ACTIVE_FADE_SPEED * delta
	for i in 2:
		_pulse[i] = maxf(_pulse[i] - delta, 0.0)
	_left_active = move_toward(_left_active, 1.0 if _is_slot_active(0) else 0.0, active_step)
	_right_active = move_toward(_right_active, 1.0 if _is_slot_active(1) else 0.0, active_step)
	_mat.set_shader_parameter("left_active", _left_active)
	_mat.set_shader_parameter("right_active", _right_active)
	_left_on = move_toward(_left_on, _target_on(0), step)
	_right_on = move_toward(_right_on, _target_on(1), step)
	_left_hot = move_toward(_left_hot, _target_hot(0), step)
	_right_hot = move_toward(_right_hot, _target_hot(1), step)
	_mat.set_shader_parameter("left_on", _left_on)
	_mat.set_shader_parameter("right_on", _right_on)
	_mat.set_shader_parameter("left_hot", _left_hot)
	_mat.set_shader_parameter("right_hot", _right_hot)
	_rect.visible = _left_on > 0.0 or _right_on > 0.0

## Lit while equipped and usable (or in use) — dark while empty or recharging.
func _target_on(slot_index: int) -> float:
	if AlienTechManager.slots[slot_index].is_empty():
		return 0.0
	if _is_slot_active(slot_index):
		return 1.0
	return 0.0 if _is_cooling_down(slot_index) else 1.0

## Recharging and unusable. Only meaningful once _is_slot_active() is false:
## a tech's cooldown timer already runs during its active window.
func _is_cooling_down(slot_index: int) -> bool:
	var tech_id: String = AlienTechManager.slots[slot_index].get("id", "")
	if tech_id == AlienTechRegistry.PHASE_SHIFTER:
		return AlienTechManager.phase_shifter_recharging \
				and not AlienTechManager.is_tech_hot(AlienTechRegistry.PHASE_SHIFTER)
	var phase: String = AlienTechManager.get_bar_phase(slot_index).get("phase", "none")
	if phase != "none":
		return phase == "cooldown"  # "off" (hot toggle, switched off) is usable
	# Covers plain cooldowns, and passive bars such as a popped Bubble Shield
	# regenerating.
	return AlienTechManager.get_cooldown_ratio(slot_index) > 0.0

func _target_hot(slot_index: int) -> float:
	return 1.0 if AlienTechManager.is_slot_hot(slot_index) else 0.0

func _on_tech_activated(slot_index: int, _tech_id: String) -> void:
	_pulse_slot(slot_index)

func _on_phase_shifter_ammo_changed(_current: int, _max_ammo: int, _recharging: bool) -> void:
	_pulse_tech(AlienTechRegistry.PHASE_SHIFTER)

func _on_powerup_replicator_changed() -> void:
	_pulse_tech(AlienTechRegistry.POWERUP_REPLICATOR)

func _pulse_slot(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < 2:
		_pulse[slot_index] = INSTANT_PULSE

func _pulse_tech(tech_id: String) -> void:
	_pulse_slot(AlienTechManager.get_slot_index_for_tech(tech_id))

## Is this slot's tech in effect right now (not merely equipped)?
func _is_slot_active(slot_index: int) -> bool:
	var tech: Dictionary = AlienTechManager.slots[slot_index]
	if tech.is_empty():
		return false
	# Passive techs, and hot always-on ones (Graviton Harness, Magnetic
	# Repulsion), have no button — they're in effect whenever they aren't
	# recharging (e.g. a popped Bubble Shield isn't).
	if not AlienTechManager.slot_needs_input(slot_index):
		return not _is_cooling_down(slot_index)
	if _pulse[slot_index] > 0.0:
		return true
	var player = get_parent()
	var tech_id: String = tech.get("id", "")
	if tech_id == AlienTechRegistry.FLIPPER_VELCRO:
		return player._flipper_velcro_latched
	var effect = player._tech_effects.get(tech_id)
	if effect == null:
		return false
	match tech_id:
		AlienTechRegistry.TRANSPORTER:
			return effect.windup or effect.invincible
		AlienTechRegistry.MULTI_BEAM:
			return effect.is_in_progress()
	# Every other timed/toggle effect exposes a plain `active` flag.
	return "active" in effect and effect.active
