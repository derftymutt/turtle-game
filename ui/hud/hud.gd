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
var super_speed_indicator: Label  # New!
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
@export var max_breath: float = 30.0  # 30 seconds underwater
@export var breath_drain_rate: float = 1.0  # 1 breath per second
@export var breath_refill_rate: float = 30.0  # 30 breaths per second at surface
@export var breath_warning_threshold: float = 10.0  # Flash red below this
var current_breath: float = 30.0
var breath_warning: bool = false

# Exhaustion system (experimental - toggleable)
@export_group("Exhaustion System")
@export var exhaustion_enabled: bool = true
@export var max_exhaustion: float = 100.0
@export var exhaustion_per_thrust: float = 12.0  # Cost per thrust
@export var exhaustion_recovery_rate: float = 20.0  # Recovery per second when idle
@export var exhaustion_wall_bonus: float = 45.0  # Extra recovery per second touching wall
@export var exhaustion_threshold: float = 15.0  # Can't thrust below this
var current_exhaustion: float = 100.0
var is_touching_wall: bool = false

# Visual feedback
var breath_flash_timer: float = 0.0
var breath_flash_interval: float = 0.5
var hud_layer_flash_speed: float = 5.0  # How fast the HUD pulses (higher = faster)

func _ready():
	# Add to group for easy lookup
	add_to_group("hud")
	
	# Find the main container (usually a VBoxContainer or HBoxContainer at the root)
	# This will be what we modulate for the flash effect
	for child in get_children():
		if child is Control:
			hud_container = child
			break
	
	if not hud_container:
		push_warning("HUD: Could not find container Control node! Flash effect won't work.")
	
	# Find UI nodes dynamically (works with VBox or HBox)
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
	
	print("HUD initialized successfully!")

func _process(delta):
	# Handle breath warning flash - entire HUD layer pulses red
	if breath_warning and breath_enabled and hud_container:
		breath_flash_timer += delta * hud_layer_flash_speed
		
		# Sine wave for smooth pulsing (0.0 to 1.0)
		var pulse = (sin(breath_flash_timer) + 1.0) / 2.0
		
		# Interpolate between normal white and red
		var warning_color = Color.WHITE.lerp(Color(1.0, 0.3, 0.3, 1.0), pulse)
		hud_container.modulate = warning_color
		
		# Keep breath bar cyan during flash for contrast
		if breath_bar:
			breath_bar.modulate = Color.CYAN
	else:
		# Reset to normal when not warning
		if hud_container:
			hud_container.modulate = Color.WHITE
		breath_flash_timer = 0.0

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
		return true  # Always allow if system disabled
	
	if current_exhaustion >= exhaustion_threshold:
		current_exhaustion -= exhaustion_per_thrust
		update_exhaustion(current_exhaustion, max_exhaustion)
		return true
	else:
		return false  # Too exhausted!

## Recover exhaustion over time
func recover_exhaustion(delta: float, touching_wall: bool = false):
	if not exhaustion_enabled:
		return
	
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
			# Flash effect
			var tween = create_tween().set_loops()
			tween.tween_property(super_speed_indicator, "modulate:a", 0.3, 0.3)
			tween.tween_property(super_speed_indicator, "modulate:a", 1.0, 0.3)
