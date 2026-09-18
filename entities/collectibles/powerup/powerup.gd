extends RigidBody2D
class_name Powerup

## Powerup that spawns when trash sequence is completed
## Sinks gradually to ocean floor, can be collected by player

signal powerup_collected(powerup_type)

# Powerup type enum
enum PowerupType {
	SHIELD,          # Temporary invincibility
	AIR_RESERVE,     # Extra breath capacity
	ENERGY_ENDLESS,  # Pause stamina drain
	RAPID_FIRE,      # Faster shooting
	RANDOM,          # Randomly picks one of the above on collection
}

# Properties
@export var powerup_type: PowerupType = PowerupType.SHIELD
@export var sink_speed: float = 60.0
@export var sway_amount: float = 20.0
@export var sway_speed: float = 1.2

# Visual feedback
@export var glow_amount: float = 0.3  # Brightness pulsing
@export var glow_speed: float = 2.0
@export var rotation_speed: float = 1.5  # Gentle spin

# Lifetime
@export var floor_lifetime: float = 12.0  # How long it stays on floor before despawning
@export var disable_floor_despawn: bool = false

# Below this speed (px/s) the powerup counts as resting and its sprite stops
# spinning. Sinking speed is ~40-60 px/s, so this only trips once it has landed.
const REST_SPEED: float = 8.0

# Internal state
var ocean: Ocean = null
var collected: bool = false
var despawning: bool = false
var glow_offset: float = 0.0
var sway_offset: float = 0.0
var visual_node: Node2D = null
var on_floor: bool = false
var floor_timer: float = 0.0

# True while this powerup's process_mode was force-set to ALWAYS because it was
# born (as a trash-sequence reward) while Time Freeze was active. Its parent
# TrashSequenceSpawner is PROCESS_MODE_DISABLED during the freeze, and children
# inherit that — which would silently pull this body out of physics simulation
# entirely, so its Area2D could never detect the player. Reverted once the
# freeze ends (see _physics_process).
var _process_mode_forced_for_freeze: bool = false

func _ready():
	# Physics setup - sinks like valuable collectibles
	gravity_scale = 0.2
	linear_damp = 5.0
	angular_damp = 3.0
	mass = 0.5

	if AlienTechManager.time_freeze_active:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_process_mode_forced_for_freeze = true
	
	# Collision setup
	# NOTE: Set in Inspector:
	# - Collision Layer: 2 (collectibles)
	# - Collision Mask: 1 (world)
	
	# High z-index for visibility
	z_index = 100
	
	# Find ocean system
	ocean = get_tree().get_first_node_in_group("ocean")
	add_to_group("collectibles")
	add_to_group("powerups")
	
	# Random starting offsets
	glow_offset = randf() * TAU
	sway_offset = randf() * TAU
	
	# Store visual node
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")

	# Spawners set powerup_type before this node enters the tree, but the sprite's
	# autoplay ("shield") fires on entering it and overwrites any animation they
	# played beforehand — so pick the icon here, after autoplay has run.
	if visual_node is AnimatedSprite2D:
		visual_node.play(_animation_for_type(powerup_type))

	# Connect Area2D for player detection
	# NOTE: Area2D collision MUST be set in Inspector:
	# - Collision Layer: 0 (nothing)
	# - Collision Mask: 1 (player)
	var area = get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("Powerup: No Area2D child found!")

func _physics_process(delta):
	if collected or despawning:
		return

	if _process_mode_forced_for_freeze:
		if not AlienTechManager.time_freeze_active:
			# Freeze ended — go back to respecting normal pause/scene rules.
			process_mode = Node.PROCESS_MODE_INHERIT
			_process_mode_forced_for_freeze = false
		else:
			# Still frozen: stay put like every other frozen object (no sink/sway/
			# despawn-timer progress), but keep processing so this check — and the
			# Area2D pickup below — keep working.
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0
			return

	# Check if on floor
	var is_near_floor = global_position.y > 160
	var is_mostly_still = linear_velocity.length() < 50
	
	if is_near_floor and is_mostly_still:
		if not on_floor:
			on_floor = true
			floor_timer = 0.0
		
		if not disable_floor_despawn:
			floor_timer += delta
			if floor_timer >= floor_lifetime:
				despawning = true
				start_despawn()
				return
	else:
		on_floor = false
		floor_timer = 0.0
	
	# Apply sinking and swaying
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0 and depth < 160:
			# Sink downward
			apply_central_force(Vector2(0, sink_speed))
			
			# Sway side to side
			sway_offset += sway_speed * delta
			var sway_force = sin(sway_offset) * sway_amount
			apply_central_force(Vector2(sway_force, 0))
	
	# Visual effects
	animate_powerup(delta)

