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

# Alien Tech slot UI
var _tech_slots := TechSlotUI.new()

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
## Off in the Academy, which has no trash bags (tech pickups are disabled there).
@export var score_clusters_enabled: bool = true
@export var freebie_first_delay: float = 30.0       # first freebie fires around here...
@export var freebie_first_jitter: float = 8.0       # ...give or take this much
@export var freebie_interval: float = 60.0          # then roughly this often after that...
@export var freebie_interval_jitter: float = 15.0   # ...give or take this much

func _ready():
	add_to_group("hud")
	# Saved hidden in level_base.tscn so it doesn't cover the level in the editor
	visible = true
	
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
	update_hearts(_hearts.max_hearts * 2, _hearts.max_hearts)  # full, rainbow hearts included
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

	# Alien Tech slot UI
	_tech_slots.build(self)
	AlienTechManager.piece_collected.connect(_tech_slots.on_tech_piece_collected)
	AlienTechManager.tech_slots_changed.connect(_tech_slots.on_tech_slots_changed)
	AlienTechManager.phase_shifter_ammo_changed.connect(_tech_slots.on_phase_shifter_ammo_changed)
	AlienTechManager.powerup_replicator_changed.connect(_tech_slots.on_powerup_replicator_changed)
	_tech_slots.refresh()

func _process(delta):
	# Air warning pulse (hud_container/danger_overlay tint) and the air bar's
	# one-shot flash for the air-reserve powerup.
	_air.process(self, delta)

	# Alien Tech slot UI: cooldown bars, label/icon state, hot fire text, key prompts
	_tech_slots.process(delta)

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

## A bonus trash bag right now, outside the score thresholds and the freebie
## timer — the reward for the puffin's skill shot.
func spawn_bonus_trash_cluster() -> void:
	_trash_clusters.spawn(self)

func add_score(points: int):
	update_score(current_score + points)

## Update the heart icons. `current` (HP) / `hearts_max` (icons) come from
## TurtlePlayer; rainbow hearts are read from GameManager.
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

func freeze_timer():
	timer_system.freeze()

## Rainbow Fish round countdown, centred between the tech slots. Called every
## frame by RainbowFishSpawner while a round runs. The digits cycle through
## the rainbow so it reads as part of the minigame — twice as fast in the last
## 10 seconds — and the box's border shows `target_color`, the colour of fish
## to free next. The cycle goes on font_color, not modulate, so it doesn't
## tint the border.
func show_rainbow_timer(seconds_left: float, target_color: Color) -> void:
	var label := _get_rainbow_timer_label()
	if not label:
		return
	label.visible = true
	var secs := int(ceil(seconds_left))
	label.text = "%d:%02d" % [secs / 60, secs % 60]
	var cycle_rate := 1.0 if seconds_left > 10.0 else 2.0
	var hue := fmod(Time.get_ticks_msec() * 0.001 * cycle_rate, 1.0)
	label.add_theme_color_override("font_color", Color.from_hsv(hue, 0.75, 1.0))
	_rainbow_timer_box.border_color = target_color

## Quick pop when time is added: the label jumps up in size and flashes
## bright, then settles. Uses scale/self_modulate so it layers over the
## rainbow cycle show_rainbow_timer() drives through modulate.
func flash_rainbow_timer() -> void:
	var label := _get_rainbow_timer_label()
	if not label:
		return
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * 1.5
	label.self_modulate = Color(3.0, 3.0, 3.0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "self_modulate", Color.WHITE, 0.35)

func hide_rainbow_timer() -> void:
	var label := _get_rainbow_timer_label()
	if label:
		label.visible = false

var _rainbow_timer_label: Label = null
## The label's box, duplicated so recolouring its border never touches the
## scene's shared StyleBox
var _rainbow_timer_box: StyleBoxFlat = null

func _get_rainbow_timer_label() -> Label:
	if not _rainbow_timer_label:
		_rainbow_timer_label = find_child("RainbowTimerLabel") as Label
		if _rainbow_timer_label:
			_rainbow_timer_box = (_rainbow_timer_label.get_theme_stylebox("normal") as StyleBoxFlat).duplicate()
			_rainbow_timer_label.add_theme_stylebox_override("normal", _rainbow_timer_box)
	return _rainbow_timer_label
