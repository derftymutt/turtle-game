extends Node2D
class_name TrashSequenceSpawner

## Periodically spawns trash sequences throughout the game
## Manages timing, difficulty progression, and variety

@export var trash_sequence_scene: PackedScene

# Spawn timing
@export_group("Timing")
@export var auto_spawn: bool = true
@export var spawn_interval_min: float = 8.0
@export var spawn_interval_max: float = 15.0
@export var first_spawn_delay: float = 3.0  # Initial delay before first sequence

# Difficulty settings
@export_group("Difficulty")
@export var start_with_easy: bool = true  # First few sequences are easier
@export var easy_sequence_count: int = 2  # How many easy sequences before normal
@export var min_items_per_sequence: int = 3
@export var max_items_per_sequence: int = 5

# Pattern variety
@export_group("Patterns")
@export var use_random_patterns: bool = true
@export var available_patterns: Array[TrashSequence.PatternType] = [
	TrashSequence.PatternType.STRAIGHT,
	TrashSequence.PatternType.WAVE,
	TrashSequence.PatternType.DIAGONAL,
]

# Powerup variety
@export_group("Powerups")
@export var use_random_powerups: bool = true
@export var available_powerups: Array[Powerup.PowerupType] = [
	Powerup.PowerupType.SHIELD,
	Powerup.PowerupType.AIR_RESERVE,
	Powerup.PowerupType.STAMINA_FREEZE,
]

# Movement settings
@export_group("Movement")
@export var default_drift_speed: float = 50.0  # Default horizontal drift speed
@export var randomize_drift_speed: bool = false
@export var drift_speed_min: float = 50.0  # Min speed if randomizing
@export var drift_speed_max: float = 100.0  # Max speed if randomizing

# Internal state
var spawn_timer: float = 0.0
var next_spawn_time: float = 0.0
var sequences_spawned: int = 0
var active_sequence: TrashSequence = null

func _ready():
	add_to_group("trash_spawners")
	
	if auto_spawn:
		# Set initial spawn delay
		next_spawn_time = first_spawn_delay
		print("🗑️ TrashSequenceSpawner ready - first spawn in ", first_spawn_delay, "s")

func _process(delta):
	if not auto_spawn:
		return
	
	spawn_timer += delta
	
	if spawn_timer >= next_spawn_time:
		spawn_timer = 0.0
		spawn_sequence()
		
		# Randomize next spawn time
		next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)

func spawn_sequence():
	"""Spawn a new trash sequence"""
	if not trash_sequence_scene:
		push_error("TrashSequenceSpawner: No trash_sequence_scene assigned!")
		return
	
	# Don't spawn if there's already an active sequence
	if active_sequence and is_instance_valid(active_sequence) and active_sequence.is_active:
		print("⏭️ Skipping spawn - sequence already active")
		return
	
	# Create sequence node
	var sequence = trash_sequence_scene.instantiate()
	add_child(sequence)
	active_sequence = sequence
	
	# Determine difficulty
	var is_easy = start_with_easy and sequences_spawned < easy_sequence_count
	var item_count = get_item_count(is_easy)
	
	# Choose pattern
	var pattern = choose_pattern(is_easy)
	
	# Choose powerup
	var powerup = choose_powerup()
	
	# Choose spawn side
	sequence.spawn_side = "right" if randf() > 0.5 else "left"
	
	# Set drift speed
	if randomize_drift_speed:
		sequence.drift_speed = randf_range(drift_speed_min, drift_speed_max)
	else:
		sequence.drift_speed = default_drift_speed
	
	# Connect signals
	sequence.sequence_completed.connect(_on_sequence_completed)
	sequence.sequence_failed.connect(_on_sequence_failed)
	
	# Start the sequence
	sequence.trigger_sequence(pattern, item_count, powerup)
	
	sequences_spawned += 1
	print("📢 Spawned sequence #", sequences_spawned, " - ", item_count, " items, ", TrashSequence.PatternType.keys()[pattern])

func get_item_count(is_easy: bool) -> int:
	"""Determine how many items in sequence"""
	if is_easy:
		return min_items_per_sequence
	else:
		return randi_range(min_items_per_sequence, max_items_per_sequence)

func choose_pattern(is_easy: bool) -> TrashSequence.PatternType:
	"""Choose a pattern type"""
	if is_easy:
		# Easy sequences use simple patterns
		return available_patterns.pick_random()
	
	if use_random_patterns and available_patterns.size() > 0:
		return available_patterns.pick_random()
	else:
		return TrashSequence.PatternType.STRAIGHT

func choose_powerup() -> Powerup.PowerupType:
	"""Choose which powerup to award"""
	
	if use_random_powerups and available_powerups.size() > 0:
		return available_powerups.pick_random()
	else:
		return Powerup.PowerupType.SHIELD

func _on_sequence_completed(spawn_position: Vector2):
	"""Sequence was successfully completed"""
	print("✅ Spawner: Sequence completed!")

func _on_sequence_failed():
	"""Sequence failed"""
	print("⚠️ Spawner: Sequence failed")

## Manually trigger a sequence (for testing or scripted events)
func trigger_manual_sequence(
	pattern: TrashSequence.PatternType = TrashSequence.PatternType.WAVE,
	item_count: int = 5,
	powerup: Powerup.PowerupType = Powerup.PowerupType.SHIELD
):
	"""Manually spawn a specific sequence"""
	if not trash_sequence_scene:
		push_error("TrashSequenceSpawner: No trash_sequence_scene assigned!")
		return
	
	var sequence = trash_sequence_scene.instantiate()
	add_child(sequence)
	active_sequence = sequence
	
	sequence.sequence_completed.connect(_on_sequence_completed)
	sequence.sequence_failed.connect(_on_sequence_failed)
	
	sequence.trigger_sequence(pattern, item_count, powerup)