func animate_powerup(delta: float):
	"""Create attractive glowing/spinning effect"""
	if not visual_node:
		return
	
	# Pulsing glow
	glow_offset += glow_speed * delta
	var glow = 1.0 + (sin(glow_offset) * glow_amount)
	visual_node.modulate = Color(glow, glow, glow, 1.0)
	
	# Gentle rotation while drifting/sinking — spin the sprite only, never the
	# body. Forcing rotation on the RigidBody2D turns its square collider into a
	# wheel that "walks" along the sea floor, so powerups all crawled into the
	# same corner. The spin stops once the body has come to rest so it visibly
	# sits still. (Not gated on on_floor: that needs y > 160, but real floors
	# hold a powerup's center a few px above that.)
	if linear_velocity.length() > REST_SPEED:
		visual_node.rotation += rotation_speed * delta

func _on_area_body_entered(body: Node2D):
	if body.is_in_group("player") and not collected:
		collect(body)

func collect(collector):
	"""Collect powerup and apply effect to player"""
	if collected:
		return
	
	collected = true
	$SfxCollect.play()
	set_deferred("freeze", true)  # from the pickup Area2D's body_entered — see BaseCollectible.collect()

	# Resolve RANDOM to an actual powerup type at collection time
	var resolved_type = powerup_type
	if powerup_type == PowerupType.RANDOM:
		var base_types = [
			PowerupType.SHIELD,
			PowerupType.AIR_RESERVE,
			PowerupType.ENERGY_ENDLESS,
			PowerupType.RAPID_FIRE,
		]
		resolved_type = base_types.pick_random()
		print("🎲 RANDOM powerup resolved to: ", PowerupType.keys()[resolved_type])

	# GIANT FLASH for visibility
	print("💥💥💥 POWERUP COLLECTED: ", PowerupType.keys()[resolved_type], " 💥💥💥")

	# Emit signal with resolved powerup type
	powerup_collected.emit(resolved_type)

	# Apply powerup effect to player
	if collector.has_method("apply_powerup"):
		collector.apply_powerup(resolved_type)
	else:
		push_error("⚠️ Player doesn't have apply_powerup method! Powerup NOT applied!")

	# For RANDOM: swap to the resolved sprite first
	if powerup_type == PowerupType.RANDOM and visual_node is AnimatedSprite2D:
		match resolved_type:
			PowerupType.SHIELD:         visual_node.play("shield")
			PowerupType.AIR_RESERVE:    visual_node.play("air")
			PowerupType.ENERGY_ENDLESS: visual_node.play("energy")
			PowerupType.RAPID_FIRE:     visual_node.play("rapid_fire")

	# Reset modulate so the sprite art is visible during the zoom
	if visual_node:
		visual_node.modulate = Color.WHITE

	# Fly to player (runs concurrently with scale)
	var move_tween = create_tween()
	move_tween.tween_property(self, "global_position", collector.global_position, 0.15)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# Sequential scale: up then down — the down step starts from wherever up left off,
	# avoiding the snap-back-to-1 glitch that happened with a delayed parallel tween
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", Vector2.ONE * 4.0, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", Vector2.ZERO, 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	scale_tween.finished.connect(queue_free)

func start_despawn():
	"""Despawn powerup after timeout"""
	collected = true
	freeze = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Sink into floor
	tween.tween_property(self, "global_position:y", global_position.y + 30, 1.5)
	
	# Shrink
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), 1.5)
	
	tween.finished.connect(queue_free)

func _animation_for_type(type: PowerupType) -> StringName:
	match type:
		PowerupType.AIR_RESERVE:
			return &"air"
		PowerupType.ENERGY_ENDLESS:
			return &"energy"
		PowerupType.RAPID_FIRE:
			return &"rapid_fire"
		PowerupType.RANDOM:
			return &"random"
		_:
			return &"shield"

## Get powerup type name for display
func get_powerup_name() -> String:
	match powerup_type:
		PowerupType.SHIELD:
			return "Shield"
		PowerupType.AIR_RESERVE:
			return "Air Reserve"
		PowerupType.ENERGY_ENDLESS:
			return "Endless Energy"
		PowerupType.RAPID_FIRE:
			return "Rapid Fire"
		PowerupType.RANDOM:
			return "Random"
		_:
			return "Unknown"
