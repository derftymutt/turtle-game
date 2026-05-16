extends CanvasLayer
class_name HUD

## Heads-Up Display for score, health, and experimental meters
## Air and energy systems are toggleable for prototyping

signal time_expired

# References (will be found dynamically)
var score_label: Label
var ufo_pieces_label: Label
var health_bar: TextureProgressBar
var boss_health_container: Control
var boss_health_bar: TextureProgressBar
var air_container: Control
var air_bar: TextureProgressBar
var energy_container: Control
var energy_bar: TextureProgressBar
var super_speed_indicator: Label
var hud_container: Control  # Container for flash effect
var danger_overlay: ColorRect
var sfx_low_air: AudioStreamPlayer
var sfx_energy_charge: AudioStreamPlayer

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

# Game state
var current_score: int = 0
var current_health: float = 100.0
var max_health: float = 100.0
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
var is_touching_wall: bool = false
var wall_recovery_active: bool = false  # NEW: Track if we're actively recovering from wall

# Timer system
@export_group("Timer System")
@export var timer_enabled: bool = true
@export var level_time_limit: float = 240.0
var timer_label: Label = null
var time_remaining: float = 0.0
var _timer_active: bool = false
var _timer_expired: bool = false
var _timer_flash_timer: float = 0.0

# Trash cluster score spawning
const TRASH_CLUSTER_SCENE = preload("res://entities/collectibles/trash_cluster/trash_cluster.tscn")
const CLUSTER_SCORE_INTERVAL: int = 250
var _next_cluster_score: int = CLUSTER_SCORE_INTERVAL

# Visual feedback
var air_flash_timer: float = 0.0
var air_flash_interval: float = 0.5
var hud_layer_flash_speed: float = 5.0
var energy_pulse_timer: float = 0.0  # NEW: For wall recovery pulse
var energy_pulse_speed: float = 8.0  # NEW: How fast the pulse is

func _ready():
	add_to_group("hud")
	
	sfx_low_air = find_child("SfxLowAir")
	sfx_energy_charge = find_child("SfxEnergyCharge")
	danger_overlay = find_child("DangerOverlay")

	# Find the main container
	for child in get_children():
		if child is Control and not child == danger_overlay:
			hud_container = child
			break
	
	if not hud_container:
		push_warning("HUD: Could not find container Control node! Flash effect won't work.")
	
	# Find UI nodes dynamically
	score_label = find_child("ScoreLabel")
	ufo_pieces_label = find_child("UFOPiecesLabel")
	boss_health_container = find_child("BossHealthContainer")
	boss_health_bar = find_child("BossHealthBar")
	health_bar = find_child("HealthBar")
	air_container = find_child("AirContainer")
	air_bar = find_child("AirBar")
	energy_container = find_child("EnergyContainer")
	energy_bar = find_child("EnergyBar")
	super_speed_indicator = find_child("SuperSpeedIndicator")
	
	# Debug: verify we found everything
	if not score_label:
		push_warning("HUD: Could not find ScoreLabel!")
	if not ufo_pieces_label:
		push_warning("HUD: Could not find UFOPiecesLabel!")
	if not health_bar:
		push_warning("HUD: Could not find HealthBar!")
	if not air_bar:
		push_warning("HUD: Could not find AirBar!")
	if not energy_bar:
		push_warning("HUD: Could not find EnergyBar!")
	
	timer_label = find_child("TimerLabel")
	if timer_label:
		timer_label.visible = timer_enabled
	if timer_enabled:
		time_remaining = level_time_limit
		_timer_active = true
		_update_timer_display()

	# Apply black borders to all progress bars
	_apply_bar_borders()
	# Set all label text to black
	_apply_label_colors()

	# Initialize displays
	update_score(0)
	update_ufo_pieces(0, 0)
	update_health(max_health, max_health)
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
	if slot_b_label:
		_slot_b_rpl_container = _create_rpl_icon_container(slot_b_label.get_parent(), _slot_b_rpl_icons)
		# Mirror the left layout: icons sit left of the label, not right of the icon
		slot_b_label.get_parent().move_child(_slot_b_rpl_container, slot_b_label.get_index())

	AlienTechManager.piece_collected.connect(_on_tech_piece_collected)
	AlienTechManager.tech_slots_changed.connect(_on_tech_slots_changed)
	AlienTechManager.phase_shifter_ammo_changed.connect(_on_phase_shifter_ammo_changed)
	AlienTechManager.powerup_replicator_changed.connect(_on_powerup_replicator_changed)
	_refresh_tech_display()

