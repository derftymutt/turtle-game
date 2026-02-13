extends BaseEnemy
class_name ElectricEel

## Electric eel that hunts walls/flippers near the player and electrifies them
## Creates time pressure on safe "turtling" positions

# Movement settings
@export var swim_speed: float = 200.0
@export var wall_detection_range: float = 300.0
@export var player_influence_range: float = 250.0

# Wall navigation and stuck prevention
@export_group("Anti-Stuck Behavior")
@export var stuck_detection_time: float = 2.0  # Time stationary = stuck
@export var stuck_velocity_threshold: float = 15.0  # Velocity below this = stuck
@export var wall_avoidance_force: float = 250.0
@export var exploration_duration: float = 3.0  # How long to explore when stuck
@export var exploration_speed_multiplier: float = 0.7

# Shocking behavior
@export var shock_telegraph_duration: float = 0.3
@export var shock_duration: float = 2.5
@export var shock_cooldown: float = 2.0
@export var shock_range: float = 25.0
@export var shock_damage: float = 15.0
@export var shock_knockback: float = 300.0
@export var control_suspend_duration: float = 1.0

# Visual settings
@export var telegraph_color: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var shock_color: Color = Color(1.0, 1.0, 0.0, 1.0)
@export var wiggle_speed: float = 6.0
@export var wiggle_amount: float = 0.2

# Ocean depth preferences
@export var preferred_depth_min: float = 60.0
@export var preferred_depth_max: float = 140.0
@export var depth_correction_force: float = 40.0

# Internal state
enum State { SEEKING_WALL, APPROACHING_WALL, TELEGRAPHING, SHOCKING, COOLDOWN, EXPLORING }
var current_state: State = State.SEEKING_WALL
var player: Node2D = null
var ocean: Ocean = null

# Wall targeting
var target_wall: Node2D = null
var nearby_walls: Array[Node2D] = []
var shocked_walls: Array[Node2D] = []

# Timers
var state_timer: float = 0.0
var wiggle_offset: float = 0.0

# Stuck detection
var last_position: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var exploration_target: Vector2 = Vector2.ZERO

# Visual effects
var telegraph_particles: Array = []

func _enemy_ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 4.0
	angular_damp = 5.0
	mass = 1.2
	
	# Health
	max_health = 25.0
	current_health = max_health
	contact_damage = 10.0
	
	# Find references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Random starting wiggle
	wiggle_offset = randf() * TAU
	
	# Initialize stuck detection
	last_position = global_position
	
	# Setup damage area
	if not damage_area:
		_setup_damage_area()
	else:
		# Reconnect signal to use our override
		if damage_area.body_entered.is_connected(_on_damage_area_entered):
			damage_area.body_entered.disconnect(_on_damage_area_entered)
		damage_area.body_entered.connect(_on_damage_area_entered)
	
	# Ensure damage area is configured correctly
	if damage_area:
		damage_area.collision_layer = 0
		damage_area.collision_mask = 1

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
	# Detect if stuck (except during shocking phase)
	if current_state != State.SHOCKING and current_state != State.TELEGRAPHING:
		_detect_stuck(delta)
	
	# Maintain preferred depth
	_maintain_depth()
	
	# State machine
	match current_state:
		State.SEEKING_WALL:
			_seek_wall_behavior(delta)
		State.APPROACHING_WALL:
			_approach_wall_behavior(delta)
		State.TELEGRAPHING:
			_telegraph_behavior(delta)
		State.SHOCKING:
			_shock_behavior(delta)
		State.COOLDOWN:
			_cooldown_behavior(delta)
		State.EXPLORING:
			_exploration_behavior(delta)
	
	# Visual effects
	_animate_swimming(delta)
	
	# Update state timer
	state_timer -= delta
	
	# Update last position for stuck detection
	last_position = global_position

func _seek_wall_behavior(_delta: float):
	"""Find a nearby wall to target, prioritizing walls near player"""
	if nearby_walls.is_empty():
		_scan_for_walls()
	
	target_wall = _choose_best_wall()
	
	if target_wall:
		current_state = State.APPROACHING_WALL
	else:
		# No walls found - patrol toward player slowly
		var to_player = player.global_position - global_position
		var direction = to_player.normalized()
		apply_central_force(direction * swim_speed * 0.5)

func _approach_wall_behavior(_delta: float):
	"""Swim toward target wall"""
	if not target_wall or not is_instance_valid(target_wall):
		current_state = State.SEEKING_WALL
		return
	
	var to_wall = target_wall.global_position - global_position
	var distance = to_wall.length()
	
	if distance > shock_range:
		var direction = to_wall.normalized()
		apply_central_force(direction * swim_speed)
		_face_direction(direction)
	else:
		current_state = State.TELEGRAPHING
		state_timer = shock_telegraph_duration
		_start_telegraph_effect()

