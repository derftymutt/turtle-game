extends Node2D
class_name TrashSequence

## Spawns and manages sequences of trash items
## Awards powerup when all trash in sequence is destroyed

signal sequence_completed(spawn_position)
signal sequence_failed()

# Sequence configuration
@export var trash_item_scene: PackedScene
@export var powerup_scene: PackedScene

# Spawn settings
@export_group("Sequence Settings")
@export var items_in_sequence: int = 5
@export var spawn_interval: float = 0.4  # Time between spawning each item
@export var sequence_timeout: float = 20.0  # Max time to complete sequence

# Movement patterns
enum PatternType {
	STRAIGHT,      # Simple horizontal line
	WAVE,          # Sine wave pattern (Gradius-style)
	DIAGONAL,      # Angled descent
}

@export var pattern: PatternType = PatternType.STRAIGHT
@export var spawn_side: String = "right"  # "right" or "left" - which side trash enters from

# Drift speed
@export_group("Movement")
@export var drift_speed: float = 80.0  # Horizontal drift speed (pixels per second)

# Pattern parameters
@export_group("Pattern Parameters")
@export var wave_amplitude: float = 20.0  # Height of wave oscillation
@export var wave_frequency: float = 5.0  # How many complete waves across screen
@export var wave_center_y: float = 20.0  # Y position of wave center (0 = screen center)
@export var wave_y_variation: float = 30.0  # Random Y offset range (+/- this value)
@export var diagonal_angle: float = 30.0  # Angle for diagonal pattern

# Spawn position
@export_group("Spawn Position")
@export var spawn_y_min: float = -50.0  # Top of spawn range
@export var spawn_y_max: float = 100.0   # Bottom of spawn range
@export var spawn_x_offset: float = 350.0  # How far off-screen to start

# Powerup settings
@export_group("Reward")
@export var powerup_type: Powerup.PowerupType = Powerup.PowerupType.SHIELD

# Internal state
var sequence_id: int = 0
var trash_items: Array[TrashItem] = []
var items_destroyed: int = 0
var is_active: bool = false
var spawn_timer: float = 0.0
var items_spawned: int = 0
var timeout_timer: float = 0.0
var wave_y_offset: float = 0.0  # Random Y offset for this sequence's wave

func _ready():
	add_to_group("trash_sequences")

func _process(delta):
	if not is_active:
		return
	
	# Spawn items over time
	if items_spawned < items_in_sequence:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			spawn_trash_item(items_spawned)
			items_spawned += 1
	
	# Track timeout
	timeout_timer += delta
	if timeout_timer >= sequence_timeout:
		fail_sequence()

## Start spawning a new sequence
func start_sequence():
	if is_active:
		push_warning("TrashSequence: Sequence already active!")
		return
	
	# Reset state
	is_active = true
	sequence_id += 1
	trash_items.clear()
	items_destroyed = 0
	items_spawned = 0
	spawn_timer = 0.0
	timeout_timer = 0.0
	
	# Random Y offset for wave pattern variety
	wave_y_offset = randf_range(-wave_y_variation, wave_y_variation)
	
	print("🗑️ Starting trash sequence #", sequence_id, " (", items_in_sequence, " items)")

func spawn_trash_item(index: int):
	"""Spawn a single trash item at calculated position"""
	if not trash_item_scene:
		push_error("TrashSequence: No trash_item_scene assigned!")
		return
	
	var trash = trash_item_scene.instantiate()
	
	# Calculate spawn position based on pattern
	var spawn_pos = calculate_spawn_position(index)
	trash.global_position = spawn_pos
	
	# Calculate drift direction based on spawn side
	var drift_direction = -1.0 if spawn_side == "right" else 1.0
	trash.drift_speed = Vector2(drift_direction * drift_speed, 0)
	
	# Enable wave motion for WAVE pattern (BEFORE adding to tree!)
	if pattern == PatternType.WAVE:
		trash.use_wave_motion = true
		trash.wave_amplitude = wave_amplitude
		trash.wave_frequency = wave_frequency
	
	# NOW add to scene tree (this calls _ready())
	get_parent().add_child(trash)
	
	# Set sequence ID
	trash.set_sequence_id(sequence_id)
	
	# Connect signal
	trash.trash_destroyed.connect(_on_trash_destroyed)
	
	# Add to tracking
	trash_items.append(trash)

