extends CanvasLayer
class_name HUD

## Heads-Up Display for score, health, and experimental meters
## Breath and exhaustion systems are toggleable for prototyping

# References (will be found dynamically)
var score_label: Label
var health_bar: ProgressBar
var breath_container: Control
var breath_bar: ProgressBar
var exhaustion_container: Control
var exhaustion_bar: ProgressBar
var super_speed_indicator: Label
var hud_container: Control  # Container for flash effect

# Game state
var current_score: int = 0
var current_health: float = 100.0
var max_health: float = 100.0

## Get current score (used by game over screen)
func get_current_score() -> int:
	return current_score

# Breath system (experimental - toggleable)
@export_group("Breath System")
@export var breath_enabled: bool = true
@export var max_breath: float = 30.0
@export var breath_drain_rate: float = 1.0
@export var breath_refill_rate: float = 30.0
@export var breath_warning_threshold: float = 10.0
var current_breath: float = 30.0
var breath_warning: bool = false

# Exhaustion system (experimental - toggleable)
@export_group("Exhaustion System")
@export var exhaustion_enabled: bool = true
@export var max_exhaustion: float = 100.0
@export var exhaustion_per_thrust: float = 12.0
@export var exhaustion_recovery_rate: float = 15.0
@export var exhaustion_wall_bonus: float = 40.0
@export var exhaustion_threshold: float = 15.0
var current_exhaustion: float = 100.0
var is_touching_wall: bool = false
var wall_recovery_active: bool = false  # NEW: Track if we're actively recovering from wall

# Visual feedback
var breath_flash_timer: float = 0.0
var breath_flash_interval: float = 0.5
var hud_layer_flash_speed: float = 5.0
var exhaustion_pulse_timer: float = 0.0  # NEW: For wall recovery pulse
var exhaustion_pulse_speed: float = 8.0  # NEW: How fast the pulse is

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
	health_bar = find_child("HealthBar")
	breath_container = find_child("BreathContainer")
	breath_bar = find_child("BreathBar")
	exhaustion_container = find_child("ExhaustionContainer")
	exhaustion_bar = find_child("ExhaustionBar")
	super_speed_indicator = find_child("SuperSpeedIndicator")
	
	# Debug: verify we found everything
	if not score_label:
		push_warning("HUD: Could not find ScoreLabel!")
	if not health_bar:
		push_warning("HUD: Could not find HealthBar!")
	if not breath_bar:
		push_warning("HUD: Could not find BreathBar!")
	if not exhaustion_bar:
		push_warning("HUD: Could not find ExhaustionBar!")
	
	# Initialize displays
	update_score(0)
	update_health(max_health, max_health)
	update_breath(max_breath, max_breath)
	update_exhaustion(max_exhaustion, max_exhaustion)
	set_super_speed_active(false)
	
	# Hide experimental meters if disabled
	if breath_container:
		breath_container.visible = breath_enabled
	if exhaustion_container:
		exhaustion_container.visible = exhaustion_enabled
	
	#print("HUD initialized successfully!")

func _process(delta):
	# Handle breath warning flash - entire HUD layer pulses red
	if breath_warning and breath_enabled and hud_container:
		breath_flash_timer += delta * hud_layer_flash_speed
		var pulse = (sin(breath_flash_timer) + 1.0) / 2.0
		var warning_color = Color.WHITE.lerp(Color(1.0, 0.3, 0.3, 1.0), pulse)
		hud_container.modulate = warning_color
		
		if breath_bar:
			breath_bar.modulate = Color.CYAN
	else:
		if hud_container:
			hud_container.modulate = Color.WHITE
		breath_flash_timer = 0.0
	
	# NEW: Handle wall recovery visual feedback
	if wall_recovery_active and exhaustion_bar:
		exhaustion_pulse_timer += delta * exhaustion_pulse_speed
		
		# Pulse between current color and bright cyan
		var pulse = (sin(exhaustion_pulse_timer) + 1.0) / 2.0
		
		# Get the base color (green/yellow/red based on exhaustion level)
		var base_color = Color.GREEN
		var exhaustion_ratio = current_exhaustion / max_exhaustion
		if exhaustion_ratio <= 0.2:
			base_color = Color.RED
		elif exhaustion_ratio <= 0.5:
			base_color = Color.YELLOW
		
		# Pulse to bright cyan to indicate wall recovery
		var recovery_color = base_color.lerp(Color.CYAN, pulse * 0.7)
		exhaustion_bar.modulate = recovery_color
	else:
		exhaustion_pulse_timer = 0.0
		# Reset to normal color coding when not recovering from wall
		update_exhaustion(current_exhaustion, max_exhaustion)