func _telegraph_behavior(_delta: float):
	"""Warning phase - visual telegraph before shock"""
	if state_timer <= 0:
		current_state = State.SHOCKING
		state_timer = shock_duration
		_apply_shock_to_wall()
		_cleanup_telegraph_effect()
	
	# Stay near wall during telegraph
	if target_wall and is_instance_valid(target_wall):
		var to_wall = target_wall.global_position - global_position
		if to_wall.length() > shock_range * 1.5:
			apply_central_force(to_wall.normalized() * swim_speed * 0.5)

func _shock_behavior(_delta: float):
	"""Shocking phase - wall is electrified"""
	if state_timer <= 0:
		current_state = State.COOLDOWN
		state_timer = shock_cooldown
		_remove_shock_from_wall()
	
	# Maintain position near wall
	if target_wall and is_instance_valid(target_wall):
		var to_wall = target_wall.global_position - global_position
		if to_wall.length() > shock_range * 1.5:
			apply_central_force(to_wall.normalized() * swim_speed * 0.3)

func _cooldown_behavior(_delta: float):
	"""Recovery phase - can't shock, seeks new wall"""
	if state_timer <= 0:
		current_state = State.SEEKING_WALL
		target_wall = null
		nearby_walls.clear()
	
	# Drift slowly toward player area
	var to_player = player.global_position - global_position
	if to_player.length() < player_influence_range:
		apply_central_force(to_player.normalized() * swim_speed * 0.3)

func _detect_stuck(delta: float):
	"""Detect if eel is stuck against a wall and trigger exploration"""
	var velocity = linear_velocity.length()
	var movement = global_position.distance_to(last_position)
	
	# Check if we're barely moving
	if velocity < stuck_velocity_threshold or movement < 2.0:
		stuck_timer += delta
		
		if stuck_timer >= stuck_detection_time:
			# We're stuck! Enter exploration mode
			current_state = State.EXPLORING
			state_timer = exploration_duration
			stuck_timer = 0.0
			_choose_exploration_target()
	else:
		# We're moving fine, reset stuck timer
		stuck_timer = 0.0

func _choose_exploration_target():
	"""Pick a random direction to explore when stuck"""
	# Choose a position away from our current location
	var random_angle = randf() * TAU
	var random_distance = randf_range(150.0, 300.0)
	
	exploration_target = global_position + Vector2(
		cos(random_angle) * random_distance,
		sin(random_angle) * random_distance
	)
	
	# Keep it within reasonable depth bounds
	if ocean:
		var target_depth = ocean.get_depth(exploration_target)
		if target_depth < preferred_depth_min:
			exploration_target.y += 50
		elif target_depth > preferred_depth_max:
			exploration_target.y -= 50

func _exploration_behavior(_delta: float):
	"""Swim to exploration target to escape stuck position"""
	if state_timer <= 0:
		# Exploration done, go back to seeking walls
		current_state = State.SEEKING_WALL
		target_wall = null
		nearby_walls.clear()
		return
	
	# Swim toward exploration target
	var to_target = exploration_target - global_position
	var distance = to_target.length()
	
	if distance > 20.0:  # Still need to reach target
		var direction = to_target.normalized()
		apply_central_force(direction * swim_speed * exploration_speed_multiplier)
		_face_direction(direction)
	else:
		# Reached target, pick a new one to keep moving
		_choose_exploration_target()

func _scan_for_walls():
	"""Find all nearby walls and flippers"""
	nearby_walls.clear()
	var all_walls = get_tree().get_nodes_in_group("walls")
	
	for wall in all_walls:
		if not wall is Node2D:
			continue
		
		var distance = global_position.distance_to(wall.global_position)
		if distance < wall_detection_range:
			nearby_walls.append(wall)

func _choose_best_wall() -> Node2D:
	"""Pick the best wall to target - prioritize walls near player"""
	if nearby_walls.is_empty():
		return null
	
	var best_wall: Node2D = null
	var best_score: float = -INF
	
	for wall in nearby_walls:
		if not is_instance_valid(wall):
			continue
		
		# Skip walls we just shocked
		if wall in shocked_walls:
			continue
		
		var score = 0.0
		
		# Prefer walls closer to player
		var player_distance = wall.global_position.distance_to(player.global_position)
		if player_distance < player_influence_range:
			score += (player_influence_range - player_distance) * 2.0
		
		# Slightly prefer closer walls
		var eel_distance = global_position.distance_to(wall.global_position)
		score += (wall_detection_range - eel_distance) * 0.5
		
		if score > best_score:
			best_score = score
			best_wall = wall
	
	return best_wall

