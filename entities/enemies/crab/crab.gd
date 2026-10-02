extends BaseEnemy
class_name Crab

## Floor-dwelling enemy that throws projectiles at player
## Relocates to a new position when damaged (unless killed)

# Signals
signal ready_to_reproduce(crab: Crab)

# Projectile settings
@export var projectile_scene: PackedScene
@export var throw_cooldown: float = 1.0  # Time between throws
@export var throw_velocity: float = 280.0  # Base throw speed
@export var throw_arc_height: float = 0.2  # How much upward angle (0-1)
@export var detection_range: float = 150.0  # How far can detect player

# Floor positioning
@export var floor_y: float = 165.0  # Y position of floor (matches FloorSeeder)
@export var floor_min_x: float = -280.0
@export var floor_max_x: float = 280.0
@export var position_lock_strength: float = 80.0

# Relocation on damage
@export var relocation_distance_min: float = 10.0  # Min distance to move when hit
@export var relocation_distance_max: float = 50.0  # Max distance to move when hit
@export var relocation_speed: float = 500.0  # How fast to scuttle to new spot

# Spacing between crabs
@export var min_crab_spacing: float = 30.0  # Resting crabs are kept at least this far apart (x)
@export var separation_speed: float = 90.0  # How fast overlapping crabs slide apart (px/s)

# Visual
@export var idle_bob_amount: float = 1.0
@export var idle_bob_speed: float = 0.8
@export var is_super: bool = false

# Reproduction
@export var reproduce_threshold: float = 40.0  # Seconds til reproduce when not hit

# Internal state
enum State { IDLE, WINDUP, THROWING, RELOCATING }
var current_state: State = State.IDLE
var throw_timer: float = 0.0
var starting_position: Vector2
var relocation_target: Vector2
var bob_offset: float = 0.0
var player: Node2D = null
var ocean: Ocean = null

# Windup telegraph
const WINDUP_DURATION: float = 0.6
var _windup_timer: float = 0.0
var _windup_node: Node2D = null

# Reproduction tracking (private - use signals to access)
var _reproduce_timer: float = 0.0
var _has_reproduced: bool = false
var _reproduce_warning_particles: CPUParticles2D = null

const REPRODUCE_WARNING_TIME: float = 10.0

# Relocation timeout — prevents permanent RELOCATING invincibility if crab gets stuck
var _relocation_elapsed: float = 0.0
const RELOCATION_TIMEOUT: float = 3.0

func _enemy_ready():
	# Physics setup - stays put on floor
	gravity_scale = 0.0
	linear_damp = 15.0  # High damping to resist movement
	angular_damp = 5.0
	mass = 3.0  # Heavy
	lock_rotation = true
	
	# Set health — super crabs have 30 HP (3 shots), regular have 20 HP (2 shots)
	max_health = 30.0 if is_super else 20.0
	current_health = max_health
	contact_damage = 10.0
	death_label = "a crab"
	
	# Find references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Store starting position
	starting_position = global_position
	
	# Random starting offsets for variety
	bob_offset = randf() * TAU
	throw_timer = randf() * throw_cooldown  # Stagger initial throws
	
	# Initialize reproduction timer
	_reproduce_timer = reproduce_threshold
	
	# Add to crabs group for easy lookup
	add_to_group("crabs")

	# Crabs pass through each other: BaseEnemy puts solid enemies on World_Player
	# (so they block the turtle), which is also in the crab's mask, so without this
	# crabs shove each other into clusters. Spacing is handled by _separate_from_crabs().
	# An exception on either body is enough, so the new crab adds it for both.
	for crab in get_tree().get_nodes_in_group("crabs"):
		if crab != self and is_instance_valid(crab):
			add_collision_exception_with(crab)
	
	# Create collision shape if not present
	_setup_collision_shape()

	# Play correct idle animation for this crab type
	var anim_sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite and anim_sprite.sprite_frames:
		var anim := _get_idle_anim()
		if anim_sprite.sprite_frames.has_animation(anim):
			anim_sprite.play(anim)

