extends BaseEnemy
class_name ElectricEel

## Electric eel that hunts walls/flippers near the player and electrifies them
## Creates time pressure on safe "turtling" positions

# Movement settings
@export var swim_speed: float = 200.0  # Slow, deliberate movement
@export var wall_detection_range: float = 300.0  # How far it can "sense" walls
@export var player_influence_range: float = 250.0  # Prioritize walls near player within this range

# Shocking behavior
@export var shock_telegraph_duration: float = 0.3  # Warning before shock (0.8 was too long, reduced to 0.3)
@export var shock_duration: float = 2.5  # How long wall stays electrified
@export var shock_cooldown: float = 2.0  # Time between shocks
@export var shock_range: float = 25.0  # Distance from wall to trigger shock
@export var shock_damage: float = 15.0  # Damage to player
@export var shock_knockback: float = 300.0  # Strong repulsion
@export var control_suspend_duration: float = 1.0  # Player loses control briefly (INCREASED from 0.5 to 1.0 to make more noticeable)

# Visual settings
@export var telegraph_color: Color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan glow
@export var shock_color: Color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow/white electric
@export var wiggle_speed: float = 6.0
@export var wiggle_amount: float = 0.2

# Ocean depth preferences (mid-depth hunter)
@export var preferred_depth_min: float = 60.0
@export var preferred_depth_max: float = 140.0
@export var depth_correction_force: float = 40.0

# Internal state
enum State { SEEKING_WALL, APPROACHING_WALL, TELEGRAPHING, SHOCKING, COOLDOWN }
var current_state: State = State.SEEKING_WALL
var player: Node2D = null
var ocean: Ocean = null

# Wall targeting
var target_wall: Node2D = null
var nearby_walls: Array[Node2D] = []
var shocked_walls: Array[Node2D] = []  # Track currently shocked walls

# Timers
var state_timer: float = 0.0
var wiggle_offset: float = 0.0

# Visual effects
var telegraph_particles: Array = []  # Store arc effect nodes

func _enemy_ready():
	# Physics setup - slow, methodical swimmer
	gravity_scale = 0.0
	linear_damp = 4.0  # Higher drag = slower, more controlled
	angular_damp = 5.0
	mass = 1.2
	
	# Health - tougher than piranha
	max_health = 25.0
	current_health = max_health
	contact_damage = 10.0  # Damage when player touches eel
	
	# Find references
	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")
	
	# Random starting wiggle
	wiggle_offset = randf() * TAU
	
	# CRITICAL: Ensure DamageArea exists and is configured
	# The eel should ALWAYS be electric and dangerous!
	if not damage_area:
		_setup_damage_area()
	else:
		# IMPORTANT: Reconnect signal to use OUR override, not BaseEnemy's
		if damage_area.body_entered.is_connected(_on_damage_area_entered):
			damage_area.body_entered.disconnect(_on_damage_area_entered)
		damage_area.body_entered.connect(_on_damage_area_entered)
	
	# Make sure damage area is properly configured
	if damage_area:
		# Ensure collision settings are correct
		damage_area.collision_layer = 0
		damage_area.collision_mask = 1  # Detect player
	else:
		print("  ERROR: damage_area is still null after setup!")
	
	# Set up wall detection area
	_setup_wall_detection()

func _physics_process(delta):
	if not player or not is_instance_valid(player):
		return
	
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
	
	# Visual effects
	_animate_swimming(delta)
	
	# Update state timer
	state_timer -= delta

func _seek_wall_behavior(_delta: float):
	"""Find a nearby wall to target, prioritizing walls near player"""
	# Scan for walls periodically
	if nearby_walls.is_empty():
		_scan_for_walls()
	
	# Pick best wall target
	target_wall = _choose_best_wall()
	
	if target_wall:
		current_state = State.APPROACHING_WALL
		print("Eel: Targeting wall at ", target_wall.global_position)
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
	
	# Move toward wall
	if distance > shock_range:
		var direction = to_wall.normalized()
		apply_central_force(direction * swim_speed)
		_face_direction(direction)
	else:
		# Close enough - start telegraph
		current_state = State.TELEGRAPHING
		state_timer = shock_telegraph_duration
		_start_telegraph_effect()
		print("Eel: Telegraphing shock at ", Time.get_ticks_msec(), "ms! (duration: ", shock_telegraph_duration, "s)")

