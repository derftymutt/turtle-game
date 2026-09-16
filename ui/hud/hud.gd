extends CanvasLayer
class_name HUD

## Heads-Up Display for score, health, and experimental meters
## Air and energy systems are toggleable for prototyping

signal time_expired
signal low_air_warning_changed(is_warning: bool)

# References (will be found dynamically)
var score_label: Label
var ufo_pieces_label: Label
var health_container: Control     # HBox from the scene; now holds the heart icons
var boss_health_container: Control
var boss_health_bar: TextureProgressBar
var air_container: Control
var air_bar: TextureProgressBar
var energy_container: Control
var energy_bar: TextureProgressBar
var energy_icon: TextureRect
var super_speed_indicator: Label
var hud_container: Control  # Container for flash effect
var danger_overlay: ColorRect
var sfx_low_air: AudioStreamPlayer
var sfx_energy_charge: AudioStreamPlayer

# Damage vignette — built at runtime (see DamageVignette.build), not part of the base scene
var _damage_vignette := DamageVignette.new()

# Alien Tech displays
var tech_piece_label:  Label       = null
var slot_a_label:      Label       = null
var slot_b_label:      Label       = null
var slot_a_cooldown:   TextureProgressBar = null
var slot_b_cooldown:   TextureProgressBar = null
var slot_a_icon:       TextureRect = null
var slot_b_icon:       TextureRect = null

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

# Game state
var current_score: int = 0
var _hearts := HeartsDisplay.new()
var pieces_collected: int = 0
var pieces_needed: int = 0

## Get current score (used by game over screen)
func get_current_score() -> int:
	return current_score

# Air system (experimental - toggleable)
@export_group("Air System")
@export var air_enabled: bool = true
@export var max_air: float = 30.0
@export var air_drain_rate: float = 1.0
@export var air_refill_rate: float = 30.0
@export var air_warning_threshold: float = 10.0
var current_air: float = 30.0
var air_warning: bool = false
var _air := AirSystem.new()

# Energy system (experimental - toggleable)
@export_group("Energy System")
@export var energy_enabled: bool = true
@export var max_energy: float = 100.0
@export var energy_per_thrust: float = 12.0
@export var energy_recovery_rate: float = 15.0
@export var energy_wall_bonus: float = 40.0
@export var energy_threshold: float = 15.0
@export_subgroup("Desperation")
@export var desperation_enabled: bool = true
@export var desperation_threshold: float = 0.33
@export var desperation_max_multiplier: float = 1.75
var current_energy: float = 100.0
var wall_recovery_active: bool = false  # NEW: Track if we're actively recovering from wall
var level_completing: bool = false  # Suppresses trash cluster spawn and sounds on final piece delivery
var _energy := EnergySystem.new()

# Timer system
@export_group("Timer System")
@export var timer_enabled: bool = true
@export var level_time_limit: float = 180.0
var timer_system := TimerSystem.new()

# Trash cluster score + freebie-timer spawning
var _trash_clusters := TrashClusterSpawner.new()

# Time-based "freebie" trash clusters: a little goodie randomness so trash bags
# still trickle in during low-scoring stretches. Any score-based cluster resets
# this timer, so freebies only ever fill the gaps and stay infrequent.
@export_group("Freebie Trash Clusters")
@export var freebie_clusters_enabled: bool = true
@export var freebie_first_delay: float = 30.0       # first freebie fires around here...
@export var freebie_first_jitter: float = 8.0       # ...give or take this much
@export var freebie_interval: float = 60.0          # then roughly this often after that...
@export var freebie_interval_jitter: float = 15.0   # ...give or take this much