func _setup_collision_shape():
	"""Ensure the RigidBody2D has a collision shape"""
	var existing_shape = get_node_or_null("CollisionShape2D")
	
	if not existing_shape:
		var collision_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 10.0  # Adjust based on your sprite size
		collision_shape.shape = circle
		add_child(collision_shape)
		print("Crab: Created collision shape automatically")

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
	# Update state machine
	match current_state:
		State.IDLE:
			_idle_behavior(delta)
		State.WINDUP:
			_windup_behavior(delta)
		State.THROWING:
			_throwing_behavior(delta)
		State.RELOCATING:
			_relocating_behavior(delta)
	
	# Visual bobbing animation (unless relocating)
	if current_state != State.RELOCATING:
		bob_offset += idle_bob_speed * delta
		if sprite:
			sprite.position.y = sin(bob_offset) * idle_bob_amount
	
	# Lock to floor position
	_lock_to_floor()

func _idle_behavior(delta: float):
	"""Wait and prepare to throw"""
	throw_timer -= delta
	
	if throw_timer <= 0:
		# Check if player is in range
		var distance = global_position.distance_to(player.global_position)
		if distance <= detection_range:
			current_state = State.WINDUP
			_windup_timer = WINDUP_DURATION
			_start_windup_indicator()
			throw_timer = throw_cooldown
	
	# Reproduction timer (only in IDLE state, only if not already reproduced)
	if not _has_reproduced:
		_reproduce_timer -= delta

		if _reproduce_timer <= REPRODUCE_WARNING_TIME and not _reproduce_warning_particles:
			_start_reproduce_warning()

		if _reproduce_timer <= 0:
			_has_reproduced = true
			_stop_reproduce_warning()
			ready_to_reproduce.emit(self)
			print("🦀 Crab ready to reproduce!")

func _windup_behavior(delta: float):
	_windup_timer -= delta
	if _windup_timer <= 0:
		current_state = State.THROWING

func _throwing_behavior(_delta: float):
	_stop_windup_indicator()
	throw_projectile()
	current_state = State.IDLE

func _start_windup_indicator():
	_stop_windup_indicator()
	if not player or not is_instance_valid(player):
		return
	var indicator = Sprite2D.new()
	indicator.texture = preload("res://entities/enemies/crab/sprites/crab_projectile1.png")
	var to_player = (player.global_position - global_position).normalized()
	indicator.position = to_player * 14.0 + Vector2(0, -4)
	indicator.scale = Vector2.ONE
	_windup_node = indicator
	add_child(indicator)
	# Bound to the indicator, not the crab: a looping tween whose target is freed
	# spins forever inside one frame in release builds (no debug-only loop guard).
	var tween = indicator.create_tween().set_loops()
	tween.tween_property(indicator, "scale", Vector2(2.5, 2.5), WINDUP_DURATION * 0.4)
	tween.tween_property(indicator, "scale", Vector2(1.0, 1.0), WINDUP_DURATION * 0.2)

func _stop_windup_indicator():
	if _windup_node and is_instance_valid(_windup_node):
		_windup_node.queue_free()
	_windup_node = null

func _relocating_behavior(delta: float):
	"""Scuttle to new location"""
	_relocation_elapsed += delta

	# If stuck (boxed by walls or other crabs), give up and return to idle
	if _relocation_elapsed >= RELOCATION_TIMEOUT:
		_finish_relocation()
		return

	var to_target = relocation_target - global_position
	var distance = to_target.length()

	if distance < 6.0:
		_finish_relocation()
		return

	# Don't interrupt a damage animation mid-play
	if not _is_playing_damage_animation:
		var animated_sprite = get_node_or_null("AnimatedSprite2D")
		if animated_sprite and animated_sprite.sprite_frames:
			var anim := _get_move_anim()
			if animated_sprite.sprite_frames.has_animation(anim):
				animated_sprite.play(anim)

	var direction = to_target.normalized()
	apply_central_force(direction * relocation_speed * 10)

	if sprite:
		sprite.flip_h = direction.x < 0

func _finish_relocation():
	"""Shared exit path for relocation — reached target or timed out"""
	_relocation_elapsed = 0.0
	starting_position = global_position
	current_state = State.IDLE
	throw_timer = throw_cooldown * 0.5
	var animated_sprite = get_node_or_null("AnimatedSprite2D")
	if animated_sprite and animated_sprite.sprite_frames:
		var anim := _get_idle_anim()
		if animated_sprite.sprite_frames.has_animation(anim):
			animated_sprite.play(anim)