func _maintain_depth():
	"""Keep eel at preferred depth range"""
	if not ocean:
		return
	
	var depth = ocean.get_depth(global_position)
	var correction = 0.0
	
	if depth < preferred_depth_min:
		correction = depth_correction_force
	elif depth > preferred_depth_max:
		correction = -depth_correction_force
	
	if correction != 0:
		apply_central_force(Vector2(0, correction))

func _face_direction(direction: Vector2):
	"""Flip sprite to face movement direction"""
	if sprite:
		sprite.flip_h = direction.x < 0

func _animate_swimming(delta: float):
	"""Wiggle animation - more intense during telegraph/shock"""
	wiggle_offset += wiggle_speed * delta
	
	var intensity = 1.0
	if current_state == State.TELEGRAPHING:
		intensity = 2.0
	elif current_state == State.SHOCKING:
		intensity = 3.0
	
	rotation = sin(wiggle_offset) * wiggle_amount * intensity

func _start_telegraph_effect():
	"""Create visual warning that shock is coming"""
	if not sprite:
		return
	
	sprite.modulate = telegraph_color
	
	if target_wall and is_instance_valid(target_wall):
		_spawn_arc_effects()

func _spawn_arc_effects():
	"""Create electric arc particles between eel and wall"""
	for i in range(3):
		var arc_line = Line2D.new()
		arc_line.width = 2.0
		arc_line.default_color = telegraph_color
		arc_line.z_index = 100
		
		# Arc goes from eel to wall with some randomness
		var start_point = global_position
		var end_point = target_wall.global_position
		var midpoint = (start_point + end_point) / 2.0
		midpoint += Vector2(randf_range(-15, 15), randf_range(-15, 15))
		
		arc_line.add_point(start_point)
		arc_line.add_point(midpoint)
		arc_line.add_point(end_point)
		
		get_parent().add_child(arc_line)
		telegraph_particles.append(arc_line)
		
		# Animate arc
		var tween = create_tween()
		tween.tween_property(arc_line, "modulate:a", 0.0, shock_telegraph_duration)

func _cleanup_telegraph_effect():
	"""Remove telegraph visuals"""
	if sprite:
		sprite.modulate = Color.WHITE
	
	for arc in telegraph_particles:
		if is_instance_valid(arc):
			arc.queue_free()
	telegraph_particles.clear()

func _apply_shock_to_wall():
	"""Electrify the target wall"""
	if not target_wall or not is_instance_valid(target_wall):
		return
	
	var shock_component = ShockedWall.new()
	shock_component.shock_duration = shock_duration
	shock_component.shock_damage = shock_damage
	shock_component.shock_knockback = shock_knockback
	shock_component.control_suspend_duration = control_suspend_duration
	shock_component.shock_color = shock_color
	shock_component.name = "ShockComponent"
	
	target_wall.add_child(shock_component)
	shocked_walls.append(target_wall)

func _remove_shock_from_wall():
	"""Clean up shock from wall"""
	if target_wall and is_instance_valid(target_wall):
		var shock_component = target_wall.get_node_or_null("ShockComponent")
		if shock_component and shock_component.has_method("cleanup"):
			# Use cleanup method to ensure visual is removed immediately
			shock_component.cleanup()
		elif shock_component:
			shock_component.queue_free()
	
	# Clear shocked walls list after cooldown
	await get_tree().create_timer(shock_cooldown).timeout
	shocked_walls.clear()

func _setup_damage_area():
	"""Create DamageArea if it doesn't exist"""
	damage_area = Area2D.new()
	damage_area.name = "DamageArea"
	damage_area.collision_layer = 0
	damage_area.collision_mask = 1
	
	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0
	collision_shape.shape = circle
	
	damage_area.add_child(collision_shape)
	add_child(damage_area)
	damage_area.body_entered.connect(_on_damage_area_entered)

func _on_damage_area_entered(body: Node2D):
	"""Override from BaseEnemy - always deals damage when touched"""
	if body.is_in_group("player") and body.has_method("take_damage"):
		_deal_damage_to_player(body)

func die():
	"""Electric discharge death animation"""
	# Cleanup any active shocks
	_cleanup_telegraph_effect()
	if target_wall and is_instance_valid(target_wall):
		_remove_shock_from_wall()
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Bright flash
	tween.tween_property(self, "modulate", Color(0.0, 2.0, 2.0, 1.0), 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.1)
	
	# Spin violently
	tween.tween_property(self, "rotation", rotation + TAU * 3, 0.6)
	
	tween.finished.connect(queue_free)
	
	# Disable collision
	collision_layer = 0
	collision_mask = 0