func _process(delta):
	# Handle air warning flash - entire HUD layer pulses red
	if air_warning and air_enabled and hud_container:
		air_flash_timer += delta * hud_layer_flash_speed
		var pulse = (sin(air_flash_timer) + 1.0) / 2.0
		var warning_color = Color.WHITE.lerp(Color(1.0, 0.3, 0.3, 1.0), pulse)
		hud_container.modulate = warning_color

		if danger_overlay:
			var screen_pulse = (sin(air_flash_timer) + 1.0) / 2.0
			danger_overlay.color = Color(0.15, 0.0, 0.0, screen_pulse * 0.5)

		if air_bar:
			air_bar.modulate = Color.CYAN
	else:
		if hud_container:
			hud_container.modulate = Color.WHITE
		if danger_overlay:
			danger_overlay.color = Color(0, 0, 0, 0)
		air_flash_timer = 0.0
	
	# Alien Tech cooldown bars
	if slot_a_cooldown and slot_a_cooldown.visible:
		slot_a_cooldown.value = _get_slot_bar_value(0)
	if slot_b_cooldown and slot_b_cooldown.visible:
		slot_b_cooldown.value = _get_slot_bar_value(1)
	var dimmed_a := _is_slot_dimmed(0)
	if slot_a_label:
		slot_a_label.modulate.a = 0.5 if dimmed_a else 1.0
	if slot_a_icon:
		slot_a_icon.modulate.a = 0.5 if dimmed_a else 1.0
	var dimmed_b := _is_slot_dimmed(1)
	if slot_b_label:
		slot_b_label.modulate.a = 0.5 if dimmed_b else 1.0
	if slot_b_icon:
		slot_b_icon.modulate.a = 0.5 if dimmed_b else 1.0

	# Level timer countdown
	if _timer_active:
		time_remaining = max(0.0, time_remaining - delta)
		if time_remaining <= 10.0:
			_timer_flash_timer += delta * 6.0
		_update_timer_display()
		if time_remaining <= 0.0:
			_timer_active = false
			_timer_expired = true
			time_expired.emit()

	# Handle wall recovery visual feedback
	if wall_recovery_active and energy_bar:
		energy_pulse_timer += delta * energy_pulse_speed
		
		# Pulse between current color and bright cyan
		var pulse = (sin(energy_pulse_timer) + 1.0) / 2.0
		
		# Get the base color (white/orange/red based on energy level)
		var base_color = Color.WHITE
		var energy_ratio = current_energy / max_energy
		if energy_ratio <= 0.2:
			base_color = Color.RED
		elif energy_ratio <= 0.5:
			base_color = Color.ORANGE
		
		# Pulse to bright cyan to indicate wall recovery
		var recovery_color = base_color.lerp(Color.GOLD, pulse * 0.7)
		energy_bar.modulate = recovery_color
	else:
		energy_pulse_timer = 0.0
		# Reset to normal color coding when not recovering from wall
		update_energy(current_energy, max_energy)

func _update_timer_display() -> void:
	if not timer_label:
		return
	var mins := int(time_remaining) / 60
	var secs := int(time_remaining) % 60
	timer_label.text = "%d:%02d" % [mins, secs]
	if time_remaining > 30.0:
		timer_label.modulate = Color.WHITE
	elif time_remaining > 10.0:
		timer_label.modulate = Color.YELLOW
	else:
		var pulse := (sin(_timer_flash_timer) + 1.0) / 2.0
		timer_label.modulate = Color.WHITE.lerp(Color.RED, 0.5 + pulse * 0.5)

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
	# Only spawn a cluster when score is actually increasing past a milestone
	if new_score > previous_score and current_score >= _next_cluster_score:
		_next_cluster_score += CLUSTER_SCORE_INTERVAL
		_spawn_trash_cluster()