func _get_idle_anim() -> String:
	if current_health <= 10.0:
		return "near_death"
	if is_super and current_health > 20.0:
		return "super"
	return "default"

func _get_move_anim() -> String:
	if current_health <= 10.0:
		return "near_death"
	if is_super and current_health > 20.0:
		return "super_move"
	return "move"

func _start_reproduce_warning() -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = true
	particles.amount = 14
	particles.lifetime = 0.9
	particles.emission_shape = CPUParticles2D.EmissionShape.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 11.0
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 12.0
	particles.initial_velocity_max = 30.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.1, 0.1, 1.0))
	gradient.set_color(1, Color(1.0, 0.05, 0.05, 0.0))
	particles.color_ramp = gradient
	particles.z_index = 1
	add_child(particles)
	_reproduce_warning_particles = particles

func _stop_reproduce_warning() -> void:
	if _reproduce_warning_particles and is_instance_valid(_reproduce_warning_particles):
		_reproduce_warning_particles.emitting = false
		_reproduce_warning_particles.queue_free()
	_reproduce_warning_particles = null

func _lock_to_floor():
	"""Keep crab locked to floor position"""
	var target_y = floor_y
	var y_error = target_y - global_position.y

	# Hard ceiling at ocean surface — should never trigger normally, but guards
	# against physics edge cases that could launch the crab out of the water
	if ocean and global_position.y < ocean.surface_y:
		global_position.y = ocean.surface_y
		linear_velocity.y = maxf(linear_velocity.y, 0.0)

	# Apply vertical force to maintain floor position
	apply_central_force(Vector2(0, y_error * position_lock_strength))

	# Dampen vertical movement
	linear_velocity.y *= GameSettings.drag_step(0.8, get_physics_process_delta_time())

	_separate_from_crabs(get_physics_process_delta_time())

func _separate_from_crabs(delta: float) -> void:
	"""Slide apart from any resting crab closer than min_crab_spacing.

	Crabs don't collide with each other (collision exceptions set in
	_enemy_ready()), so spacing is enforced here by moving the crab directly rather
	than with a force — a force loses to linear_damp and to a relocating crab's
	scuttle force. Each crab of an overlapping pair moves itself half the overlap,
	so the pair resolves symmetrically. Relocating crabs are skipped on both sides
	so a scuttling crab can pass others on its way; it re-joins once it's IDLE."""
	if current_state == State.RELOCATING:
		return
	var max_step := separation_speed * delta
	var push := 0.0
	for crab in get_tree().get_nodes_in_group("crabs"):
		if crab == self or not is_instance_valid(crab) or crab.current_state == State.RELOCATING:
			continue
		var offset: Vector2 = global_position - crab.global_position
		if absf(offset.y) > min_crab_spacing:
			continue  # Different floor
		var dist := absf(offset.x)
		if dist >= min_crab_spacing:
			continue
		var dir := signf(offset.x)
		if dist < 0.01:
			# Exactly stacked (e.g. a baby that couldn't leave its parent): break the
			# tie by instance id so the two crabs always pick opposite directions.
			dir = 1.0 if get_instance_id() > crab.get_instance_id() else -1.0
		push += dir * (min_crab_spacing - dist) * 0.5
	if push == 0.0:
		return
	var new_x := clampf(global_position.x + clampf(push, -max_step, max_step), floor_min_x, floor_max_x)
	global_position.x = new_x
	starting_position.x = new_x