# ============================================================================
# SHOCKED WALL COMPONENT
# ============================================================================
class ShockedWall extends Node:
	"""Component attached to walls/flippers to make them electrified"""
	
	var shock_duration: float = 2.5
	var shock_damage: float = 30.0
	var shock_knockback: float = 400.0
	var control_suspend_duration: float = 0.5
	var shock_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	
	var shock_timer: float = 0.0
	var parent_wall: Node2D = null
	var detection_area: Area2D = null
	var shocked_players: Array = []
	var shock_overlay: Polygon2D = null
	var flash_timer: float = 0.0
	var flash_interval: float = 0.15
	var is_flashing_yellow: bool = false
	
	func _ready():
		parent_wall = get_parent()
		shock_timer = shock_duration
		
		_setup_detection_area()
		_create_shock_visual()
		
		# Check for players already touching wall
		_check_for_campers.call_deferred()
	
	func _check_for_campers():
		"""Check if player is already touching wall"""
		if not detection_area:
			return
		
		var bodies = detection_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("player") and not body in shocked_players:
				_shock_player(body)
	
	func _physics_process(delta):
		shock_timer -= delta
		
		if shock_timer <= 0:
			_expire()
			return
		
		# Manual flash effect on overlay
		if shock_overlay and is_instance_valid(shock_overlay):
			flash_timer += delta
			if flash_timer >= flash_interval:
				flash_timer = 0.0
				is_flashing_yellow = not is_flashing_yellow
				shock_overlay.color = shock_color if is_flashing_yellow else Color.WHITE
		
		# Check for player contact
		if detection_area:
			var bodies = detection_area.get_overlapping_bodies()
			for body in bodies:
				if body.is_in_group("player") and not body in shocked_players:
					_shock_player(body)
	
	func _setup_detection_area():
		"""Create Area2D to detect player touching wall"""
		detection_area = Area2D.new()
		detection_area.name = "ShockDetection"
		detection_area.collision_layer = 0
		detection_area.collision_mask = 1
		detection_area.monitoring = true
		detection_area.monitorable = false
		
		# Copy parent's collision shape
		for child in parent_wall.get_children():
			if child is CollisionShape2D and child.shape:
				var new_shape = CollisionShape2D.new()
				new_shape.shape = child.shape.duplicate()
				new_shape.position = child.position
				new_shape.rotation = child.rotation
				detection_area.add_child(new_shape)
		
		add_child(detection_area)
		detection_area.global_position = parent_wall.global_position
		detection_area.global_rotation = parent_wall.global_rotation
	
	func _create_shock_visual():
		"""Create crackling electric effect on wall"""
		var visual_effect: Node2D = null
		
		# Find visual node
		if parent_wall.has_node("Polygon2D"):
			visual_effect = parent_wall.get_node("Polygon2D")
		elif parent_wall.has_node("Sprite2D"):
			visual_effect = parent_wall.get_node("Sprite2D")
		else:
			for child in parent_wall.get_children():
				if child is Polygon2D or child is Sprite2D:
					visual_effect = child
					break
		
		# Create overlay for visual effect
		if visual_effect and visual_effect is Polygon2D:
			shock_overlay = Polygon2D.new()
			shock_overlay.polygon = visual_effect.polygon.duplicate()
			shock_overlay.color = shock_color
			shock_overlay.z_index = 1000
			shock_overlay.name = "ShockOverlay"
			parent_wall.add_child(shock_overlay)
	
	func _shock_player(player: Node2D):
		"""Apply shock damage, knockback, and control suspension to player"""
		shocked_players.append(player)
		
		# Damage
		if player.has_method("take_damage"):
			player.take_damage(shock_damage)
		
		# Knockback (reduced for better feel)
		var knockback_dir = (player.global_position - parent_wall.global_position).normalized()
		if player is RigidBody2D:
			var reduced_knockback = shock_knockback * 0.5
			player.apply_central_impulse(knockback_dir * reduced_knockback)
		
		# Suspend player control
		if player.has_method("suspend_control"):
			player.suspend_control(control_suspend_duration)
		
		# Visual feedback
		_create_shock_spark_effect(player.global_position)
	
	func _create_shock_spark_effect(position: Vector2):
		"""Create visual spark effect at shock point"""
		var spark = Node2D.new()
		spark.global_position = position
		spark.z_index = 200
		get_tree().root.add_child(spark)
		
		var tween = create_tween()
		tween.tween_callback(spark.queue_free).set_delay(0.2)
	
	func _expire():
		"""Remove shock effect when timer expires"""
		cleanup()
	
	func cleanup():
		"""Immediately clean up visual overlay and free component"""
		if shock_overlay and is_instance_valid(shock_overlay):
			shock_overlay.queue_free()
			shock_overlay = null
		queue_free()