func add_score(points: int):
	update_score(current_score + points)

func _spawn_trash_cluster():
	var scene = get_tree().current_scene
	if not scene:
		return
	var cluster = TRASH_CLUSTER_SCENE.instantiate()
	var inv = get_viewport().get_canvas_transform().affine_inverse()
	var screen_size = get_viewport().get_visible_rect().size
	var spawn_y = screen_size.y * randf_range(0.3, 0.78)
	cluster.max_y = (inv * Vector2(0.0, screen_size.y * 0.82)).y
	if randf() > 0.5:
		# Spawn from right, drift left
		cluster.drift_speed = -38.0
		scene.add_child(cluster)
		cluster.global_position = inv * Vector2(screen_size.x + 55, spawn_y)
	else:
		# Spawn from left, drift right
		cluster.drift_speed = 38.0
		scene.add_child(cluster)
		cluster.global_position = inv * Vector2(-55, spawn_y)
	# Clamp spawn position and drift to the ocean band (below the surface)
	var ocean = get_tree().get_first_node_in_group("ocean")
	var min_world_y = -116.0  # 10px below default surface_y of -126
	if ocean:
		min_world_y = ocean.surface_y + 10.0
	cluster.min_y = min_world_y
	cluster.global_position.y = max(cluster.global_position.y, min_world_y)
	print("👾 Trash cluster spawned at score %d" % current_score)

## Update health display
func update_health(health: float, max_hp: float):
	current_health = health
	max_health = max_hp
	
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = health
		
		# Color code health bar
		if health / max_hp > 0.6:
			health_bar.modulate = Color.GREEN
		elif health / max_hp > 0.3:
			health_bar.modulate = Color.YELLOW
		else:
			health_bar.modulate = Color.RED

## Update air display
func update_air(air: float, max_a: float):
	if not air_enabled:
		return
	
	current_air = air
	max_air = max_a
	
	if air_bar:
		air_bar.max_value = max_a
		air_bar.value = air
		
		# Warning state
		if air <= air_warning_threshold:
			if not air_warning:
				air_warning = true
				air_flash_timer = 0.0
				if sfx_low_air:
					sfx_low_air.play()
		else:
			air_warning = false
			if sfx_low_air and sfx_low_air.playing:
				sfx_low_air.stop()
			air_bar.modulate = Color.CYAN

## Drain air while underwater
func drain_air(delta: float):
	if not air_enabled:
		return
	
	current_air = max(0.0, current_air - air_drain_rate * delta)
	update_air(current_air, max_air)
	
	# Return true if out of air (for damage/warning)
	return current_air <= 0.0

## Refill air at surface
func refill_air(delta: float):
	if not air_enabled:
		return
	
	current_air = min(max_air, current_air + air_refill_rate * delta)
	update_air(current_air, max_air)

## Update energy display
func update_energy(energy: float, max_en: float):
	if not energy_enabled:
		return
	
	current_energy = energy
	max_energy = max_en
	
	if energy_bar:
		energy_bar.max_value = max_en
		energy_bar.value = energy
		
		# Only update color if NOT actively recovering from wall
		# (wall recovery has its own pulsing color in _process)
		if not wall_recovery_active:
			# Color code energy bar
			if energy / max_en > 0.5:
				energy_bar.modulate = Color.WHITE
			elif energy / max_en > 0.2:
				energy_bar.modulate = Color.ORANGE
			else:
				energy_bar.modulate = Color.RED

## Try to use energy for a thrust
func try_thrust() -> bool:
	if not energy_enabled:
		return true
	
	if current_energy >= energy_threshold:
		current_energy -= energy_per_thrust
		update_energy(current_energy, max_energy)
		return true
	else:
		return false