## Update score display
func update_score(new_score: int):
	current_score = new_score
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

## Update breath display
func update_breath(breath: float, max_br: float):
	if not breath_enabled:
		return
	
	current_breath = breath
	max_breath = max_br
	
	if breath_bar:
		breath_bar.max_value = max_br
		breath_bar.value = breath
		
		# Warning state
		if breath <= breath_warning_threshold:
			if not breath_warning:
				breath_warning = true
				breath_flash_timer = 0.0
		else:
			breath_warning = false
			breath_bar.modulate = Color.CYAN

## Drain breath while underwater
func drain_breath(delta: float):
	if not breath_enabled:
		return
	
	current_breath = max(0.0, current_breath - breath_drain_rate * delta)
	update_breath(current_breath, max_breath)
	
	# Return true if out of breath (for damage/warning)
	return current_breath <= 0.0

## Refill breath at surface
func refill_breath(delta: float):
	if not breath_enabled:
		return
	
	current_breath = min(max_breath, current_breath + breath_refill_rate * delta)
	update_breath(current_breath, max_breath)

## Update exhaustion display
func update_exhaustion(exhaustion: float, max_ex: float):
	if not exhaustion_enabled:
		return
	
	current_exhaustion = exhaustion
	max_exhaustion = max_ex
	
	if exhaustion_bar:
		exhaustion_bar.max_value = max_ex
		exhaustion_bar.value = exhaustion
		
		# Only update color if NOT actively recovering from wall
		# (wall recovery has its own pulsing color in _process)
		if not wall_recovery_active:
			# Color code exhaustion bar
			if exhaustion / max_ex > 0.5:
				exhaustion_bar.modulate = Color.GREEN
			elif exhaustion / max_ex > 0.2:
				exhaustion_bar.modulate = Color.YELLOW
			else:
				exhaustion_bar.modulate = Color.RED

## Try to use exhaustion for a thrust
func try_thrust() -> bool:
	if not exhaustion_enabled:
		return true
	
	if current_exhaustion >= exhaustion_threshold:
		current_exhaustion -= exhaustion_per_thrust
		update_exhaustion(current_exhaustion, max_exhaustion)
		return true
	else:
		return false

## Recover exhaustion over time
func recover_exhaustion(delta: float, touching_wall: bool = false):
	if not exhaustion_enabled:
		return
	
	# Track if we're getting wall bonus
	var was_wall_recovery = wall_recovery_active
	wall_recovery_active = touching_wall
	
	var recovery = exhaustion_recovery_rate * delta
	if touching_wall:
		recovery += exhaustion_wall_bonus * delta
	
	current_exhaustion = min(max_exhaustion, current_exhaustion + recovery)
	update_exhaustion(current_exhaustion, max_exhaustion)

## Check if player can thrust
func can_thrust() -> bool:
	if not exhaustion_enabled:
		return true
	return current_exhaustion >= exhaustion_threshold

## Update super speed indicator
func set_super_speed_active(active: bool):
	if super_speed_indicator:
		super_speed_indicator.visible = active
		if active:
			var tween = create_tween().set_loops()
			tween.tween_property(super_speed_indicator, "modulate:a", 0.3, 0.3)
			tween.tween_property(super_speed_indicator, "modulate:a", 1.0, 0.3)
