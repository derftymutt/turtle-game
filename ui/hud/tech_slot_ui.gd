extends RefCounted
class_name TechSlotUI

## Alien tech slot UI: slot labels/icons/cooldown bars, the flashing "hot"
## border, and the powerup-replicator's icon carousel + uses-remaining badge.
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

# Hot tech indicator — a flashing red border drawn around the slot's icon+label
# row. Built at runtime (like the replicator icons above) and kept in sync with
# its target container's rect every frame, since the row resizes with its text.
var _slot_a_hot_border: ReferenceRect = null
var _slot_b_hot_border: ReferenceRect = null
var _hot_pulse_timer: float = 0.0

## Finds the slot nodes under `hud` and builds the runtime-only extras
## (powerup icon atlas, replicator carousels, hot borders). Call once from
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

	if slot_a_label:
		_slot_a_hot_border = _make_hot_border(hud)
	if slot_b_label:
		_slot_b_hot_border = _make_hot_border(hud)

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

## Border-only overlay control, parented directly to the HUD CanvasLayer (not
## inside a Container) so it's free to be positioned/sized manually each frame
## instead of being fought over by container layout.
func _make_hot_border(hud) -> ReferenceRect:
	var rect := ReferenceRect.new()
	rect.editor_only = false
	rect.border_color = Color(1.0, 0.15, 0.1, 1.0)
	rect.border_width = 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	hud.add_child(rect)
	return rect

## Called every frame from HUD._process().
func process(delta: float) -> void:
	_apply_slot_cooldown_bar(slot_a_cooldown, 0)
	_apply_slot_cooldown_bar(slot_b_cooldown, 1)
	_apply_slot_label_state(slot_a_label, slot_a_icon, 0)
	_apply_slot_label_state(slot_b_label, slot_b_icon, 1)
	_update_hot_borders(delta)

func _update_hot_borders(delta: float) -> void:
	_hot_pulse_timer += delta * 6.0
	var pulse := (sin(_hot_pulse_timer) + 1.0) * 0.5
	var alpha := lerpf(0.35, 1.0, pulse)
	_sync_hot_border(_slot_a_hot_border, slot_a_label, AlienTechManager.is_slot_hot(0), alpha)
	_sync_hot_border(_slot_b_hot_border, slot_b_label, AlienTechManager.is_slot_hot(1), alpha)

func _sync_hot_border(border: ReferenceRect, label: Label, is_hot: bool, alpha: float) -> void:
	if not border:
		return
	border.visible = is_hot
	if not is_hot or not label:
		return
	var row: Control = label.get_parent()
	if not row:
		return
	# row.get_global_rect() would be the row container's own rect, which is
	# stretched wide (size_flags_horizontal expand) to split evenly with its
	# sibling column — reaching halfway across the screen even though the
	# icon/label/bar inside only use part of that width. Use the tight union
	# of the row's visible children instead, so the border hugs the content.
	const PAD := 2.0
	var rect := _tight_content_rect(row)
	if rect.size == Vector2.ZERO:
		return
	rect = rect.grow(PAD)
	border.global_position = rect.position
	border.size = rect.size
	border.modulate.a = alpha

## Union of a Control's visible children's global rects.
func _tight_content_rect(row: Control) -> Rect2:
	var result := Rect2()
	var first := true
	for child in row.get_children():
		if not child is Control:
			continue
		var c: Control = child
		if not c.visible:
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size == Vector2.ZERO:
			continue
		result = r if first else result.merge(r)
		first = false
	return result

func on_tech_piece_collected(current: int, needed: int) -> void:
	if tech_piece_label:
		tech_piece_label.text = "%d/%d" % [current, needed]

func on_tech_slots_changed(slot_a: Dictionary, slot_b: Dictionary) -> void:
	_update_slot_display(slot_a_label, slot_a_cooldown, slot_a_icon, slot_a, _slot_a_rpl_container, _slot_a_rpl_icons)
	_update_slot_display(slot_b_label, slot_b_cooldown, slot_b_icon, slot_b, _slot_b_rpl_container, _slot_b_rpl_icons)

func _update_slot_display(label: Label, cooldown_bar: TextureProgressBar,
		icon: TextureRect, tech: Dictionary,
		rpl_container: HBoxContainer = null, rpl_icons: Array = []):
	if not label:
		return
	if rpl_container:
		rpl_container.visible = false
	if tech.is_empty():
		label.text = ""
		label.modulate = Color(0.5, 0.5, 0.5, 0.8)
		if cooldown_bar:
			cooldown_bar.visible = false
	elif tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		if AlienTechManager.is_tech_hot(AlienTechRegistry.PHASE_SHIFTER):
			label.text = "Phase Shifter ∞"
			if cooldown_bar:
				cooldown_bar.visible = false
		else:
			var ammo := AlienTechManager.phase_shifter_ammo
			var max_ammo := AlienTechManager.PHASE_SHIFTER_MAX_AMMO
			var recharging := AlienTechManager.phase_shifter_recharging
			if recharging:
				label.text = "Phase Shifter --/%d" % max_ammo
			else:
				label.text = "Phase Shifter %d/%d" % [ammo, max_ammo]
			if cooldown_bar:
				cooldown_bar.visible = true
		label.modulate = tech.get("color", Color.WHITE)
	elif tech.get("id", "") == AlienTechRegistry.POWERUP_REPLICATOR:
		var slots_state := AlienTechManager.powerup_replicator_slots
		var selected := AlienTechManager.powerup_replicator_selected
		label.text = tech.get("slot_label", tech.get("name", "?"))
		label.modulate = tech.get("color", Color.WHITE)
		if cooldown_bar:
			cooldown_bar.visible = false
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
		if cooldown_bar:
			var tech_id: String = tech.get("id", "")
			cooldown_bar.visible = AlienTechManager.tech_has_bar(tech_id) or tech.get("has_passive_bar", false)

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

const _COOLDOWN_BAR_MUTED := Color(0.55, 0.55, 0.55, 1.0)

## Drives one slot's cooldown TextureProgressBar. Techs AlienTechManager
## tracks as two-phase (see get_bar_phase()) get a full-color drain for their
## active window, then a muted refill for the cooldown that snaps back to
## full color the instant it's ready again. Only tint_progress (the fill) is
## ever touched — tint_under (the background track) is left alone so it
## always reads as its normal grey, never darkening toward black. Everything
## else keeps the older single-bar behavior (_get_slot_bar_value), untinted.
func _apply_slot_cooldown_bar(cooldown_bar: TextureProgressBar, slot_index: int) -> void:
	if not cooldown_bar or not cooldown_bar.visible:
		return
	var phase_info := AlienTechManager.get_bar_phase(slot_index)
	var phase: String = phase_info.get("phase", "none")
	if phase == "none":
		cooldown_bar.tint_progress = Color.WHITE
		cooldown_bar.value = _get_slot_bar_value(slot_index)
		return
	cooldown_bar.value = phase_info.get("ratio", 0.0)
	# Multiplying the fill's own baked-in color by a neutral grey darkens it
	# without shifting its hue — a muted version of that same active color,
	# not a flat generic grey. "off" (a hot toggle-style tech, not currently
	# engaged — see get_bar_phase()) reads the same as "cooldown": greyed,
	# and its ratio is 0.0 so the bar also empties out, not just dims.
	cooldown_bar.tint_progress = _COOLDOWN_BAR_MUTED if phase == "cooldown" or phase == "off" else Color.WHITE

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
