extends CanvasLayer
class_name HUD

## Heads-Up Display for score, health, and experimental meters
## Air and energy systems are toggleable for prototyping

# References (will be found dynamically)
var score_label: Label
var ufo_pieces_label: Label
var health_bar: ProgressBar
var air_container: Control
var air_bar: ProgressBar
var energy_container: Control
var energy_bar: ProgressBar
var super_speed_indicator: Label
var hud_container: Control  # Container for flash effect

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
var current_energy: float = 100.0
var is_touching_wall: bool = false
var wall_recovery_active: bool = false  # NEW: Track if we're actively recovering from wall

# Visual feedback
var air_flash_timer: float = 0.0
var air_flash_interval: float = 0.5
var hud_layer_flash_speed: float = 5.0
var energy_pulse_timer: float = 0.0  # NEW: For wall recovery pulse
var energy_pulse_speed: float = 8.0  # NEW: How fast the pulse is

func _ready():
	add_to_group("hud")
	
	# Find the main container
	for child in get_children():
		if child is Control:
			hud_container = child
			break
	
	if not hud_container:
		push_warning("HUD: Could not find container Control node! Flash effect won't work.")
	
	# Find UI nodes dynamically
	score_label = find_child("ScoreLabel")
	ufo_pieces_label = find_child("UFOPiecesLabel")
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

func _process(delta):
	# Handle air warning flash - entire HUD layer pulses red
	if air_warning and air_enabled and hud_container:
		air_flash_timer += delta * hud_layer_flash_speed
		var pulse = (sin(air_flash_timer) + 1.0) / 2.0
		var warning_color = Color.WHITE.lerp(Color(1.0, 0.3, 0.3, 1.0), pulse)
		hud_container.modulate = warning_color
		
		if air_bar:
			air_bar.modulate = Color.CYAN
	else:
		if hud_container:
			hud_container.modulate = Color.WHITE
		air_flash_timer = 0.0
	
	# Handle wall recovery visual feedback
	if wall_recovery_active and energy_bar:
		energy_pulse_timer += delta * energy_pulse_speed
		
		# Pulse between current color and bright cyan
		var pulse = (sin(energy_pulse_timer) + 1.0) / 2.0
		
		# Get the base color (green/yellow/red based on energy level)
		var base_color = Color.GREEN
		var energy_ratio = current_energy / max_energy
		if energy_ratio <= 0.2:
			base_color = Color.RED
		elif energy_ratio <= 0.5:
			base_color = Color.YELLOW
		
		# Pulse to bright cyan to indicate wall recovery
		var recovery_color = base_color.lerp(Color.CYAN, pulse * 0.7)
		energy_bar.modulate = recovery_color
	else:
		energy_pulse_timer = 0.0
		# Reset to normal color coding when not recovering from wall
		update_energy(current_energy, max_energy)

## Update score display
func update_score(new_score: int):
	current_score = new_score
	GameManager.current_score = new_score 
	if score_label:
		score_label.text = "Score: %d" % current_score

func add_score(points: int):
	update_score(current_score + points)

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
		else:
			air_warning = false
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
				energy_bar.modulate = Color.GREEN
			elif energy / max_en > 0.2:
				energy_bar.modulate = Color.YELLOW
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
	var was_wall_recovery = wall_recovery_active
	wall_recovery_active = touching_wall
	
	var recovery = energy_recovery_rate * delta
	if touching_wall:
		recovery += energy_wall_bonus * delta
	
	current_energy = min(max_energy, current_energy + recovery)
	update_energy(current_energy, max_energy)

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
		ufo_pieces_label.text = "UFO Pieces: %d/%d" % [collected, needed]
		
		# Color code: green when complete, white otherwise
		if collected >= needed and needed > 0:
			ufo_pieces_label.modulate = Color.GREEN
		else:
			ufo_pieces_label.modulate = Color.WHITE

## Signal handlers for LevelManager
func _on_piece_delivered(collected: int, needed: int):
	"""Called when a piece is delivered to the workshop"""
	update_ufo_pieces(collected, needed)

func _on_level_started(level_number: int):
	"""Called when a new level starts - reset piece counter"""
	# LevelManager will emit piece_delivered signal with initial 0/x values
	# so we don't need to do anything here
	pass