func _telegraph_behavior(_delta: float):
	"""Warning phase - visual telegraph before shock"""
	if state_timer <= 0:
		print("Eel: Telegraph complete at ", Time.get_ticks_msec(), "ms - SHOCKING NOW!")
		# Telegraph complete - SHOCK IMMEDIATELY!
		current_state = State.SHOCKING
		state_timer = shock_duration
		_apply_shock_to_wall()  # This creates the yellow visual NOW
		_cleanup_telegraph_effect()  # Remove cyan telegraph
	
	# Stay near wall during telegraph
	if target_wall and is_instance_valid(target_wall):
		var to_wall = target_wall.global_position - global_position
		if to_wall.length() > shock_range * 1.5:
			apply_central_force(to_wall.normalized() * swim_speed * 0.5)

func _shock_behavior(_delta: float):
	"""Shocking phase - wall is electrified"""
	if state_timer <= 0:
		# Shock complete - enter cooldown
		current_state = State.COOLDOWN
		state_timer = shock_cooldown
		_remove_shock_from_wall()
		print("Eel: Shock complete, entering cooldown")
	
	# Maintain position near wall
	if target_wall and is_instance_valid(target_wall):
		var to_wall = target_wall.global_position - global_position
		if to_wall.length() > shock_range * 1.5:
			apply_central_force(to_wall.normalized() * swim_speed * 0.3)

func _cooldown_behavior(_delta: float):
	"""Recovery phase - can't shock, seeks new wall"""
	if state_timer <= 0:
		# Cooldown complete - seek new target
		current_state = State.SEEKING_WALL
		target_wall = null
		nearby_walls.clear()
		print("Eel: Cooldown complete, seeking new wall")
	
	# Drift slowly, maybe toward player area
	var to_player = player.global_position - global_position
	if to_player.length() < player_influence_range:
		apply_central_force(to_player.normalized() * swim_speed * 0.3)

func _scan_for_walls():
	"""Find all nearby walls and flippers"""
	nearby_walls.clear()
	
	# Get all walls in the scene
	var all_walls = get_tree().get_nodes_in_group("walls")
	
	print("Eel: Scanning for walls... found ", all_walls.size(), " in 'walls' group")
	
	for wall in all_walls:
		if not wall is Node2D:
			continue
		
		var distance = global_position.distance_to(wall.global_position)
		if distance < wall_detection_range:
			nearby_walls.append(wall)
			print("  - Found wall '", wall.name, "' at distance ", distance)
	
	print("Eel: ", nearby_walls.size(), " walls in detection range")

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
		
		# Slightly prefer closer walls (but player proximity is more important)
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
	
	# Glow effect on eel
	sprite.modulate = telegraph_color
	
	# Create electric arcs toward wall
	if target_wall and is_instance_valid(target_wall):
		_spawn_arc_effects()

func _spawn_arc_effects():
	"""Create electric arc particles between eel and wall"""
	# Simple line-based arcs (you can replace with particles later)
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
	
	# Add shock component to wall
	var shock_component = ShockedWall.new()
	shock_component.shock_duration = shock_duration
	shock_component.shock_damage = shock_damage
	shock_component.shock_knockback = shock_knockback
	shock_component.control_suspend_duration = control_suspend_duration
	shock_component.shock_color = shock_color
	shock_component.name = "ShockComponent"
	
	target_wall.add_child(shock_component)
	shocked_walls.append(target_wall)
	
	print("Eel: Wall shocked!")

func _remove_shock_from_wall():
	"""Clean up shock from wall"""
	if target_wall and is_instance_valid(target_wall):
		var shock_component = target_wall.get_node_or_null("ShockComponent")
		if shock_component:
			shock_component.queue_free()
	
	# Clear shocked walls list after a delay (allow re-shocking after cooldown)
	await get_tree().create_timer(shock_cooldown).timeout
	shocked_walls.clear()

func _setup_wall_detection():
	"""Create detection radius for finding walls (debugging helper)"""
	# This is just for internal logic - actual detection uses distance checks
	pass

