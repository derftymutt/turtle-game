extends RefCounted
class_name TechSlotUI

## Alien tech slot UI: slot labels/icons/cooldown bars, the fiery "hot" label
## sheen, the blinking ready-key prompt, and the powerup-replicator's icon carousel + uses-remaining badge.
##
## Fully self-contained — nothing outside hud.gd references any of this
## class's symbols — so unlike AirSystem/EnergySystem/TrashClusterSpawner it
## owns its node references outright for their whole lifetime, built once
## from HUD._ready() via build(hud). AlienTechManager's signals are
## connected directly to this object's on_* methods from HUD._ready().

var tech_piece_label: Label = null
var slot_a_label: Label = null
var slot_b_label: Label = null
var slot_a_cooldown: TextureProgressBar = null
var slot_b_cooldown: TextureProgressBar = null
var slot_a_icon: TextureRect = null
var slot_b_icon: TextureRect = null

var _powerup_icons: Array = []
var _placeholder_tex: Texture2D = null

var _slot_a_rpl_container: HBoxContainer = null
var _slot_b_rpl_container: HBoxContainer = null
var _slot_a_rpl_icons: Array = []
var _slot_b_rpl_icons: Array = []
var _slot_a_rpl_count_label: Label = null  # hot only — "x2"/"x1" uses-remaining badge
var _slot_b_rpl_count_label: Label = null

# Hot tech indicator — a band of flowing red/yellow fire sweeps across the slot
# label's text, which otherwise keeps its tech colour. One material per slot,
# since each carries its own label's colour and width as shader uniforms.
var _fire_materials: Array[ShaderMaterial] = []

# "Ready" key prompt (e.g. "LB" / "L Shift") that blinks just under the
# cooldown bar, flush with its screen-centre end, whenever a press-activated
# tech can be fired.
var _slot_a_key_prompt: Label = null
var _slot_b_key_prompt: Label = null

## Finds the slot nodes under `hud` and builds the runtime-only extras
## (powerup icon atlas, replicator carousels, fire material, key prompts). Call once from
## HUD._ready(), then connect AlienTechManager's signals to this object and
## call refresh().
func build(hud) -> void:
	tech_piece_label = hud.find_child("TechPieceLabel")
	slot_a_label     = hud.find_child("SlotALabel")
	slot_b_label     = hud.find_child("SlotBLabel")
	slot_a_cooldown  = hud.find_child("SlotACooldown")
	slot_b_cooldown  = hud.find_child("SlotBCooldown")
	slot_a_icon      = hud.find_child("SlotAIcon")
	slot_b_icon      = hud.find_child("SlotBIcon")
	_build_powerup_icons()
	if slot_a_label:
		_slot_a_rpl_container = _create_rpl_icon_container(slot_a_label.get_parent(), _slot_a_rpl_icons)
		_slot_a_rpl_count_label = _create_rpl_count_label(_slot_a_rpl_container)
	if slot_b_label:
		_slot_b_rpl_container = _create_rpl_icon_container(slot_b_label.get_parent(), _slot_b_rpl_icons)
		# Mirror the left layout: icons sit left of the label, not right of the icon
		slot_b_label.get_parent().move_child(_slot_b_rpl_container, slot_b_label.get_index())
		_slot_b_rpl_count_label = _create_rpl_count_label(_slot_b_rpl_container)

	var fire_shader: Shader = load("res://ui/hud/fire_text.gdshader")
	for i in 2:
		var mat := ShaderMaterial.new()
		mat.shader = fire_shader
		_fire_materials.append(mat)

	# Each prompt is a child of its cooldown bar (a plain Control, not a
	# Container), so it can hang in the spare space below the 6px bar without
	# growing the row, and hides along with the bar for techs that have none.
	if slot_a_label and slot_a_cooldown:
		_slot_a_key_prompt = _create_key_prompt(slot_a_label)
		slot_a_cooldown.add_child(_slot_a_key_prompt)
	if slot_b_label and slot_b_cooldown:
		_slot_b_key_prompt = _create_key_prompt(slot_b_label)
		slot_b_cooldown.add_child(_slot_b_key_prompt)