func calculate_spawn_position(index: int) -> Vector2:
	"""Calculate position based on pattern type"""
	var base_x = spawn_x_offset if spawn_side == "right" else -spawn_x_offset
	var base_y = lerp(spawn_y_min, spawn_y_max, 0.5)  # Center by default
	var t = float(index) / max(1, items_in_sequence - 1)  # 0 to 1
	
	match pattern:
		PatternType.STRAIGHT:
			# Horizontal line at center height
			return Vector2(base_x, base_y)
		
		PatternType.WAVE:
			# Spawn at wave center with random Y variation
			return Vector2(base_x, wave_center_y + wave_y_offset)
		
		PatternType.DIAGONAL:
			# Angled line from top to bottom
			var angle_rad = deg_to_rad(diagonal_angle)
			var offset_y = t * (spawn_y_max - spawn_y_min)
			var offset_x = tan(angle_rad) * offset_y
			return Vector2(base_x + offset_x, spawn_y_min + offset_y)
	
	return Vector2(base_x, base_y)

func _on_trash_destroyed(trash: TrashItem):
	"""Track when trash items are destroyed"""
	if not is_active:
		return
	
	# Only count if it's part of current sequence
	if trash.sequence_id != sequence_id:
		return
	
	items_destroyed += 1
	print("  ✓ Trash destroyed: ", items_destroyed, "/", items_in_sequence)
	
	# Check if sequence is complete
	if items_destroyed >= items_in_sequence:
		complete_sequence(trash.global_position)

func complete_sequence(last_position: Vector2):
	"""All trash destroyed - spawn powerup!"""
	is_active = false
	
	print("✨ Sequence completed! Spawning powerup at ", last_position)
	
	# Spawn powerup at last trash location
	spawn_powerup(last_position)
	
	# Emit signal
	sequence_completed.emit(last_position)
	
	# Clean up
	cleanup_trash()

func fail_sequence():
	"""Sequence failed (timeout or incomplete)"""
	if not is_active:
		return
	
	is_active = false
	
	print("❌ Sequence failed (timeout or missed trash)")
	
	# Emit signal
	sequence_failed.emit()
	
	# Clean up remaining trash
	cleanup_trash()

func spawn_powerup(position: Vector2):
	"""Spawn the reward powerup"""
	if not powerup_scene:
		push_error("TrashSequence: No powerup_scene assigned!")
		return
	
	var powerup = powerup_scene.instantiate()
	get_parent().add_child(powerup)
	powerup.global_position = position
	powerup.powerup_type = powerup_type
	
	var powerup_sprite = powerup.get_node_or_null("AnimatedSprite2D")
	if powerup_sprite:
		if powerup_sprite is AnimatedSprite2D:
			if powerup_type == Powerup.PowerupType.SHIELD:
				powerup_sprite.play("shield")
			elif powerup_type == Powerup.PowerupType.AIR_RESERVE:
				powerup_sprite.play("air")
			elif powerup_type == Powerup.PowerupType.STAMINA_FREEZE:
				powerup_sprite.play("stamina")
	
	
	
	print("🎁 Powerup spawned: ", Powerup.PowerupType.keys()[powerup_type])

func cleanup_trash():
	"""Remove any remaining trash items from this sequence"""
	for trash in trash_items:
		if trash and is_instance_valid(trash) and not trash.is_destroyed:
			trash.despawn_quietly()
	
	trash_items.clear()

## Public method to manually trigger a sequence
func trigger_sequence(
	pattern_type: PatternType = PatternType.STRAIGHT,
	item_count: int = 5,
	reward_type: Powerup.PowerupType = Powerup.PowerupType.SHIELD
):
	"""Trigger a sequence with custom parameters"""
	pattern = pattern_type
	items_in_sequence = item_count
	powerup_type = reward_type
	start_sequence()