func _setup_damage_area():
	"""Create DamageArea if it doesn't exist - eel is always electric!"""
	damage_area = Area2D.new()
	damage_area.name = "DamageArea"
	damage_area.collision_layer = 0
	damage_area.collision_mask = 1
	
	# Create collision shape - circle around eel body
	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0  # Adjust based on your eel sprite size
	collision_shape.shape = circle
	
	damage_area.add_child(collision_shape)
	add_child(damage_area)
	
	# Connect signal for damage dealing
	damage_area.body_entered.connect(_on_damage_area_entered)
	
	print("Eel: Created DamageArea - eel is now always electric!")

func _on_damage_area_entered(body: Node2D):
	"""Override from BaseEnemy - always deals damage when touched"""
	print("Eel: DamageArea body_entered signal fired!")
	print("  Body: ", body.name, " | Is player: ", body.is_in_group("player"))
	
	if body.is_in_group("player") and body.has_method("take_damage"):
		print("  ⚡ EEL SHOCKING PLAYER ON CONTACT! ⚡")
		_deal_damage_to_player(body)
	else:
		print("  Body is not player or doesn't have take_damage method")

## Override die() for eel-specific death
func die():
	# Cleanup any active shocks
	_cleanup_telegraph_effect()
	if target_wall and is_instance_valid(target_wall):
		_remove_shock_from_wall()
	
	# Electric discharge death animation
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
## Component attached to walls/flippers to make them electrified
## Detects and damages the player on contact
class ShockedWall extends Node:
	var shock_duration: float = 2.5
	var shock_damage: float = 30.0
	var shock_knockback: float = 400.0
	var control_suspend_duration: float = 0.5
	var shock_color: Color = Color(1.0, 1.0, 0.0, 1.0)
	
	var shock_timer: float = 0.0
	var parent_wall: Node2D = null
	var detection_area: Area2D = null
	var shocked_players: Array = []  # Track who we've shocked (one shock per contact)
	var visual_effect: Node2D = null
	var last_body_count: int = 0  # Track body count changes to reduce spam
	var debug_frame_count: int = 0  # For periodic debug output
	var original_modulate: Color = Color.WHITE  # Store original color
	var original_z_index: int = 0  # Store original z_index
	var flash_timer: float = 0.0  # Manual flash timer
	var flash_interval: float = 0.15  # Flash every 0.15 seconds
	var is_flashing_yellow: bool = false  # Track flash state
	var shock_overlay: Polygon2D = null  # NEW: separate overlay for visual effect
	
	func _ready():
		print("=== ShockedWall._ready() STARTING ===")
		parent_wall = get_parent()
		shock_timer = shock_duration
		
		# Create Area2D for player detection
		_setup_detection_area()
		
		# Create visual effect
		_create_shock_visual()
		
		# Verify player setup
		var player = get_tree().get_first_node_in_group("player")
		if player:
			print("  Player found: ", player.name)
			print("  Player collision_layer: ", player.collision_layer)
			print("  Player collision_mask: ", player.collision_mask)
			print("  Player in 'player' group: ", player.is_in_group("player"))
		else:
			print("  WARNING: No player found in 'player' group!")
		
		print("ShockedWall: Active on ", parent_wall.name)
		
		# Schedule camping check for next physics frame (don't block with await)
		_check_for_campers.call_deferred()
	
	func _check_for_campers():
		"""Check if player is already touching wall - called after physics update"""
		print("=== CHECKING FOR CAMPERS (deferred) ===")
		if not detection_area:
			print("  ERROR: detection_area is null!")
			return
		
		var bodies = detection_area.get_overlapping_bodies()
		print("  Bodies currently overlapping: ", bodies.size())
		
		if bodies.size() > 0:
			print("  !!! FOUND BODIES ALREADY TOUCHING WALL !!!")
			for body in bodies:
				print("    - Body: ", body.name, " | In player group: ", body.is_in_group("player"))
				if body.is_in_group("player") and not body in shocked_players:
					print("    - ⚡⚡⚡ PLAYER WAS CAMPING! SHOCKING IMMEDIATELY! ⚡⚡⚡")
					_shock_player(body)
		else:
			print("  No bodies currently touching")
	
	func _physics_process(delta):
		shock_timer -= delta
		
		if shock_timer <= 0:
			_expire()
			return
		
		# Manual flash effect on OVERLAY (guaranteed visible)
		if shock_overlay and is_instance_valid(shock_overlay):
			flash_timer += delta
			if flash_timer >= flash_interval:
				flash_timer = 0.0
				is_flashing_yellow = not is_flashing_yellow
				
				if is_flashing_yellow:
					shock_overlay.color = shock_color
				else:
					shock_overlay.color = Color.WHITE
				# No need to print every flash - too spammy
		
		# Check for player contact
		if detection_area:
			var bodies = detection_area.get_overlapping_bodies()
			
			# Periodic debug only when player is close
			debug_frame_count += 1
			if debug_frame_count >= 60:  # Every ~1 second
				debug_frame_count = 0
				var player = get_tree().get_first_node_in_group("player")
				if player:
					var distance = detection_area.global_position.distance_to(player.global_position)
					# Only print if player is nearby (within 50 pixels)
					if distance < 50:
						print("ShockedWall DEBUG: Player nearby!")
						print("  Detection area pos: ", detection_area.global_position)
						print("  Player pos: ", player.global_position)
						print("  Distance: ", distance)
						print("  Bodies detected: ", bodies.size())
			
			# Only print when bodies count changes
			if bodies.size() != last_body_count:
				last_body_count = bodies.size()
				if bodies.size() > 0:
					print("ShockedWall: NOW detecting ", bodies.size(), " bodies")
					for body in bodies:
						print("  - Body: ", body.name, " | Type: ", body.get_class(), " | In 'player' group: ", body.is_in_group("player"))
						print("  - Body position: ", body.global_position)
						print("  - Detection area position: ", detection_area.global_position)
				else:
					print("ShockedWall: Bodies left detection area")
			
			for body in bodies:
				if body.is_in_group("player"):
					if not body in shocked_players:
						print("  - SHOCKING player: ", body.name)
						_shock_player(body)
		else:
			if shock_timer == shock_duration:  # Only print once
				print("ShockedWall: WARNING - detection_area is null!")
	
	func _setup_detection_area():
		"""Create Area2D to detect player touching wall"""
		print("ShockedWall: Setting up detection area")
		detection_area = Area2D.new()
		detection_area.name = "ShockDetection"
		detection_area.collision_layer = 0
		detection_area.collision_mask = 1  # Detect player (layer 1)
		
		# CRITICAL: Enable monitoring
		detection_area.monitoring = true
		detection_area.monitorable = false  # Don't need others to detect this
		
		print("  Parent wall children: ", parent_wall.get_children())
		print("  Parent wall position: ", parent_wall.global_position)
		
		# Copy parent's collision shape
		var shapes_copied = 0
		for child in parent_wall.get_children():
			if child is CollisionShape2D and child.shape:
				print("  Found CollisionShape2D: ", child.name, " with shape ", child.shape)
				print("    Child position: ", child.position)
				print("    Child rotation: ", child.rotation)
				print("    Shape size: ", child.shape.get_rect() if child.shape.has_method("get_rect") else "N/A")
				
				var new_shape = CollisionShape2D.new()
				new_shape.shape = child.shape.duplicate()
				new_shape.position = child.position
				new_shape.rotation = child.rotation
				detection_area.add_child(new_shape)
				shapes_copied += 1
				print("    Copied shape to detection area")
		
		if shapes_copied == 0:
			print("  WARNING: No collision shapes found to copy!")
		else:
			print("  Successfully copied ", shapes_copied, " shape(s)")
		
		add_child(detection_area)
		
		# CRITICAL: Set position AND ensure shape inherits proper transform
		detection_area.global_position = parent_wall.global_position
		detection_area.global_rotation = parent_wall.global_rotation
		
		print("  Detection area added as child")
		print("  Detection area local position: ", detection_area.position)
		print("  Detection area global_position: ", detection_area.global_position)
		print("  Parent wall global_position: ", parent_wall.global_position)
		print("  Parent wall global_rotation: ", parent_wall.global_rotation)
		print("  Should match parent wall position: ", parent_wall.global_position)
		print("  Detection area monitoring: ", detection_area.monitoring)
		print("  Detection area collision_mask: ", detection_area.collision_mask)
		
		# Debug: Print shape details
		for child in detection_area.get_children():
			if child is CollisionShape2D:
				print("  Detection shape global_position: ", child.global_position)
				print("  Detection shape position relative to area: ", child.position)
	
	func _create_shock_visual():
		"""Create crackling electric effect on wall"""
		print("=== ShockedWall._create_shock_visual() STARTING ===")
		print("ShockedWall: Looking for visual on ", parent_wall.name)
		print("  Children: ", parent_wall.get_children())
		
		# Try to find visual node (for reference)
		if parent_wall.has_node("Polygon2D"):
			visual_effect = parent_wall.get_node("Polygon2D")
			print("  Found Polygon2D!")
		elif parent_wall.has_node("Sprite2D"):
			visual_effect = parent_wall.get_node("Sprite2D")
			print("  Found Sprite2D!")
		else:
			# Search through all children
			for child in parent_wall.get_children():
				if child is Polygon2D or child is Sprite2D:
					visual_effect = child
					print("  Found visual in children: ", child.name)
					break
		
		# CREATE A NEW OVERLAY instead of modulating existing
		if visual_effect and visual_effect is Polygon2D:
			print("  !!! CREATING NEW SHOCK OVERLAY at ", Time.get_ticks_msec(), "ms !!!")
			shock_overlay = Polygon2D.new()
			shock_overlay.polygon = visual_effect.polygon.duplicate()
			shock_overlay.color = shock_color
			shock_overlay.z_index = 1000  # Way above everything
			shock_overlay.name = "ShockOverlay"
			parent_wall.add_child(shock_overlay)
			print("  ✓ Shock overlay created successfully!")
			print("    - Overlay name: ", shock_overlay.name)
			print("    - Overlay color: ", shock_overlay.color)
			print("    - Overlay z_index: ", shock_overlay.z_index)
			print("    - Overlay polygon points: ", shock_overlay.polygon.size())
		else:
			print("  ERROR: No Polygon2D found or visual_effect is wrong type!")
			print("    visual_effect type: ", visual_effect.get_class() if visual_effect else "null")
		print("=== _create_shock_visual() COMPLETE ===")
	
	func _shock_player(player: Node2D):
		"""Apply shock damage, knockback, and control suspension to player"""
		shocked_players.append(player)
		
		print("ShockedWall: ⚡ PLAYER SHOCKED! ⚡")
		
		# Damage
		if player.has_method("take_damage"):
			player.take_damage(shock_damage)
			print("  Applied ", shock_damage, " damage")
		
		# Moderate knockback away from wall (reduced from 400 to 200)
		var knockback_dir = (player.global_position - parent_wall.global_position).normalized()
		if player is RigidBody2D:
			var reduced_knockback = shock_knockback * 0.5  # Half the knockback
			player.apply_central_impulse(knockback_dir * reduced_knockback)
			print("  Applied knockback: ", reduced_knockback)
		
		# Suspend player control briefly - ADDED DEBUG
		print("  Checking for suspend_control method...")
		print("    Player has method: ", player.has_method("suspend_control"))
		if player.has_method("suspend_control"):
			print("  ⚡ CALLING suspend_control(", control_suspend_duration, ") ⚡")
			player.suspend_control(control_suspend_duration)
			print("  ✓ suspend_control() called successfully")
		else:
			print("  ERROR: Player doesn't have suspend_control method!")
		
		# Visual feedback on player (optional - could add electric sparks)
		_create_shock_spark_effect(player.global_position)
	
	func _create_shock_spark_effect(position: Vector2):
		"""Create visual spark effect at shock point"""
		# Simple expanding circle
		var spark = Node2D.new()
		spark.global_position = position
		spark.z_index = 200
		get_tree().root.add_child(spark)
		
		# You could add a Sprite2D or particles here
		# For now, just a quick flash
		var tween = create_tween()
		tween.tween_callback(spark.queue_free).set_delay(0.2)
	
	func _expire():
		"""Remove shock effect when timer expires"""
		print("ShockedWall: Shock expired")
		
		# Remove the overlay
		if shock_overlay and is_instance_valid(shock_overlay):
			shock_overlay.queue_free()
			print("  Removed shock overlay")
		
		queue_free()