func _build_powerup_icons() -> void:
	var sheet: Texture2D = load("res://entities/collectibles/powerup/sprites/powerup.png")
	var regions := [
		Rect2(64, 0, 16, 16),   # SHIELD
		Rect2(32, 0, 16, 16),   # AIR_RESERVE
		Rect2(0, 0, 16, 16),    # ENERGY_ENDLESS
		Rect2(96, 0, 16, 16),   # RAPID_FIRE
	]
	for region in regions:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = region
		_powerup_icons.append(atlas)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_placeholder_tex = ImageTexture.create_from_image(img)

func _create_rpl_icon_container(parent: Node, icons_out: Array) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.visible = false
	parent.add_child(container)
	# Always build 4 (not 3) so the container is already sized for a hot batch
	# (all 4 powerup types, wild) — cold mode simply never fills the 4th.
	for i in 4:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(12, 12)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		container.add_child(tr)
		icons_out.append(tr)
	return container

## "x2"/"x1" badge shown next to the carousel only during a hot Replicator batch.
func _create_rpl_count_label(container: HBoxContainer) -> Label:
	if not container:
		return null
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.visible = false
	container.add_child(lbl)
	return lbl

## Blinking key-name prompt, styled to match the slot label it sits beside.
func _create_key_prompt(slot_label: Label) -> Label:
	var lbl := Label.new()
	var font := slot_label.get_theme_font("font")
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_font_size_override("font_size", _KEY_PROMPT_FONT_SIZE)
	lbl.add_theme_constant_override("line_spacing", 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = false
	return lbl

## Called every frame from HUD._process().
func process(_delta: float) -> void:
	_apply_bar_visibility(slot_a_cooldown, 0)
	_apply_bar_visibility(slot_b_cooldown, 1)
	_apply_slot_cooldown_bar(slot_a_cooldown, 0)
	_apply_slot_cooldown_bar(slot_b_cooldown, 1)
	_apply_slot_label_state(slot_a_label, slot_a_icon, 0)
	_apply_slot_label_state(slot_b_label, slot_b_icon, 1)
	_apply_hot_text(slot_a_label, 0)
	_apply_hot_text(slot_b_label, 1)
	_apply_key_prompt(_slot_a_key_prompt, 0)
	_apply_key_prompt(_slot_b_key_prompt, 1)

const _KEY_PROMPT_BLINK_PERIOD_MSEC: int = 350
# Blink alternates white with the violet of the turtle's TechAura glow.
const _KEY_PROMPT_BLINK_COLOR := Color(0.65, 0.12, 1.0)
const _KEY_PROMPT_FONT_SIZE: int = 12
const _KEY_PROMPT_Y_OFFSET: float = -3.0  # tuck up under the bar (font has top padding)
const _SLOT_GAMEPAD_KEYS := ["LB", "RB"]

## Hot slots get the fire-sweep shader on their label text (which supplies the
## tech colour itself); everything else gets its normal tech colour back. Runs after _apply_slot_label_state() so the
## alpha it chose (dimmed / blinking) is preserved — only rgb is touched.
func _apply_hot_text(label: Label, slot_index: int) -> void:
	if not label:
		return
	var tech: Dictionary = AlienTechManager.slots[slot_index]
	if tech.is_empty():
		label.material = null
		return
	var a := label.modulate.a
	var c: Color = tech.get("color", Color.WHITE)
	if AlienTechManager.is_slot_hot(slot_index):
		var mat := _fire_materials[slot_index]
		mat.set_shader_parameter("base_color", c)
		mat.set_shader_parameter("text_width", label.size.x)
		label.material = mat
		label.modulate = Color(1.0, 1.0, 1.0, a)  # colour comes from base_color instead
	else:
		label.material = null
		label.modulate = Color(c.r, c.g, c.b, a)

## The key prompt is a child of the bar, so a slot that needs a prompt but no
## bar (e.g. hot Lateral Thrust, hot Phase Shifter) keeps the bar node in the
## layout with only its own texture made transparent (self_modulate doesn't
## reach children) — the prompt stays put where the bar's end would be.
func _apply_bar_visibility(bar: TextureProgressBar, slot_index: int) -> void:
	if not bar:
		return
	var wants_bar := _slot_wants_bar(slot_index)
	bar.visible = wants_bar or _is_slot_ready_to_press(slot_index)
	bar.self_modulate.a = 1.0 if wants_bar else 0.0

func _slot_wants_bar(slot_index: int) -> bool:
	var tech: Dictionary = AlienTechManager.slots[slot_index]
	if tech.is_empty():
		return false
	var tech_id: String = tech.get("id", "")
	if tech_id == AlienTechRegistry.PHASE_SHIFTER:
		return not AlienTechManager.is_tech_hot(AlienTechRegistry.PHASE_SHIFTER)
	if tech_id == AlienTechRegistry.POWERUP_REPLICATOR:
		return false
	if not (AlienTechManager.tech_has_bar(tech_id) or tech.get("has_passive_bar", false)):
		return false
	return AlienTechManager.slot_bar_meaningful(slot_index)

## Shows the slot's button name, blinking white/violet, while its press-activated tech is
## fully charged and can be fired right now.
func _apply_key_prompt(prompt: Label, slot_index: int) -> void:
	if not prompt:
		return
	var ready := _is_slot_ready_to_press(slot_index)
	prompt.visible = ready
	if not ready:
		return
	prompt.text = _SLOT_GAMEPAD_KEYS[slot_index] if GameSettings.using_gamepad \
			else GameSettings.tech_slot_key_label(slot_index)
	# Normally tucked under the bar, flush with its screen-centre end. With the
	# bar hidden (transparent placeholder) it instead sits level with the
	# label, at the bar end touching it, so it doesn't float in empty space.
	var bar: Control = prompt.get_parent()
	prompt.size = prompt.get_minimum_size()
	var toward_centre := slot_index == 0
	if bar.self_modulate.a > 0.0:
		var x := bar.size.x - prompt.size.x if toward_centre else 0.0
		prompt.position = Vector2(x, bar.size.y + _KEY_PROMPT_Y_OFFSET)
	else:
		var x := 0.0 if toward_centre else bar.size.x - prompt.size.x
		prompt.position = Vector2(x, (bar.size.y - prompt.size.y) * 0.5)
	var blink_on := int(Time.get_ticks_msec() / _KEY_PROMPT_BLINK_PERIOD_MSEC) % 2 == 0
	prompt.add_theme_color_override("font_color", Color.WHITE if blink_on else _KEY_PROMPT_BLINK_COLOR)

func _is_slot_ready_to_press(slot_index: int) -> bool:
	if not AlienTechManager.slot_needs_input(slot_index):
		return false
	# Only techs that (cold) have a bar get a prompt — it's anchored to that
	# bar. That leaves out the Replicator (its carousel sits there instead).
	# Flipper Velcro and Phase Shifter are the exceptions: no bar of their own
	# (or none when hot), but knowing the button matters more than the prompt
	# never stopping blinking, so they get the transparent placeholder bar.
	var tech: Dictionary = AlienTechManager.slots[slot_index]
	var tech_id: String = tech.get("id", "")
	if tech_id == AlienTechRegistry.POWERUP_REPLICATOR:
		return false
	if tech_id != AlienTechRegistry.PHASE_SHIFTER and tech_id != AlienTechRegistry.FLIPPER_VELCRO \
			and not (AlienTechManager.tech_has_bar(tech_id) or tech.get("has_passive_bar", false)):
		return false
	var phase: String = AlienTechManager.get_bar_phase(slot_index).get("phase", "none")
	if phase != "none":
		# "off" = hot toggle-style tech that's switched off — pressable now.
		return phase == "ready" or phase == "off"
	return not _is_slot_dimmed(slot_index)

func on_tech_piece_collected(current: int, needed: int) -> void:
	if tech_piece_label:
		tech_piece_label.text = "%d/%d" % [current, needed]

func on_tech_slots_changed(slot_a: Dictionary, slot_b: Dictionary) -> void:
	_update_slot_display(slot_a_label, slot_a_cooldown, slot_a_icon, slot_a, _slot_a_rpl_container, _slot_a_rpl_icons)
	_update_slot_display(slot_b_label, slot_b_cooldown, slot_b_icon, slot_b, _slot_b_rpl_container, _slot_b_rpl_icons)

## Cooldown bar visibility isn't set here — hot state can change without a
## slot-change signal, so _apply_bar_visibility() decides it every frame.
func _update_slot_display(label: Label, _cooldown_bar: TextureProgressBar,
		icon: TextureRect, tech: Dictionary,
		rpl_container: HBoxContainer = null, rpl_icons: Array = []):
	if not label:
		return
	if rpl_container:
		rpl_container.visible = false
	if tech.is_empty():
		label.text = ""
		label.modulate = Color(0.5, 0.5, 0.5, 0.8)
	elif tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		if AlienTechManager.is_tech_hot(AlienTechRegistry.PHASE_SHIFTER):
			label.text = "Phase Shifter ∞"
		else:
			var ammo := AlienTechManager.phase_shifter_ammo
			var max_ammo := AlienTechManager.PHASE_SHIFTER_MAX_AMMO
			var recharging := AlienTechManager.phase_shifter_recharging
			if recharging:
				label.text = "Phase Shifter --/%d" % max_ammo
			else:
				label.text = "Phase Shifter %d/%d" % [ammo, max_ammo]
		label.modulate = tech.get("color", Color.WHITE)
	elif tech.get("id", "") == AlienTechRegistry.POWERUP_REPLICATOR:
		var slots_state := AlienTechManager.powerup_replicator_slots
		var selected := AlienTechManager.powerup_replicator_selected
		label.text = tech.get("slot_label", tech.get("name", "?"))
		label.modulate = tech.get("color", Color.WHITE)
		if rpl_container and rpl_icons.size() >= slots_state.size():
			var filled_count := 0
			for i in slots_state.size():
				var ir: TextureRect = rpl_icons[i]
				var st: int = slots_state[i]
				if st >= 0 and st < _powerup_icons.size():
					ir.texture = _powerup_icons[st]
					ir.modulate = Color.WHITE if i == selected else Color(0.5, 0.5, 0.5, 1.0)
					ir.visible = true
					filled_count += 1
				else:
					ir.visible = false
			# Icons beyond the current slot count (cold mode only uses 3 of the 4 built) stay hidden.
			for i in range(slots_state.size(), rpl_icons.size()):
				(rpl_icons[i] as TextureRect).visible = false
			rpl_container.visible = filled_count > 0
		var count_label: Label = _slot_a_rpl_count_label if rpl_container == _slot_a_rpl_container else _slot_b_rpl_count_label
		if count_label:
			var uses_left: int = AlienTechManager.powerup_replicator_hot_uses_remaining
			if uses_left > 0:
				count_label.text = "x%d" % uses_left
				count_label.visible = true
			else:
				count_label.visible = false
	else:
		label.text = tech.get("slot_label", tech.get("name", "?"))
		label.modulate = tech.get("color", Color.WHITE)

func refresh() -> void:
	if tech_piece_label:
		tech_piece_label.text = "%d/%d" % [
			AlienTechManager.pieces_this_threshold,
			AlienTechManager.PIECES_PER_TECH
		]
	on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

func on_phase_shifter_ammo_changed(_current: int, _max_ammo: int, _recharging: bool) -> void:
	on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

func on_powerup_replicator_changed() -> void:
	on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

const _COOLDOWN_BAR_MUTED := Color(0.75, 0.75, 0.75, 1.0)

## Drives one slot's cooldown TextureProgressBar. Techs AlienTechManager
## tracks as two-phase (see get_bar_phase()) get a full-color drain for their
## active window, then a muted refill for the cooldown that snaps back to
## full color the instant it's ready again. Only tint_progress (the fill) is
## ever touched — tint_under (the background track) is left alone so it
## always reads as its normal grey, never darkening toward black. Everything
## else keeps the older single-bar behavior (_get_slot_bar_value), muted the
## same way whenever that bar is a cooldown refilling (_is_bar_refilling).
func _apply_slot_cooldown_bar(cooldown_bar: TextureProgressBar, slot_index: int) -> void:
	if not cooldown_bar or not cooldown_bar.visible:
		return
	var phase_info := AlienTechManager.get_bar_phase(slot_index)
	var phase: String = phase_info.get("phase", "none")
	if phase == "none":
		cooldown_bar.value = _get_slot_bar_value(slot_index)
		cooldown_bar.tint_progress = _COOLDOWN_BAR_MUTED if _is_bar_refilling(slot_index, cooldown_bar.value) else Color.WHITE
		return
	cooldown_bar.value = phase_info.get("ratio", 0.0)
	# Multiplying the fill's own baked-in color by a neutral grey darkens it
	# without shifting its hue — a muted version of that same active color,
	# not a flat generic grey. "off" (a hot toggle-style tech, not currently
	# engaged — see get_bar_phase()) reads the same as "cooldown": greyed,
	# and its ratio is 0.0 so the bar also empties out, not just dims.
	cooldown_bar.tint_progress = _COOLDOWN_BAR_MUTED if phase == "cooldown" or phase == "off" else Color.WHITE

## Single-bar techs: is this bar a cooldown/recharge refilling (muted), as
## opposed to full/ready or a tech's own active window draining (full color)?
func _is_bar_refilling(slot_index: int, value: float) -> bool:
	if value >= 1.0:
		return false
	var tech_id: String = AlienTechManager.slots[slot_index].get("id", "")
	if tech_id == AlienTechRegistry.PHASE_SHIFTER:
		# A partly spent magazine is still usable — only the reload is a refill.
		return AlienTechManager.phase_shifter_recharging
	# A passive bar is normally a tech's active window draining (Bumper Magnet
	# orbiting, Dermal Regen channeling) — except Bubble Shield, whose passive
	# bar is its pop-to-regen recharge.
	if AlienTechManager.has_passive_bar(tech_id) and tech_id != AlienTechRegistry.BUBBLE_SHIELD:
		return false
	return true

const _ACTIVE_BLINK_PERIOD_MSEC: int = 300  # one alpha flip every 300ms (600ms full cycle)
const _ACTIVE_BLINK_LOW_ALPHA: float = 0.35

## Drives one slot's label/icon opacity. Two-phase techs (see get_bar_phase())
## blink the label while active — a clearer "this is live right now" signal
## than the old flat dim — then grey both label and icon out while cooling
## down (or, for a hot toggle-style tech, while simply switched off) so the
## text agrees with the bar. Everything else keeps the older
## _is_slot_dimmed() behavior (dim whenever there's any outstanding cooldown).
func _apply_slot_label_state(label: Label, icon: TextureRect, slot_index: int) -> void:
	if not label and not icon:
		return
	var phase_info := AlienTechManager.get_bar_phase(slot_index)
	var phase: String = phase_info.get("phase", "none")
	if phase == "none":
		var dimmed := _is_slot_dimmed(slot_index)
		if label:
			label.modulate.a = 0.5 if dimmed else 1.0
		if icon:
			icon.modulate.a = 0.5 if dimmed else 1.0
		return
	match phase:
		"active":
			var blink_on := int(Time.get_ticks_msec() / _ACTIVE_BLINK_PERIOD_MSEC) % 2 == 0
			if label:
				label.modulate.a = 1.0 if blink_on else _ACTIVE_BLINK_LOW_ALPHA
			if icon:
				icon.modulate.a = 1.0
		"cooldown", "off":
			if label:
				label.modulate.a = 0.5
			if icon:
				icon.modulate.a = 0.5
		_:  # "ready"
			if label:
				label.modulate.a = 1.0
			if icon:
				icon.modulate.a = 1.0

func _get_slot_bar_value(slot_index: int) -> float:
	var tech := AlienTechManager.slots[slot_index]
	if tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		if AlienTechManager.phase_shifter_recharging:
			return 1.0 - (AlienTechManager.phase_shifter_recharge_timer / AlienTechManager.PHASE_SHIFTER_RECHARGE_TIME)
		return float(AlienTechManager.phase_shifter_ammo) / float(AlienTechManager.PHASE_SHIFTER_MAX_AMMO)
	return 1.0 - AlienTechManager.get_cooldown_ratio(slot_index)

func _is_slot_dimmed(slot_index: int) -> bool:
	var tech := AlienTechManager.slots[slot_index]
	if tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		if AlienTechManager.is_tech_hot(AlienTechRegistry.PHASE_SHIFTER):
			return false
		return AlienTechManager.phase_shifter_recharging
	if tech.get("id", "") == AlienTechRegistry.POWERUP_REPLICATOR:
		var sel := AlienTechManager.powerup_replicator_selected
		return AlienTechManager.powerup_replicator_slots[sel] < 0
	return AlienTechManager.get_cooldown_ratio(slot_index) > 0.0