func _ready():
	add_to_group("hud")
	
	sfx_low_air = find_child("SfxLowAir")
	sfx_energy_charge = find_child("SfxEnergyCharge")
	danger_overlay = find_child("DangerOverlay")
	_damage_vignette.build(self, danger_overlay)

	# Find the main container
	for child in get_children():
		if child is Control and not child == danger_overlay and not child == _damage_vignette.rect:
			hud_container = child
			break
	
	if not hud_container:
		push_warning("HUD: Could not find container Control node! Flash effect won't work.")
	
	# Find UI nodes dynamically
	score_label = find_child("ScoreLabel")
	ufo_pieces_label = find_child("UFOPiecesLabel")
	boss_health_container = find_child("BossHealthContainer")
	boss_health_bar = find_child("BossHealthBar")
	health_container = find_child("HealthContainer")
	_hearts.build(health_container)
	air_container = find_child("AirContainer")
	air_bar = find_child("AirBar")
	energy_container = find_child("EnergyContainer")
	energy_bar = find_child("EnergyBar")
	if energy_container:
		energy_icon = energy_container.get_node_or_null("TextureRect")
	super_speed_indicator = find_child("SuperSpeedIndicator")
	
	# Debug: verify we found everything
	if not score_label:
		push_warning("HUD: Could not find ScoreLabel!")
	if not ufo_pieces_label:
		push_warning("HUD: Could not find UFOPiecesLabel!")
	if not health_container:
		push_warning("HUD: Could not find HealthContainer!")
	if not air_bar:
		push_warning("HUD: Could not find AirBar!")
	if not energy_bar:
		push_warning("HUD: Could not find EnergyBar!")
	
	timer_system.start(find_child("TimerLabel"), level_time_limit, timer_enabled)

	_trash_clusters.start(self)

	# Apply black borders to all progress bars
	_apply_bar_borders()
	# Set all label text to black
	_apply_label_colors()

	# Initialize displays
	update_score(0)
	update_ufo_pieces(0, 0)
	update_hearts(_hearts.max_hearts, _hearts.max_hearts)
	update_air(max_air, max_air)
	update_energy(max_energy, max_energy)
	set_super_speed_active(false)
	
	# Hide experimental meters if disabled
	if air_container:
		air_container.visible = air_enabled
	if energy_container:
		energy_container.visible = energy_enabled
	
	if LevelManager:
		LevelManager.piece_delivered.connect(_on_piece_delivered)
		LevelManager.level_started.connect(_on_level_started)
		LevelManager.boss_level_started.connect(_on_boss_level_started)

	# Alien Tech UI
	tech_piece_label = find_child("TechPieceLabel")
	slot_a_label     = find_child("SlotALabel")
	slot_b_label     = find_child("SlotBLabel")
	slot_a_cooldown  = find_child("SlotACooldown")
	slot_b_cooldown  = find_child("SlotBCooldown")
	slot_a_icon      = find_child("SlotAIcon")
	slot_b_icon      = find_child("SlotBIcon")
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
		_slot_a_hot_border = _make_hot_border()
	if slot_b_label:
		_slot_b_hot_border = _make_hot_border()

	AlienTechManager.piece_collected.connect(_on_tech_piece_collected)
	AlienTechManager.tech_slots_changed.connect(_on_tech_slots_changed)
	AlienTechManager.phase_shifter_ammo_changed.connect(_on_phase_shifter_ammo_changed)
	AlienTechManager.powerup_replicator_changed.connect(_on_powerup_replicator_changed)
	_refresh_tech_display()

func _process(delta):
	# Air warning pulse (hud_container/danger_overlay tint) and the air bar's
	# one-shot flash for the air-reserve powerup.
	_air.process(self, delta)

	# Alien Tech cooldown bars
	_apply_slot_cooldown_bar(slot_a_cooldown, 0)
	_apply_slot_cooldown_bar(slot_b_cooldown, 1)
	_apply_slot_label_state(slot_a_label, slot_a_icon, 0)
	_apply_slot_label_state(slot_b_label, slot_b_icon, 1)

	_update_hot_borders(delta)

	# Level timer countdown
	if timer_system.process(delta):
		time_expired.emit()

	# Freebie trash clusters (score-independent). A spawn (score-based or
	# freebie) reschedules the next freebie, so a score-based cluster
	# spawning first pushes this back too.
	_trash_clusters.process_freebie(self, delta)

	# Handle wall recovery visual feedback, then the powerup feedback overlays
	# — applied last so they win over the color-coding above for the frame
	# they're active.
	_energy.process(self, delta)
	_hearts.process()

## Trigger the damage vignette: corners snap to `peak` darkness, then fade
## back to fully transparent over `fade_time` seconds. Re-triggering while a
## fade is in progress (rapid hits) restarts from the peak.
func flash_damage_vignette(peak: float = 0.85, fade_time: float = 0.85) -> void:
	_damage_vignette.flash(peak, fade_time)

## Set all HUD labels to black text
func _apply_label_colors() -> void:
	for label in find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", Color.WHITE)

## Add a 2px black border around each progress bar for readability
func _apply_bar_borders() -> void:
	const RADIUS := 4

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.0, 0.0, 0.0, 1.0)
	bg_style.corner_radius_top_left = RADIUS
	bg_style.corner_radius_top_right = RADIUS
	bg_style.corner_radius_bottom_left = RADIUS
	bg_style.corner_radius_bottom_right = RADIUS

	# Fill is white so the bar's modulate color (green/yellow/red/cyan) comes through cleanly
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color.WHITE
	fill_style.corner_radius_top_left = RADIUS
	fill_style.corner_radius_top_right = RADIUS
	fill_style.corner_radius_bottom_left = RADIUS
	fill_style.corner_radius_bottom_right = RADIUS

# var bars: Array[Range] = [health_bar, air_bar, energy_bar]
# for bar in bars:
#     if bar:
#         bar.add_theme_stylebox_override("background", bg_style)
#         bar.add_theme_stylebox_override("fill", fill_style)