func throw_projectile():
	"""Throw a projectile at the player"""
	if not projectile_scene:
		push_warning("Crab: No projectile scene assigned!")
		return
	
	if not player or not is_instance_valid(player):
		return
	
	# Calculate throw direction with arc
	var to_player = player.global_position - global_position
	var distance = to_player.length()
	var horizontal_direction = to_player.normalized()
	
	# Add upward arc component
	var arc_angle = lerp(0.0, PI / 4, throw_arc_height)  # 0 to 45 degrees
	var throw_direction = horizontal_direction.rotated(-arc_angle)
	
	# Adjust velocity based on distance (throw harder for farther targets)
	var distance_multiplier = clamp(distance / 150.0, 0.8, 1.5)
	var throw_vel = throw_direction * throw_velocity * distance_multiplier
	
	# Spawn projectile
	var projectile = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	
	# Position slightly in front of crab
	var spawn_offset = horizontal_direction * 15
	projectile.global_position = global_position + spawn_offset
	
	# Set velocity
	if projectile.has_method("set_velocity"):
		projectile.set_velocity(throw_vel)
	else:
		projectile.linear_velocity = throw_vel
	
	# Face throw direction
	if sprite:
		sprite.flip_h = horizontal_direction.x < 0

func choose_relocation_target() -> Vector2:
	"""Pick a new floor position away from current spot and clear of other crabs.

	Clearance is measured against where each other crab will end up — its
	relocation target if it's scuttling, otherwise where it stands — so two crabs
	relocating at once can't claim the same spot. If the floor is too crowded for
	any candidate to be fully clear, takes the roomiest one rather than staying put."""
	var claimed: Array[float] = []
	for crab in get_tree().get_nodes_in_group("crabs"):
		if crab == self or not is_instance_valid(crab):
			continue
		claimed.append(crab.relocation_target.x if crab.current_state == State.RELOCATING else crab.global_position.x)

	var best_target := Vector2(global_position.x, floor_y)
	var best_score := -INF
	var roomiest_target := best_target
	var roomiest_clearance := -INF

	for _i in range(30):
		var candidate := Vector2(randf_range(floor_min_x, floor_max_x), floor_y)
		var dist_from_self := absf(candidate.x - global_position.x)
		if dist_from_self < relocation_distance_min:
			continue

		var clearance := INF
		for x in claimed:
			clearance = minf(clearance, absf(candidate.x - x))

		if clearance > roomiest_clearance:
			roomiest_clearance = clearance
			roomiest_target = candidate

		if clearance < min_crab_spacing + 4.0:
			continue

		# Score: prefer farther from self, capped at relocation_distance_max
		var score := minf(dist_from_self, relocation_distance_max)
		if score > best_score:
			best_score = score
			best_target = candidate

	return best_target if best_score > -INF else roomiest_target

## PUBLIC METHOD: Called by CrabSpawner to make baby crab relocate
func relocate_from_parent():
	relocation_target = choose_relocation_target()
	current_state = State.RELOCATING
	_relocation_elapsed = 0.0

## Override take_damage to trigger relocation and reset reproduction timer
func take_damage(amount: float):
	# Relocating crabs are normally invincible mid-scuttle, but during Time Freeze
	# their _physics_process (and thus _relocating_behavior/_finish_relocation) is
	# paused, so they'd never leave RELOCATING and would become permanently
	# invincible for the rest of the freeze. Since they're visibly frozen in place
	# anyway, let them still take damage in that case.
	var relocating_but_frozen = current_state == State.RELOCATING and AlienTechManager.time_freeze_active
	if is_invincible or (current_state == State.RELOCATING and not relocating_but_frozen):
		_play_invincible_feedback()
		return
	
	var was_alive = current_health > 0
	current_health -= amount
	_play_damage_feedback()
	
	# Reset reproduction timer on damage — also remove warning particles
	_reproduce_timer = reproduce_threshold
	_stop_reproduce_warning()
	
	if current_health <= 0:
		_report_kill()
		die()
	elif was_alive and current_state != State.RELOCATING:
		_stop_windup_indicator()
		relocation_target = choose_relocation_target()
		current_state = State.RELOCATING
		_relocation_elapsed = 0.0

## Override die() for crab death animation
func die():
	# Dying crabs float off and fade — stop counting them for spacing
	remove_from_group("crabs")
	_play_die_sound()
	_stop_windup_indicator()
	_stop_reproduce_warning()
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	
	# Flip upside down
	if sprite:
		tween.tween_property(sprite, "rotation", PI, 0.8)
	
	# Float up slightly (dead crab)
	tween.tween_property(self, "global_position:y", global_position.y - 20, 0.8)
	
	tween.finished.connect(queue_free)
	
	# Disable collision while dying
	collision_layer = 0
	collision_mask = 0