## Recover energy over time
func recover_energy(delta: float, touching_wall: bool = false):
	if not energy_enabled:
		return
	
	# Track if we're getting wall bonus
	wall_recovery_active = touching_wall

	var desperation_mult := 1.0
	if desperation_enabled and max_health > 0.0:
		var health_ratio := current_health / max_health
		if health_ratio < desperation_threshold:
			var t := 1.0 - (health_ratio / desperation_threshold)
			desperation_mult = lerp(1.0, desperation_max_multiplier, t)

	var recovery = energy_recovery_rate * desperation_mult * delta
	if touching_wall:
		recovery += energy_wall_bonus * delta
	
	current_energy = min(max_energy, current_energy + recovery)
	update_energy(current_energy, max_energy)

	# Sound: play while wall recovery is active and energy isn't full; stop otherwise
	if sfx_energy_charge:
		var should_play = wall_recovery_active and current_energy < max_energy
		if should_play and not sfx_energy_charge.playing:
			sfx_energy_charge.play()
		elif not should_play and sfx_energy_charge.playing:
			sfx_energy_charge.stop()

## Check if player can thrust (has enough energy)
func can_thrust() -> bool:
	if not energy_enabled:
		return true
	return current_energy >= energy_threshold

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
	for i in 3:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(12, 12)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		container.add_child(tr)
		icons_out.append(tr)
	return container

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
		var ammo := AlienTechManager.phase_shifter_ammo
		var max_ammo := AlienTechManager.PHASE_SHIFTER_MAX_AMMO
		var recharging := AlienTechManager.phase_shifter_recharging
		if recharging:
			label.text = "Phase Shifter --/%d" % max_ammo
		else:
			label.text = "Phase Shifter %d/%d" % [ammo, max_ammo]
		label.modulate = tech.get("color", Color.WHITE)
		if cooldown_bar:
			cooldown_bar.visible = true
	elif tech.get("id", "") == AlienTechRegistry.POWERUP_REPLICATOR:
		var slots_state := AlienTechManager.powerup_replicator_slots
		var selected := AlienTechManager.powerup_replicator_selected
		label.text = tech.get("slot_label", tech.get("name", "?"))
		label.modulate = tech.get("color", Color.WHITE)
		if cooldown_bar:
			cooldown_bar.visible = false
		if rpl_container and rpl_icons.size() == 3:
			var filled_count := 0
			for i in 3:
				var ir: TextureRect = rpl_icons[i]
				var st: int = slots_state[i]
				if st >= 0 and st < _powerup_icons.size():
					ir.texture = _powerup_icons[st]
					ir.modulate = Color.WHITE if i == selected else Color(0.5, 0.5, 0.5, 1.0)
					ir.visible = true
					filled_count += 1
				else:
					ir.visible = false
			rpl_container.visible = filled_count > 0
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

func _get_slot_bar_value(slot_index: int) -> float:
	var tech := AlienTechManager.slots[slot_index]
	if tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		if AlienTechManager.phase_shifter_recharging:
			return 1.0 - (AlienTechManager.phase_shifter_recharge_timer / AlienTechManager.PHASE_SHIFTER_RECHARGE_TIME)
		return float(AlienTechManager.phase_shifter_ammo) / float(AlienTechManager.PHASE_SHIFTER_MAX_AMMO)
	return 1.0 - AlienTechManager.get_cooldown_ratio(slot_index)

func freeze_timer():
	_timer_active = false

func _is_slot_dimmed(slot_index: int) -> bool:
	var tech := AlienTechManager.slots[slot_index]
	if tech.get("id", "") == AlienTechRegistry.PHASE_SHIFTER:
		return AlienTechManager.phase_shifter_recharging
	if tech.get("id", "") == AlienTechRegistry.POWERUP_REPLICATOR:
		var sel := AlienTechManager.powerup_replicator_selected
		return AlienTechManager.powerup_replicator_slots[sel] < 0
	return AlienTechManager.get_cooldown_ratio(slot_index) > 0.0