## Update score display
func update_score(new_score: int):
	var previous_score := current_score
	current_score = new_score
	GameManager.current_score = new_score
	if score_label:
		score_label.text = "%d" % current_score
	_trash_clusters.on_score_updated(self, new_score, previous_score)

func add_score(points: int):
	update_score(current_score + points)

## Update the heart icons. `current` / `hearts_max` come from TurtlePlayer.
func update_hearts(current: int, hearts_max: int = 7) -> void:
	_hearts.update(current, hearts_max)

## Blink the heart icons for the duration of an active invincibility powerup
func set_hearts_blinking(active: bool) -> void:
	_hearts.set_blinking(active)

## Update air display
func update_air(air: float, max_a: float):
	_air.update(self, air, max_a)

## Drain air while underwater. Returns true if out of air (for damage/warning)
func drain_air(delta: float):
	return _air.drain(self, delta)

## Refill air at surface
func refill_air(delta: float):
	_air.refill(self, delta)

## Flash the air bar a few times — one-shot feedback for the (instant, no
## duration) air reserve powerup.
func flash_air_bar(duration: float = 1.0) -> void:
	_air.flash_bar(self, duration)

## Blink the energy bar and its icon for the duration of an active energy powerup
func set_energy_blinking(active: bool) -> void:
	_energy.set_blinking(self, active)

## Update energy display
func update_energy(energy: float, max_en: float):
	_energy.update(self, energy, max_en)

## Try to use energy for a thrust
func try_thrust() -> bool:
	return _energy.try_thrust(self)

## Recover energy over time
func recover_energy(delta: float, touching_wall: bool = false):
	_energy.recover(self, delta, touching_wall)

## Called by UFOWorkshop on final piece delivery — silences any active sounds immediately
func begin_level_completion() -> void:
	_energy.begin_level_completion(self)

## Check if player can thrust (has enough energy)
func can_thrust() -> bool:
	return _energy.can_thrust(self)

## Update super speed indicator
func set_super_speed_active(active: bool):
	if super_speed_indicator:
		super_speed_indicator.visible = active
		if active:
			var tween = create_tween().set_loops()
			tween.tween_property(super_speed_indicator, "modulate:a", 0.3, 0.3)
			tween.tween_property(super_speed_indicator, "modulate:a", 1.0, 0.3)
			
## Update UFO pieces display
func update_ufo_pieces(collected: int, needed: int):
	pieces_collected = collected
	pieces_needed = needed
	
	if ufo_pieces_label:
		ufo_pieces_label.text = "%d/%d" % [collected, needed]

		# Color code: green when complete, black otherwise
		if collected >= needed and needed > 0:
			ufo_pieces_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			ufo_pieces_label.add_theme_color_override("font_color", Color.BLACK)

## Signal handlers for LevelManager
func _on_piece_delivered(collected: int, needed: int):
	"""Called when a piece is delivered to the workshop"""
	update_ufo_pieces(collected, needed)

func _on_level_started(level_number: int):
	"""Called when a new level starts - reset piece counter"""
	# LevelManager will emit piece_delivered signal with initial 0/x values
	# so we don't need to do anything here
	pass

func _on_boss_level_started(_level_number: int):
	# Hide UFO pieces section, show boss health bar
	if ufo_pieces_label:
		ufo_pieces_label.get_parent().visible = false
	if boss_health_container:
		boss_health_container.visible = true

	# Connect to submarine boss health signal
	var boss = get_tree().get_first_node_in_group("submarine_boss")
	if boss and boss.has_signal("health_changed"):
		boss.health_changed.connect(_on_boss_health_changed)

func _on_boss_health_changed(current: float, max_hp: float):
	if boss_health_bar:
		boss_health_bar.max_value = max_hp
		boss_health_bar.value = current

# ─── Alien Tech display ───────────────────────────────────────────────────────

func _build_powerup_icons():
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
func _make_hot_border() -> ReferenceRect:
	var rect := ReferenceRect.new()
	rect.editor_only = false
	rect.border_color = Color(1.0, 0.15, 0.1, 1.0)
	rect.border_width = 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)
	return rect

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

func _on_tech_piece_collected(current: int, needed: int):
	if tech_piece_label:
		tech_piece_label.text = "%d/%d" % [current, needed]

func _on_tech_slots_changed(slot_a: Dictionary, slot_b: Dictionary):
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

func _refresh_tech_display():
	if tech_piece_label:
		tech_piece_label.text = "%d/%d" % [
			AlienTechManager.pieces_this_threshold,
			AlienTechManager.PIECES_PER_TECH
		]
	_on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

func _on_phase_shifter_ammo_changed(_current: int, _max_ammo: int, _recharging: bool):
	_on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

func _on_powerup_replicator_changed():
	_on_tech_slots_changed(AlienTechManager.slots[0], AlienTechManager.slots[1])

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

func freeze_timer():
	timer_system.freeze()

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
