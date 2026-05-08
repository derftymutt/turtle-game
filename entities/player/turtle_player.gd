extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30.0
@export var max_velocity: float = 2500.0
@export var kick_animation_duration: float = 0.25
@export var kick_animation_duration_with_ufo_piece: float = 0.5

# Shooting properties
@export var shoot_cooldown: float = 0.25
@export var rapid_fire_shoot_cooldown: float = 0.1
@export var bullet_speed: float = 500.0
@export var bullet_scene: PackedScene
@export var phase_bullet_scene: PackedScene

# Thrust strengths
@export var horizontal_thrust: float = 175.0
@export var upward_thrust: float = 75.0
@export var downward_thrust: float = 225.0

@export var horizontal_thrust_with_piece: float = 75.0
@export var upward_thrust_with_piece: float = 25.0
@export var downward_thrust_with_piece: float = 125.0

# Health
@export var max_health: float = 100.0
var current_health: float = 100.0

# Super Speed System
@export_group("Super Speed")
@export var super_speed_threshold: float = 300.0  # Velocity needed to activate
@export var super_speed_damage: float = 100.0     # Damage dealt to enemies
# Single source of truth for all super speed visuals (glow, trail, burst).
# Values above 1.0 are intentional — they push into HDR/bloom territory.
@export var super_speed_color: Color = Color(0.778, 1.504, 0.0)
@export var super_speed_cooldown_duration: float = 0.5
var is_super_speed: bool = false
var is_super_speed_cooldown: bool = false
var super_speed_cooldown_timer: float = 0.0
var super_speed_trail_timer: float = 0.0
var super_speed_trail_interval: float = 0.01

# Internal state
var can_thrust: bool = true
var can_shoot: bool = true
var thrust_timer: float = 0.0
var shoot_timer: float = 0.0
var current_kick_animation_duration: float = kick_animation_duration
# Guards against multiple simultaneous damage flashes fighting over modulate.
# Drowning calls take_damage() every frame; without this, hundreds of competing
# awaits all write Color.RED before any of them can write Color.WHITE back.
var _is_flashing: bool = false
var _health_restore_flash_timer: float = 0.0

# Ocean reference
var ocean: Ocean = null

# HUD reference
var hud: HUD = null

# Wall contact tracking for energy recovery bonus
var touching_walls: Array = []
var _is_underwater: bool = true  # updated every physics frame; used by sparkle emitter

# Super speed damage detection
var super_speed_area: Area2D = null

# Wall-rest energy recharge particles
var rest_particles: CPUParticles2D = null

var active_shoot_cooldown: float = shoot_cooldown

# Powerup states
var shield_active: bool = false
var shield_duration: float = 10.0
var shield_timer: float = 0.0

var air_reserve_bonus: float = 20.0

var energy_freeze_active: bool = false
var energy_freeze_duration: float = 10.0
var energy_freeze_timer: float = 0.0
var energy_freeze_tween: Tween = null

var rapid_fire_active: bool = false
var rapid_fire_duration: float = 10.0
var rapid_fire_timer: float = 0.0

var is_player_controlling_rotation: bool = false

var control_suspended: bool = false
var control_suspend_timer: float = 0.0

# Alien Tech state
var inertia_dampener_active: bool = false
var inertia_dampener_timer: float = 0.0

var lateral_thrust_active: bool = false
var lateral_thrust_timer: float = 0.0
const LATERAL_THRUST_DURATION: float = 0.05
const LATERAL_THRUST_FORCE: float = 600.0

const TRANSPORTER_DISTANCE: float = 150.0
const TRANSPORTER_INVINCIBLE_DURATION: float = 0.75
const TRANSPORTER_WINDUP: float = 0.18
var transporter_invincible: bool = false
var transporter_invincible_timer: float = 0.0
var _transporter_windup: bool = false
var _transporter_canceled: bool = false

const CONTACT_IFRAME_DURATION: float = 0.75
var _contact_iframes_active: bool = false
var _contact_iframes_timer: float = 0.0

const BUBBLE_SHIELD_REGEN_DURATION: float = 15.0
var bubble_shield_hp: float = 0.0
var bubble_shield_regen_timer: float = 0.0
var _bubble_flash_timer: float = 0.0

# Bumper Magnet
const BUMPER_MAGNET_DURATION: float = 2.0
const BUMPER_MAGNET_RADIUS: float = 30.0       # seek range beyond bumper surface
const BUMPER_MAGNET_PULL_SPEED: float = 280.0  # approach speed while seeking
const BUMPER_MAGNET_ORBIT_SPEED: float = 5.5   # radians/sec while orbiting
const BUMPER_MAGNET_PLAYER_RADIUS: float = 7.0 # must match CircleShape2D radius

var _bumper_magnet_active: bool = false
var _bumper_magnet_timer: float = 0.0
var _bumper_magnet_slot: int = -1
var _bumper_magnet_attached: bool = false
var _bumper_magnet_target: Node2D = null
var _bumper_magnet_angle: float = 0.0
var _bumper_magnet_attach_speed: float = 0.0

# Flipper Velcro
const FLIPPER_VELCRO_SLIDE_SPEED: float = 50.0
const FLIPPER_VELCRO_PLAYER_OFFSET: float = 13.0  # capsule_radius(6) + player_radius(7)
# Arm travel range (px from flipper pivot along arm_dir).
# MIN: pivot-side end of capsule cylinder (center 12 - half_height 10.5 = 1.5)
# MAX: extended past the capsule tip cap so the turtle can reach the very end
const FLIPPER_VELCRO_ARM_MIN_T: float = 1.5
const FLIPPER_VELCRO_ARM_MAX_T: float = 30.0   # capsule tip (22.5) + cap radius (6) ≈ 28

var _flipper_velcro_latched: bool = false
var _flipper_velcro_target: Node2D = null   # always a FlipperBase at runtime
var _flipper_velcro_t: float = 12.0         # px along arm_dir from pivot
var _flipper_velcro_normal_side: float = 1.0  # which side of arm (+1 or -1)

# Dermal Regenerator
const DERMAL_REGEN_HEAL: float = 60.0
const DERMAL_REGEN_CHANNEL_DURATION: float = 1.0

var _dermal_regen_active: bool = false
var _dermal_regen_timer: float = 0.0
var _dermal_regen_slot: int = -1
var _dermal_regen_used: bool = false   # true after one successful heal per level

# Deflector Shield
const DEFLECTOR_SHIELD_DURATION: float = 5.0    # seconds active — tweak for feel
const DEFLECTOR_SHIELD_RADIUS:   float = 35.0   # px repulsion radius — tweak for feel
const DEFLECTOR_SHIELD_FORCE:    float = 1000.0 # repulsion force — tweak for feel

var deflector_shield_active: bool = false
var deflector_shield_timer:  float = 0.0
var _deflector_area: Area2D = null
var _deflector_visual: Line2D = null

# Powerup Replicator
var _using_replicator: bool = false  # guard to prevent recursive storage on replicator-use

# Time Freeze
var time_freeze_active: bool = false

# Thing Bringer
const THING_BRINGER_RADIUS: float = 30.0
const THING_BRINGER_PULL_SPEED: float = 220.0
var time_freeze_timer: float = 0.0
var _time_frozen_bodies: Array = []

# ---------------------------------------------------------------------------
# 8-DIRECTIONAL SPRITE SYSTEM
# ---------------------------------------------------------------------------
# Maps angle buckets to animation name suffixes.
# Godot's Vector2.angle() returns 0 at East, increasing clockwise.
# We offset by 22.5 degrees so each direction owns an equal +/-22.5 degree zone.
#
#   Index:  0    1     2    3     4    5     6    7
#   Dir:    e    se    s    sw    w    nw    n    ne
#   Angle:  0    45    90   135   180  225   270  315
#
const DIRECTION_SUFFIXES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

# The direction the turtle is currently facing. Persists between actions so
# idle always shows the correct facing direction after a kick or shoot.
var facing_direction: String = "s"  # Default: face downward into the water

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready():
	gravity_scale = 0.0
	linear_damp = 1.5
	angular_damp = 3.0
	mass = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	# CRITICAL: Enable contact monitoring for body_entered/exited signals.
	# Without this, collision signals won't fire even though physics works.
	contact_monitor = true
	max_contacts_reported = 4

	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 1 (player/world)
	# - Collision Mask: 1 + 3 (world + enemies)

	ocean = get_tree().get_first_node_in_group("ocean")
	if not ocean:
		push_warning("No Ocean found! Add Ocean scene to level and add it to 'ocean' group.")
		gravity_scale = 0.1

	hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		push_warning("No HUD found! Add HUD scene to level and add it to 'hud' group.")
	else:
		hud.update_health(current_health, max_health)

	add_to_group("player")

	_setup_super_speed_area()
	_setup_rest_particles()
	_setup_deflector_area()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	AlienTechManager.tech_activated.connect(_on_alien_tech_activated)
	AlienTechManager.tech_slots_changed.connect(_on_alien_tech_slots_changed_player)

	# Show the correct idle frame immediately on spawn
	_play_animation("idle")

	# Ensure the sprite always renders above motion trails (z_index = 10).
	# z_as_relative = false makes this an absolute z, independent of the parent body's z.
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.z_as_relative = false
		sprite.z_index = 15

# ---------------------------------------------------------------------------
# PHYSICS PROCESS
# ---------------------------------------------------------------------------

func _physics_process(delta):
	# Update cooldown timers
	if not can_thrust:
		thrust_timer -= delta
		if thrust_timer <= 0:
			can_thrust = true
			is_player_controlling_rotation = false

	if not can_shoot:
		shoot_timer -= delta
		if shoot_timer <= 0:
			can_shoot = true
			is_player_controlling_rotation = false

	# Super speed state
	# While magnetically attached the bumper's bounce impulse (applied by the
	# physics engine between frames) can exceed the super speed threshold every
	# frame, causing perpetual invincibility and broken visuals.  Force the entire
	# super speed system off for the duration of the attachment.
	var current_speed = linear_velocity.length()
	var was_super_speed = is_super_speed
	if _bumper_magnet_attached or _flipper_velcro_latched:
		was_super_speed = false  # prevents cooldown from triggering on the way out
		is_super_speed = false
		is_super_speed_cooldown = false
		super_speed_cooldown_timer = 0.0
	else:
		is_super_speed = current_speed >= super_speed_threshold

	if is_super_speed_cooldown:
		super_speed_cooldown_timer -= delta
		if super_speed_cooldown_timer <= 0:
			is_super_speed_cooldown = false

	if is_super_speed:
		_apply_super_speed_visuals(delta)
		if not was_super_speed:
			_create_super_speed_burst()
	elif is_super_speed_cooldown:
		_apply_cooldown_visuals(delta)
	else:
		_remove_super_speed_visuals()

	if was_super_speed and not is_super_speed and not is_super_speed_cooldown:
		is_super_speed_cooldown = true
		super_speed_cooldown_timer = super_speed_cooldown_duration

	# Powerup timers
	if shield_active:
		shield_timer -= delta
		if shield_timer <= 0:
			deactivate_shield()

	if energy_freeze_active:
		energy_freeze_timer -= delta
		if energy_freeze_timer <= 0:
			deactivate_energy_freeze()
			
	if rapid_fire_active:
		rapid_fire_timer -= delta
		if rapid_fire_timer <= 0:
			deactivate_rapid_fire()

	if inertia_dampener_active:
		inertia_dampener_timer -= delta
		if inertia_dampener_timer <= 0.0:
			inertia_dampener_active = false

	if lateral_thrust_active:
		lateral_thrust_timer -= delta
		if lateral_thrust_timer <= 0:
			lateral_thrust_active = false

	if transporter_invincible:
		transporter_invincible_timer -= delta
		if transporter_invincible_timer <= 0.0:
			transporter_invincible = false

	if _contact_iframes_active:
		_contact_iframes_timer -= delta
		if _contact_iframes_timer <= 0.0:
			_contact_iframes_active = false

	if AlienTechManager.is_tech_active(AlienTechRegistry.BUBBLE_SHIELD):
		if bubble_shield_hp == 0.0 and bubble_shield_regen_timer > 0.0:
			bubble_shield_regen_timer -= delta
			if bubble_shield_regen_timer <= 0.0:
				bubble_shield_hp = 1.0
		var _regen_ratio: float = 1.0 if bubble_shield_hp > 0.0 else clamp(1.0 - bubble_shield_regen_timer / BUBBLE_SHIELD_REGEN_DURATION, 0.0, 1.0)
		AlienTechManager.set_passive_bar(AlienTechRegistry.BUBBLE_SHIELD, _regen_ratio)

	if AlienTechManager.is_tech_active(AlienTechRegistry.THING_BRINGER):
		_update_thing_bringer()

	if _bumper_magnet_active:
		_update_bumper_magnet(delta)

	if _dermal_regen_active:
		_update_dermal_regen(delta)

	if deflector_shield_active:
		deflector_shield_timer -= delta
		var _ratio := deflector_shield_timer / DEFLECTOR_SHIELD_DURATION
		AlienTechManager.set_passive_bar(AlienTechRegistry.DEFLECTOR_SHIELD, max(0.0, _ratio))
		_repel_deflected_bodies(delta)
		if deflector_shield_timer <= 0.0:
			deflector_shield_active = false
			AlienTechManager.clear_passive_bar(AlienTechRegistry.DEFLECTOR_SHIELD)
			if _deflector_visual:
				_deflector_visual.visible = false

	if time_freeze_active:
		time_freeze_timer -= delta
		AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_FREEZE, max(0.0, time_freeze_timer / AlienTechManager.TIME_FREEZE_ACTIVE_DURATION))
		if time_freeze_timer <= 0.0:
			_unfreeze_world_bodies()

	# Ocean physics — suppressed while pinned to a bumper or flipper
	if not _bumper_magnet_attached and not _flipper_velcro_latched:
		if ocean:
			apply_ocean_effects(delta)
		else:
			linear_velocity *= 0.98

	# Counter-rotate the sprite to cancel the physics body's rotation every frame.
	# The body can spin freely (correct flipper/bumper physics) but the sprite
	# always appears axis-aligned and pixel-perfect.
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.rotation = -rotation

	# HUD systems
	if hud:
		var depth = ocean.get_depth(global_position) if ocean else 0.0
		var is_underwater = depth > 3

		_is_underwater = is_underwater

		if is_underwater:
			var out_of_air = hud.drain_air(delta)
			if out_of_air:
				take_damage(10.0 * delta)
		else:
			hud.refill_air(delta)

		var at_surface: bool = not is_underwater
		hud.recover_energy(delta, touching_walls.size() > 0 or at_surface)

	_update_rest_particles()

	# Control suspension timer — runs even while suspended so it keeps counting down
	control_suspend_timer -= delta
	if control_suspend_timer <= 0 and control_suspended:
		control_suspended = false
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.scale = Vector2.ONE

	if control_suspended:
		if _flipper_velcro_latched:
			_cancel_flipper_velcro()
		return

	# Flipper Velcro: hold-based, intercepts input before normal movement
	var _fv_slot := AlienTechManager.get_slot_index_for_tech(AlienTechRegistry.FLIPPER_VELCRO)
	if _fv_slot != -1:
		var fv_action := _slot_action(_fv_slot)
		if Input.is_action_pressed(fv_action):
			_update_flipper_velcro(delta)
		elif _flipper_velcro_latched:
			_launch_from_flipper_velcro()
		if _flipper_velcro_latched:
			return

	# Input
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	var shoot_input = Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)

	# Movement — check energy unless energy freeze is active
	var can_actually_thrust = can_thrust
	if hud and movement_input.length() > 0.1 and not energy_freeze_active:
		can_actually_thrust = can_actually_thrust and hud.can_thrust()

	if movement_input.length() > 0.1 and can_actually_thrust:
		apply_thrust(movement_input.normalized())

	if shoot_input.length() > 0.1 and can_shoot:
		shoot(shoot_input.normalized())
		
	# Drop carried UFO piece on button press (intentional = grace period before re-pickup)
	if Input.is_action_just_pressed("drop_piece"):
		if GameManager.is_carrying_piece and GameManager.carried_piece:
			GameManager.carried_piece.drop_piece(true)

	# Alien Tech active slot buttons
	if Input.is_action_just_pressed("tech_slot_left"):
		if _fv_slot != 0:
			AlienTechManager.try_activate_slot(0)
	if Input.is_action_just_pressed("tech_slot_right"):
		if _fv_slot != 1:
			AlienTechManager.try_activate_slot(1)

	# Bumper magnet: release button → launch
	if _bumper_magnet_active:
		var magnet_action := "tech_slot_left" if _bumper_magnet_slot == 0 else "tech_slot_right"
		if Input.is_action_just_released(magnet_action):
			_launch_from_bumper()

	# While attached the orbit function owns position/velocity — skip normal movement
	if _bumper_magnet_attached:
		return

	# Clamp velocity
	if linear_velocity.length() > max_velocity:
		linear_velocity = linear_velocity.normalized() * max_velocity

	# Return to directional idle when nearly stopped and no action is running
	if can_thrust and linear_velocity.length() < 50:
		var target_idle = "idle_" + facing_direction
		if animated_sprite and animated_sprite.animation != target_idle:
			animated_sprite.play(target_idle)

# ---------------------------------------------------------------------------
# SPRITE MODULATE (runs every rendered frame — single source of truth)
# ---------------------------------------------------------------------------

func _process(delta: float):
	if _health_restore_flash_timer > 0.0:
		_health_restore_flash_timer -= delta
	if _bubble_flash_timer > 0.0:
		_bubble_flash_timer -= delta
	_update_sprite_modulate()
	if deflector_shield_active and _deflector_visual:
		var pulse := (sin(Time.get_ticks_msec() * 0.008) + 1.0) * 0.5
		_deflector_visual.default_color = Color(0.3, 0.7, 1.0, 0.4 + pulse * 0.45)

func _update_sprite_modulate():
	var sprite = $AnimatedSprite2D
	if not sprite or not is_instance_valid(sprite):
		return
	if _health_restore_flash_timer > 0.0:
		sprite.modulate = Color.GREEN
	elif _transporter_windup:
		var flash = (sin(Time.get_ticks_msec() * 0.25) + 1.0) * 0.5
		sprite.modulate = Color(0.6, 0.3, 1.0).lerp(Color.WHITE, flash * 0.6)
	elif transporter_invincible:
		var flash = (sin(Time.get_ticks_msec() * 0.06) + 1.0) * 0.5
		sprite.modulate = Color(0.6, 0.3, 1.0).lerp(Color.WHITE, flash)
	elif _bubble_flash_timer > 0.0:
		sprite.modulate = Color(0.3, 0.9, 1.0)
	elif _dermal_regen_active:
		var progress := _dermal_regen_timer / DERMAL_REGEN_CHANNEL_DURATION
		var flash := (sin(Time.get_ticks_msec() * (0.06 + progress * 0.18)) + 1.0) * 0.5
		sprite.modulate = Color(0.1, 0.9, 0.3).lerp(Color(0.7, 1.0, 0.7), flash)
	elif _bumper_magnet_active:
		if _bumper_magnet_attached:
			# Slow amber pulse while orbiting
			var flash := (sin(Time.get_ticks_msec() * 0.04) + 1.0) * 0.5
			sprite.modulate = Color(1.0, 0.6, 0.0).lerp(Color(1.0, 1.0, 0.2), flash)
		else:
			# Fast golden flicker while seeking
			var flash := (sin(Time.get_ticks_msec() * 0.12) + 1.0) * 0.5
			sprite.modulate = Color(1.0, 0.85, 0.0).lerp(Color(1.0, 1.0, 0.5), flash)
	elif _flipper_velcro_latched:
		var flash := (sin(Time.get_ticks_msec() * 0.06) + 1.0) * 0.5
		sprite.modulate = Color(0.2, 1.0, 0.6).lerp(Color(0.6, 1.0, 0.85), flash)
	elif deflector_shield_active:
		var flash := (sin(Time.get_ticks_msec() * 0.04) + 1.0) * 0.5
		sprite.modulate = Color(0.3, 0.7, 1.0).lerp(Color.WHITE, flash * 0.5)
	elif time_freeze_active:
		var flash := (sin(Time.get_ticks_msec() * 0.05) + 1.0) * 0.5
		sprite.modulate = Color(0.5, 0.85, 1.0).lerp(Color.WHITE, flash * 0.4)
	elif shield_active or energy_freeze_active or rapid_fire_active:
		sprite.modulate = _get_powerup_flash_color()
	elif is_super_speed:
		sprite.modulate = super_speed_color
	elif is_super_speed_cooldown:
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		sprite.modulate = super_speed_color.lerp(Color.WHITE, 1.0 - fade_factor)
	else:
		sprite.modulate = Color.WHITE

	# Iframe blink: flicker alpha on top of whatever color was set above.
	# FlashOverlay and sprite modulate are separate nodes so they can coexist.
	if _contact_iframes_active:
		sprite.modulate.a = 1.0 if (int(Time.get_ticks_msec() / 80) % 2 == 0) else 0.25

# ---------------------------------------------------------------------------
# OCEAN
# ---------------------------------------------------------------------------

func apply_ocean_effects(_delta: float):
	"""Apply depth-based buoyancy and water drag"""
	# Lateral Thrust: suppress all ocean forces during dash window
	if lateral_thrust_active:
		return

	var depth = ocean.get_depth(global_position)

	# Inertia Dampener in air: skip gravity calculation entirely and treat air
	# as shallow ocean so the turtle can swim freely above the surface.
	if inertia_dampener_active and depth <= 0:
		apply_central_force(Vector2(0, -ocean.shallow_buoyancy * mass))
		linear_velocity *= ocean.water_drag
		linear_damp = 1.0
		return

	# Inertia Dampener underwater: clamp depth to shallow zone so deep buoyancy never fires
	if inertia_dampener_active:
		depth = min(depth, ocean.shallow_depth - 1.0)

	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass)
	apply_central_force(Vector2(0, -buoyancy_force))

	if depth > 0:
		linear_velocity *= ocean.water_drag
		var depth_factor = clamp(depth / 100.0, 0.0, 1.0)
		linear_damp = lerp(1.0, 2.0, depth_factor)
	else:
		linear_velocity *= ocean.air_drag
		linear_damp = 1.2

# ---------------------------------------------------------------------------
# MOVEMENT & SHOOTING
# ---------------------------------------------------------------------------

func return_to_idle_after_delay():
	await get_tree().create_timer(current_kick_animation_duration).timeout
	if not is_inside_tree():
		return
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.play("idle_" + facing_direction)

func apply_thrust(direction: Vector2):
	var kick_direction = -direction if GameSettings.thrust_inverted else direction

	# No upward thrust in air (dampener converts air to shallow ocean, so allow all directions)
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0 and not inertia_dampener_active:
		return

	if hud and not energy_freeze_active and not hud.try_thrust():
		return

	is_player_controlling_rotation = true

	# Update facing direction using kick_direction so thrust_inverted is accounted for
	facing_direction = _vector_to_direction_suffix(kick_direction)

	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play("kick_" + facing_direction)

	# Thrust strength
	var thrust_strength: float
	if GameManager.is_carrying_piece and GameManager.carried_piece:
		thrust_strength = horizontal_thrust_with_piece
		if kick_direction.y < 0:
			thrust_strength = upward_thrust_with_piece
		elif kick_direction.y > 0:
			thrust_strength = downward_thrust_with_piece
	else:
		thrust_strength = horizontal_thrust
		if kick_direction.y < 0:
			thrust_strength = upward_thrust
		elif kick_direction.y > 0:
			thrust_strength = downward_thrust

	linear_velocity += kick_direction * thrust_strength

	can_thrust = false
	thrust_timer = current_kick_animation_duration

func shoot(direction: Vector2):
	if bullet_scene == null:
		push_warning("No bullet scene assigned!")
		return

	is_player_controlling_rotation = true

	# Update facing so idle returns to the correct pose afterward
	facing_direction = _vector_to_direction_suffix(direction)

	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play("shoot_" + facing_direction)
		return_to_idle_after_delay()

	# Phase Shifter: hold slot button while shooting → fire phase bullet instead
	var _phase_slot := AlienTechManager.get_slot_index_for_tech(AlienTechRegistry.PHASE_SHIFTER)
	if _phase_slot != -1 and Input.is_action_pressed(_slot_action(_phase_slot)):
		if AlienTechManager.consume_phase_bullet():
			_shoot_phase_bullet(direction)
		can_shoot = false
		shoot_timer = active_shoot_cooldown
		return

	var bullet = bullet_scene.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = _safe_bullet_spawn(direction)
	bullet.set_velocity(direction * bullet_speed)
	if AlienTechManager.is_tech_active(AlienTechRegistry.SALIVA_NANOBOTS):
		bullet.is_homing = true
		bullet.damage = 20.0

	can_shoot = false
	shoot_timer = active_shoot_cooldown

func _slot_action(slot_index: int) -> String:
	return "tech_slot_left" if slot_index == 0 else "tech_slot_right"

func _shoot_phase_bullet(direction: Vector2) -> void:
	if phase_bullet_scene == null:
		push_warning("TurtlePlayer: phase_bullet_scene not assigned in Inspector!")
		return
	var bullet = phase_bullet_scene.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = _safe_bullet_spawn(direction)
	bullet.set_velocity(direction * bullet_speed)

func _safe_bullet_spawn(direction: Vector2) -> Vector2:
	"""Raycast in the shoot direction and spawn the bullet just before any wall,
	   so it can never teleport through geometry."""
	const DESIRED_OFFSET: float = 15.0  # Ideal distance from turtle centre
	const MIN_OFFSET: float = 4.0       # Never spawn closer than this (avoids self-collision)

	var space_state = get_world_2d().direct_space_state
	var ray = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + direction * DESIRED_OFFSET
	)
	# Layer 1 = world/walls. Add other solid layers here if needed (e.g. 1 | 2).
	ray.collision_mask = 1
	ray.exclude = [self]

	var hit = space_state.intersect_ray(ray)
	if hit:
		# Pull the spawn point back from the wall surface so the bullet
		# starts on the correct side with a small safe margin.
		var distance_to_wall = global_position.distance_to(hit.position)
		var safe_distance = max(MIN_OFFSET, distance_to_wall - 2.0)
		return global_position + direction * safe_distance

	return global_position + direction * DESIRED_OFFSET

func apply_flipper_force(direction: Vector2, force_multiplier: float = 5.0):
	"""Apply strong pinball-like forces from flippers"""
	apply_central_impulse(direction * thrust_force * force_multiplier)

# ---------------------------------------------------------------------------
# HEALTH
# ---------------------------------------------------------------------------

func take_damage(amount: float, use_iframes: bool = false):
	if use_iframes and _contact_iframes_active:
		return
	if is_super_speed or is_super_speed_cooldown or shield_active or transporter_invincible or deflector_shield_active:
		return

	if AlienTechManager.is_tech_active(AlienTechRegistry.BUBBLE_SHIELD) and bubble_shield_hp > 0.0:
		bubble_shield_hp = 0.0
		bubble_shield_regen_timer = BUBBLE_SHIELD_REGEN_DURATION
		_bubble_flash_timer = 0.4
		return  # Shield absorbed — transporter windup NOT canceled

	# Real damage lands — cancel active techs that need aborting
	if _transporter_windup:
		_transporter_canceled = true
	if _bumper_magnet_active:
		_cancel_bumper_magnet()
	if _dermal_regen_active:
		_cancel_dermal_regen()
	if _flipper_velcro_latched:
		_cancel_flipper_velcro()

	current_health -= amount

	if hud:
		hud.update_health(current_health, max_health)

	# Drop piece and check death BEFORE any await — these must fire immediately
	# and must not be triggered multiple times from repeated per-frame damage.
	if GameManager.is_carrying_piece and GameManager.carried_piece:
		GameManager.carried_piece.drop_piece()

	if current_health <= 0:
		die()
		return  # die() handles everything from here

	if use_iframes:
		_contact_iframes_active = true
		_contact_iframes_timer = CONTACT_IFRAME_DURATION

	_flash(Color.RED, 0.3)

func restore_health(amount: float):
	"""Restore health (e.g., from health plants)"""
	current_health = min(max_health, current_health + amount)

	if hud:
		hud.update_health(current_health, max_health)

	_health_restore_flash_timer = 0.2
	print("Health restored! Current: ", current_health, "/", max_health)

func die():
	var final_score = 0
	if hud:
		final_score = hud.current_score

	GameManager.current_score = final_score

	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("on_player_died"):
		level.on_player_died(final_score)
	else:
		var game_over_screen = get_tree().get_first_node_in_group("game_over_screen")
		if game_over_screen and game_over_screen.has_method("show_game_over"):
			game_over_screen.show_game_over(final_score, GameManager.total_score)
		else:
			push_warning("No GameOverScreen found!")
			await get_tree().create_timer(2.0).timeout
			get_tree().reload_current_scene()

# ---------------------------------------------------------------------------
# COLLISION TRACKING
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node):
	if body.is_in_group("walls") or body.is_in_group("flippers"):
		if not body in touching_walls:
			touching_walls.append(body)

func _on_body_exited(body: Node):
	if body in touching_walls:
		touching_walls.erase(body)

func add_score(points: int):
	"""Called by collectibles when picked up"""
	if hud:
		hud.add_score(points)

# ---------------------------------------------------------------------------
# DIRECTION HELPERS
# ---------------------------------------------------------------------------

func _vector_to_direction_suffix(direction: Vector2) -> String:
	# Vector2.angle() returns radians: 0 = East, increasing clockwise.
	# Convert to 0-360 degrees then offset by 22.5 so each 45-degree bucket
	# is perfectly centred on its cardinal or diagonal direction.
	var angle_deg = rad_to_deg(direction.angle())
	angle_deg = fmod(angle_deg + 360.0 + 22.5, 360.0)
	var index = int(angle_deg / 45.0) % 8
	return DIRECTION_SUFFIXES[index]

func _play_animation(anim_type: String):
	"""Play a directional animation using the current facing_direction.
	   anim_type should be 'idle', 'kick', or 'shoot'."""
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite:
		animated_sprite.play(anim_type + "_" + facing_direction)

# ---------------------------------------------------------------------------
# SUPER SPEED AREA
# ---------------------------------------------------------------------------

func _setup_super_speed_area():
	"""Create an Area2D for detecting enemies during super speed without physics collision"""
	super_speed_area = Area2D.new()
	super_speed_area.name = "SuperSpeedArea"

	# NOTE: Set programmatically only because this node is created at runtime.
	# All other collision layers are set in the Inspector per project rules.
	super_speed_area.collision_layer = 0
	super_speed_area.collision_mask = 4  # Layer 3 = enemies

	var collision_shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 12.0
	collision_shape.shape = circle

	super_speed_area.add_child(collision_shape)
	add_child(super_speed_area)

	super_speed_area.body_entered.connect(_on_super_speed_area_entered)

func _setup_rest_particles():
	"""Create yellow upward-drifting particles shown while resting on a wall
	   to telegraph the accelerated energy recovery mechanic."""
	rest_particles = CPUParticles2D.new()
	rest_particles.name = "RestParticles"

	rest_particles.emitting = false
	rest_particles.amount = 14
	rest_particles.lifetime = 0.9
	rest_particles.one_shot = false
	rest_particles.explosiveness = 0.0
	rest_particles.randomness = 0.5

	# Emit from a small disc around the turtle's centre
	rest_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rest_particles.emission_sphere_radius = 8.0

	# Drift upward with some spread
	rest_particles.direction = Vector2(0.0, -1.0)
	rest_particles.spread = 50.0
	rest_particles.gravity = Vector2(0.0, -20.0)
	rest_particles.initial_velocity_min = 15.0
	rest_particles.initial_velocity_max = 35.0

	# Size — small sparks that fade out
	rest_particles.scale_amount_min = 1.5
	rest_particles.scale_amount_max = 3.0

	# Yellow colour, fading to transparent
	rest_particles.color = Color(1.0, 1.0, 0.1, 0.9)
	rest_particles.color_ramp = _make_yellow_fade_gradient()

	# Render above the turtle sprite (sprite z_index = 15)
	rest_particles.z_as_relative = false
	rest_particles.z_index = 20

	add_child(rest_particles)

func _make_yellow_fade_gradient() -> Gradient:
	var g = Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.2, 1.0))    # bright yellow at birth
	g.set_color(1, Color(1.0, 1.0, 0.0, 0.0))    # yellow, fully transparent at death
	return g

func _update_rest_particles():
	if not rest_particles:
		return
	var energy_not_full = hud and hud.current_energy < hud.max_energy
	var should_emit = (touching_walls.size() > 0 or not _is_underwater) and energy_not_full
	if rest_particles.emitting != should_emit:
		rest_particles.emitting = should_emit

func _on_super_speed_area_entered(body: Node2D):
	if not is_super_speed and not shield_active:
		return

	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(super_speed_damage)
		var bounce_direction = (global_position - body.global_position).normalized()
		apply_central_impulse(bounce_direction * 100)

# ---------------------------------------------------------------------------
# SUPER SPEED VISUALS
# ---------------------------------------------------------------------------

func _get_powerup_flash_color() -> Color:
	var flash = (sin(Time.get_ticks_msec() * 0.031) + 1.0) * 0.5

	if shield_active:
		return Color(3.0, 3.0, 3.0, 1.0).lerp(Color(0.6, 0.6, 0.6, 1.0), flash)
	elif energy_freeze_active:
		return Color(8.05, 7.925, 0.0, 1.0).lerp(Color(0.3, 0.25, 0.0, 1.0), flash)
	elif rapid_fire_active:
		return Color(2.5, 0.0, 2.5, 1.0).lerp(Color(0.6, 0.0, 0.6, 1.0), flash)
	return Color.WHITE

func _apply_super_speed_visuals(delta: float):
	var sprite = $AnimatedSprite2D
	if sprite:
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.4
		sprite.scale = Vector2.ONE * pulse

	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		_spawn_motion_trail(1.0)

func _apply_cooldown_visuals(delta: float):
	var sprite = $AnimatedSprite2D
	if sprite:
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.02) * (0.2 * fade_factor)
		sprite.scale = Vector2.ONE * pulse

	super_speed_trail_timer += delta
	if super_speed_trail_timer >= super_speed_trail_interval:
		super_speed_trail_timer = 0.0
		var fade_factor = super_speed_cooldown_timer / super_speed_cooldown_duration
		_spawn_motion_trail(fade_factor)

func _remove_super_speed_visuals():
	var sprite = $AnimatedSprite2D
	if sprite and is_instance_valid(sprite):
		sprite.scale = Vector2.ONE

func _spawn_motion_trail(intensity: float = 1.0):
	var sprite = $AnimatedSprite2D
	if not sprite:
		return

	var trail = Sprite2D.new()
	trail.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	# Use the sprite's global_position, NOT the body's global_position.
	# The AnimatedSprite2D may have a local offset from the body origin;
	# using the body origin causes trails to appear shifted.
	trail.global_position = sprite.global_position
	trail.global_rotation = sprite.global_rotation
	trail.scale = sprite.scale * 1.2
	var trail_color = super_speed_color
	trail_color.a = 0.8 * intensity
	trail.modulate = trail_color
	trail.z_index = 10

	get_parent().add_child(trail)

	var fade_duration = max(0.2, 0.5 * intensity)
	var tween = create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(trail.queue_free)

func _create_super_speed_burst():
	var sprite = $AnimatedSprite2D
	for i in range(8):
		var burst_sprite = Sprite2D.new()
		if sprite:
			burst_sprite.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)

		burst_sprite.global_position = global_position
		burst_sprite.rotation = randf() * TAU
		var burst_color = super_speed_color
		burst_color.a = 0.9
		burst_sprite.modulate = burst_color
		burst_sprite.z_index = 10

		get_parent().add_child(burst_sprite)

		var tween = create_tween()
		tween.set_parallel(true)
		var burst_dir = Vector2(cos(i * TAU / 8), sin(i * TAU / 8))
		tween.tween_property(burst_sprite, "global_position", global_position + burst_dir * 50, 0.4)
		tween.tween_property(burst_sprite, "scale", Vector2.ONE * 2.0, 0.4)
		tween.tween_property(burst_sprite, "modulate:a", 0.0, 0.4)
		tween.tween_callback(burst_sprite.queue_free)

# ---------------------------------------------------------------------------
# POWERUPS
# ---------------------------------------------------------------------------

func apply_powerup(powerup_type: int):
	print("APPLYING POWERUP TYPE: ", powerup_type)
	if AlienTechManager.has_tech(AlienTechRegistry.POWERUP_REPLICATOR) and not _using_replicator:
		AlienTechManager.store_replicated_powerup(powerup_type)
	match powerup_type:
		0:  activate_shield()
		1:  activate_air_reserve()
		2:  activate_energy_freeze()
		3:  activate_rapid_fire()
		_:  push_error("Unknown powerup type: ", powerup_type)

func activate_shield():
	shield_active = true
	shield_timer = shield_duration
	print("SHIELD ACTIVATED! Invincible for ", shield_duration, " seconds!")

func deactivate_shield():
	shield_active = false
	print("Shield expired")

func activate_air_reserve():
	if hud:
		hud.max_air += air_reserve_bonus
		hud.current_air = hud.max_air
		hud.update_air(hud.current_air, hud.max_air)
		print("AIR RESERVE! +", air_reserve_bonus, " max air! (new max: ", hud.max_air, ")")
	else:
		push_error("No HUD found! Can't apply air reserve.")

func activate_energy_freeze():
	energy_freeze_active = true
	energy_freeze_timer = energy_freeze_duration
	print("ENERGY FREEZE! No energy drain for ", energy_freeze_duration, " seconds!")

func deactivate_energy_freeze():
	energy_freeze_active = false
	print("Energy freeze expired")
			
func _flash(_color: Color, duration: float):
	if _is_flashing:
		return
	_is_flashing = true
	var overlay = $FlashOverlay
	if overlay:
		overlay.modulate.a = 0.9  # Semi-transparent so original sprite shows through
		var tween = create_tween()
		tween.tween_property(overlay, "modulate:a", 0.0, duration)
		await get_tree().create_timer(duration).timeout
	if not is_inside_tree():
		return
	_is_flashing = false
	
func activate_rapid_fire():
	rapid_fire_active = true
	rapid_fire_timer = rapid_fire_duration
	active_shoot_cooldown = rapid_fire_shoot_cooldown
	print("RAPID FIRE activated", rapid_fire_duration, " seconds!")

func deactivate_rapid_fire():
	rapid_fire_active = false
	active_shoot_cooldown = shoot_cooldown
	print("Rapid Fire expired")

# ---------------------------------------------------------------------------
# ALIEN TECH
# ---------------------------------------------------------------------------

func _on_alien_tech_activated(slot_index: int, tech_id: String):
	match tech_id:
		AlienTechRegistry.INERTIA_DAMPENER:
			_activate_inertia_dampener()
		AlienTechRegistry.LATERAL_THRUST:
			_activate_lateral_thrust()
		AlienTechRegistry.TRANSPORTER:
			_activate_transporter()
		AlienTechRegistry.BUMPER_MAGNET:
			_start_bumper_magnet(slot_index)
		AlienTechRegistry.DERMAL_REGEN:
			_start_dermal_regen(slot_index)
		AlienTechRegistry.DEFLECTOR_SHIELD:
			_activate_deflector_shield()
		AlienTechRegistry.POWERUP_REPLICATOR:
			_use_powerup_replicator()
		AlienTechRegistry.TIME_FREEZE:
			_activate_time_freeze()
		AlienTechRegistry.SHOCKWAVE:
			_activate_shockwave()

func _activate_inertia_dampener():
	inertia_dampener_active = true
	inertia_dampener_timer = AlienTechManager.INERTIA_DAMPENER_ACTIVE_DURATION

func _activate_lateral_thrust():
	lateral_thrust_active = true
	lateral_thrust_timer = LATERAL_THRUST_DURATION

	# Determine left or right purely from horizontal input, then facing, then velocity.
	var h_input := Input.get_axis("move_left", "move_right")
	var thrust_sign: float

	if abs(h_input) > 0.1:
		thrust_sign = sign(h_input)
		if GameSettings.thrust_inverted:
			thrust_sign = -thrust_sign
	else:
		# Derive from facing direction suffix ("e"/"ne"/"se" → right, rest → left)
		var facing_vec = _direction_suffix_to_vector(facing_direction)
		if facing_vec.x != 0.0:
			thrust_sign = sign(facing_vec.x)
		elif linear_velocity.x != 0.0:
			thrust_sign = sign(linear_velocity.x)
		else:
			thrust_sign = 1.0  # default right if no signal

	linear_velocity = Vector2.ZERO
	apply_central_impulse(Vector2(thrust_sign * LATERAL_THRUST_FORCE, 0.0))
	_flash(Color.WHITE, 0.2)

func _activate_transporter():
	# Direction priority: active input > current velocity > facing direction
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var dir: Vector2
	if movement_input.length() > 0.1:
		dir = movement_input.normalized()
		if GameSettings.thrust_inverted:
			dir = -dir
	elif linear_velocity.length() > 30.0:
		dir = linear_velocity.normalized()
	else:
		dir = _direction_suffix_to_vector(facing_direction)

	# Windup: brief visual telegraph — player is vulnerable during this window
	_transporter_windup = true
	_transporter_canceled = false
	await get_tree().create_timer(TRANSPORTER_WINDUP).timeout
	if not is_inside_tree():
		return
	_transporter_windup = false

	if _transporter_canceled:
		_transporter_canceled = false
		return

	# Teleport: ignore all regular geometry, clamp to world boundaries.
	# If there's no room (already at the edge), the clamp lands us at the wall — player's problem.
	var raw_target = global_position + dir * TRANSPORTER_DISTANCE
	global_position = _clamp_to_boundaries(raw_target)
	linear_velocity *= 0.3
	transporter_invincible = true
	transporter_invincible_timer = TRANSPORTER_INVINCIBLE_DURATION

	# Scale pop on arrival
	var sprite = $AnimatedSprite2D
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.35, 1.35), 0.07)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)

func _get_boundary_limits() -> Dictionary:
	# MARGIN must exceed player collision radius (7px).
	const MARGIN := 20.0
	var limits = {min_x = -INF, max_x = INF, max_y = INF}
	var root = get_tree().current_scene
	if not root:
		return limits
	var wb = root.get_node_or_null("WorldSafetyBoundaries")
	if not wb:
		return limits
	for bname in ["BoundaryLeft", "BoundaryRight", "BoundaryBottom"]:
		var node = wb.get_node_or_null(bname)
		if not node:
			continue
		var col: CollisionShape2D = null
		for child in node.get_children():
			if child is CollisionShape2D:
				col = child
				break
		if not col:
			continue
		var cx := col.global_position.x
		var cy := col.global_position.y
		var hw := 0.0
		var hh := 0.0
		if col.shape is RectangleShape2D:
			var sz = col.shape.size
			# If the CollisionShape2D is rotated ~90°/270°, world-space extents are swapped
			# relative to the local shape dimensions (e.g. BoundaryBottom uses a rotated wall shape).
			if abs(sin(col.global_rotation)) > 0.7:
				hw = sz.y * 0.5
				hh = sz.x * 0.5
			else:
				hw = sz.x * 0.5
				hh = sz.y * 0.5
		match bname:
			"BoundaryLeft":   limits.min_x = cx + hw + MARGIN
			"BoundaryRight":  limits.max_x = cx - hw - MARGIN
			"BoundaryBottom": limits.max_y = cy - hh - MARGIN
	return limits

func _is_outside_playfield(pos: Vector2) -> bool:
	var lim = _get_boundary_limits()
	return (lim.min_x > -INF and pos.x < lim.min_x) or \
		   (lim.max_x < INF  and pos.x > lim.max_x) or \
		   (lim.max_y < INF  and pos.y > lim.max_y)

func _clamp_to_boundaries(target_pos: Vector2) -> Vector2:
	var lim = _get_boundary_limits()
	return Vector2(
		clamp(target_pos.x, lim.min_x, lim.max_x),
		min(target_pos.y, lim.max_y)
	)

func _on_alien_tech_slots_changed_player(_slot_a: Dictionary, _slot_b: Dictionary):
	if AlienTechManager.is_tech_active(AlienTechRegistry.BUBBLE_SHIELD):
		if bubble_shield_hp == 0.0 and bubble_shield_regen_timer <= 0.0:
			bubble_shield_hp = 1.0

# ---------------------------------------------------------------------------
# DEFLECTOR SHIELD
# ---------------------------------------------------------------------------

func _setup_deflector_area() -> void:
	_deflector_area = Area2D.new()
	_deflector_area.name = "DeflectorArea"
	_deflector_area.collision_layer = 0
	_deflector_area.collision_mask = 4 | 8  # Layer 3 (enemies) + Layer 4 (projectiles)
	_deflector_area.monitoring = true
	_deflector_area.monitorable = false

	var _col := CollisionShape2D.new()
	var _circle := CircleShape2D.new()
	_circle.radius = DEFLECTOR_SHIELD_RADIUS
	_col.shape = _circle
	_deflector_area.add_child(_col)
	add_child(_deflector_area)

	_deflector_area.body_entered.connect(_on_deflector_body_entered)

	# Visual ring — a closed Line2D circle
	_deflector_visual = Line2D.new()
	_deflector_visual.name = "DeflectorVisual"
	var _pts: PackedVector2Array = []
	var _segs := 36
	for i in range(_segs + 1):
		var a := i * TAU / _segs
		_pts.append(Vector2(cos(a), sin(a)) * DEFLECTOR_SHIELD_RADIUS)
	_deflector_visual.points = _pts
	_deflector_visual.default_color = Color(0.3, 0.7, 1.0, 0.7)
	_deflector_visual.width = 1.5
	_deflector_visual.z_as_relative = false
	_deflector_visual.z_index = 12
	_deflector_visual.visible = false
	add_child(_deflector_visual)

func _activate_deflector_shield() -> void:
	deflector_shield_active = true
	deflector_shield_timer = DEFLECTOR_SHIELD_DURATION
	if _deflector_visual:
		_deflector_visual.visible = true

func _on_deflector_body_entered(body: Node2D) -> void:
	if not deflector_shield_active:
		return
	if body == self or body.is_in_group("player"):
		return
	var dir := (body.global_position - global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(dir * 500.0)
	elif body is CharacterBody2D:
		var cb := body as CharacterBody2D
		cb.velocity = dir * max(cb.velocity.length(), 250.0)
	elif body is AnimatableBody2D:
		# Immediate positional kick on entry — no physics forces on AnimatableBody2D
		body.global_position += dir * 12.0

func _repel_deflected_bodies(delta: float) -> void:
	if not _deflector_area:
		return
	for body in _deflector_area.get_overlapping_bodies():
		if body == self or body.is_in_group("player"):
			continue
		var dir := (body.global_position - global_position)
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		if body is RigidBody2D:
			(body as RigidBody2D).apply_central_force(dir * DEFLECTOR_SHIELD_FORCE)
		elif body is CharacterBody2D:
			var cb := body as CharacterBody2D
			cb.velocity = dir * max(cb.velocity.length(), DEFLECTOR_SHIELD_FORCE * 0.4)
		elif body is AnimatableBody2D:
			# AnimatableBody2D (e.g. Crocodile) has no physics forces — push via position
			body.global_position += dir * DEFLECTOR_SHIELD_FORCE * 0.3 * delta

# ---------------------------------------------------------------------------
# POWERUP REPLICATOR
# ---------------------------------------------------------------------------

func _use_powerup_replicator() -> void:
	var stored := AlienTechManager.consume_replicated_powerup()
	if stored >= 0:
		_using_replicator = true
		apply_powerup(stored)
		_using_replicator = false

# ---------------------------------------------------------------------------
# TIME FREEZE
# ---------------------------------------------------------------------------

func _activate_time_freeze() -> void:
	time_freeze_active = true
	AlienTechManager.time_freeze_active = true
	time_freeze_timer = AlienTechManager.TIME_FREEZE_ACTIVE_DURATION
	_freeze_world_bodies()
	AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_FREEZE, 1.0)
	_flash(Color(0.5, 0.9, 1.0), 0.3)

func _freeze_world_bodies() -> void:
	_time_frozen_bodies.clear()
	var groups := ["enemies", "bullets", "plane_projectiles", "enemy_projectiles",
				   "trash_clusters", "trash_cluster_pieces",
				   "powerups", "air_bubbles"]
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node is RigidBody2D:
				var rb := node as RigidBody2D
				_time_frozen_bodies.append({
					"body":       rb,
					"lin_vel":    rb.linear_velocity,
					"ang_vel":    rb.angular_velocity,
					"was_frozen": rb.freeze,
					"type":       "rigid",
				})
				rb.freeze = true
				rb.set_physics_process(false)
				rb.set_process(false)
			elif node is AnimatableBody2D:
				_time_frozen_bodies.append({
					"body": node,
					"type": "animatable",
				})
				node.set_physics_process(false)
				node.set_process(false)
	# Trash items: stop movement without hard-freezing the physics body.
	# freeze=true converts to a static body which breaks bullet contact detection;
	# zeroing velocity + pausing process is enough to hold them in place
	# (gravity_scale=0 means no forces accumulate while process is off).
	for node in get_tree().get_nodes_in_group("trash_items"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is RigidBody2D:
			var rb := node as RigidBody2D
			_time_frozen_bodies.append({
				"body":    rb,
				"lin_vel": rb.linear_velocity,
				"ang_vel": rb.angular_velocity,
				"type":    "soft_rigid",
			})
			rb.linear_velocity = Vector2.ZERO
			rb.angular_velocity = 0.0
			rb.set_physics_process(false)
			rb.set_process(false)
	# Pause all spawners so nothing new appears during the freeze.
	# Must use process_mode (not set_process) so child Timer nodes also stop.
	var spawner_groups := ["spawners", "trash_spawners"]
	for group in spawner_groups:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			_time_frozen_bodies.append({"body": node, "type": "spawner", "process_mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _unfreeze_world_bodies() -> void:
	for entry in _time_frozen_bodies:
		var body = entry["body"]
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		match entry["type"]:
			"rigid":
				var rb := body as RigidBody2D
				rb.freeze = entry["was_frozen"]
				if not entry["was_frozen"]:
					rb.linear_velocity = entry["lin_vel"]
					rb.angular_velocity = entry["ang_vel"]
				rb.set_physics_process(true)
				rb.set_process(true)
			"soft_rigid":
				var rb := body as RigidBody2D
				rb.linear_velocity = entry["lin_vel"]
				rb.angular_velocity = entry["ang_vel"]
				rb.set_physics_process(true)
				rb.set_process(true)
			"animatable":
				body.set_physics_process(true)
				body.set_process(true)
			"spawner":
				body.process_mode = entry["process_mode"]
	_time_frozen_bodies.clear()
	time_freeze_active = false
	AlienTechManager.time_freeze_active = false
	AlienTechManager.clear_passive_bar(AlienTechRegistry.TIME_FREEZE)

func _direction_suffix_to_vector(suffix: String) -> Vector2:
	match suffix:
		"e":  return Vector2.RIGHT
		"w":  return Vector2.LEFT
		"n":  return Vector2.UP
		"s":  return Vector2.DOWN
		"ne": return Vector2(1, -1).normalized()
		"nw": return Vector2(-1, -1).normalized()
		"se": return Vector2(1, 1).normalized()
		"sw": return Vector2(-1, 1).normalized()
		_:    return Vector2.DOWN

# ---------------------------------------------------------------------------
# CONTROL SUSPENSION
# ---------------------------------------------------------------------------

func suspend_control(duration: float):
	"""Temporarily disable player input (called by electric shock)"""
	control_suspended = true
	control_suspend_timer = duration
	print("Player: Control suspended for ", duration, "s!")

# ---------------------------------------------------------------------------
# BUMPER MAGNET
# ---------------------------------------------------------------------------

func _start_bumper_magnet(slot: int) -> void:
	_bumper_magnet_active = true
	_bumper_magnet_timer = BUMPER_MAGNET_DURATION
	_bumper_magnet_slot = slot
	_bumper_magnet_attached = false
	_bumper_magnet_target = null
	_bumper_magnet_attach_speed = linear_velocity.length()

func _update_bumper_magnet(delta: float) -> void:
	_bumper_magnet_timer -= delta
	AlienTechManager.set_passive_bar(
		AlienTechRegistry.BUMPER_MAGNET,
		_bumper_magnet_timer / BUMPER_MAGNET_DURATION
	)
	if _bumper_magnet_timer <= 0.0:
		_launch_from_bumper()
		return
	if _bumper_magnet_attached:
		_update_magnet_orbit(delta)
	else:
		_update_magnet_seek()

func _update_magnet_seek() -> void:
	var nearest: CircularBumper = null
	var nearest_dist: float = INF
	for node in get_tree().get_nodes_in_group("bumpers"):
		if not node is CircularBumper:
			continue
		var bumper := node as CircularBumper
		# Distance from player surface to bumper surface
		var dist_to_surface := global_position.distance_to(bumper.global_position) - bumper.radius - BUMPER_MAGNET_PLAYER_RADIUS
		if dist_to_surface < BUMPER_MAGNET_RADIUS and dist_to_surface < nearest_dist:
			nearest = bumper
			nearest_dist = dist_to_surface

	if nearest == null:
		return

	var dir_outward := (global_position - nearest.global_position)
	if dir_outward == Vector2.ZERO:
		dir_outward = Vector2.RIGHT
	else:
		dir_outward = dir_outward.normalized()
	var contact_point := nearest.global_position + dir_outward * (nearest.radius + BUMPER_MAGNET_PLAYER_RADIUS)

	if nearest_dist <= 2.0:
		_attach_to_bumper(nearest)
	else:
		linear_velocity = (contact_point - global_position).normalized() * BUMPER_MAGNET_PULL_SPEED

func _attach_to_bumper(bumper: CircularBumper) -> void:
	_bumper_magnet_target = bumper
	_bumper_magnet_attached = true
	_bumper_magnet_angle = (global_position - bumper.global_position).angle()
	linear_velocity = Vector2.ZERO
	global_position = bumper.global_position + Vector2(cos(_bumper_magnet_angle), sin(_bumper_magnet_angle)) * (bumper.radius + BUMPER_MAGNET_PLAYER_RADIUS)

func _update_magnet_orbit(delta: float) -> void:
	if not is_instance_valid(_bumper_magnet_target):
		_cancel_bumper_magnet()
		return
	var bumper := _bumper_magnet_target as CircularBumper
	var stick := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if GameSettings.thrust_inverted:
		stick = -stick
	# Clockwise tangent at current angle: project stick onto it so "right stick"
	# always feels like moving right on screen regardless of attachment position.
	var tangent_cw := Vector2(-sin(_bumper_magnet_angle), cos(_bumper_magnet_angle))
	_bumper_magnet_angle += stick.dot(tangent_cw) * BUMPER_MAGNET_ORBIT_SPEED * delta
	global_position = bumper.global_position + Vector2(cos(_bumper_magnet_angle), sin(_bumper_magnet_angle)) * (bumper.radius + BUMPER_MAGNET_PLAYER_RADIUS)
	linear_velocity = Vector2.ZERO

func _launch_from_bumper() -> void:
	if _bumper_magnet_attached and is_instance_valid(_bumper_magnet_target) and _bumper_magnet_target is CircularBumper:
		(_bumper_magnet_target as CircularBumper).apply_launch_force(self, _bumper_magnet_attach_speed)
	_cancel_bumper_magnet()

func _cancel_bumper_magnet() -> void:
	_bumper_magnet_active = false
	_bumper_magnet_attached = false
	_bumper_magnet_target = null
	_bumper_magnet_slot = -1
	AlienTechManager.clear_passive_bar(AlienTechRegistry.BUMPER_MAGNET)

# ---------------------------------------------------------------------------
# DERMAL REGENERATOR
# ---------------------------------------------------------------------------

func _start_dermal_regen(slot: int) -> void:
	if _dermal_regen_used:
		return
	_dermal_regen_active = true
	_dermal_regen_timer = 0.0
	_dermal_regen_slot = slot

func _update_dermal_regen(delta: float) -> void:
	var action := "tech_slot_left" if _dermal_regen_slot == 0 else "tech_slot_right"
	if not Input.is_action_pressed(action):
		_cancel_dermal_regen()
		return
	_dermal_regen_timer += delta
	AlienTechManager.set_passive_bar(
		AlienTechRegistry.DERMAL_REGEN,
		_dermal_regen_timer / DERMAL_REGEN_CHANNEL_DURATION
	)
	if _dermal_regen_timer >= DERMAL_REGEN_CHANNEL_DURATION:
		_complete_dermal_regen()

func _complete_dermal_regen() -> void:
	restore_health(DERMAL_REGEN_HEAL)
	_dermal_regen_used = true
	# Leave passive bar at 0.0 (spent) so HUD shows bar-empty + dimmed label
	# until the player re-spawns or the level resets.
	AlienTechManager.set_passive_bar(AlienTechRegistry.DERMAL_REGEN, 0.0)
	_dermal_regen_active = false
	_dermal_regen_timer = 0.0
	_dermal_regen_slot = -1

func _cancel_dermal_regen() -> void:
	AlienTechManager.clear_passive_bar(AlienTechRegistry.DERMAL_REGEN)
	_dermal_regen_active = false
	_dermal_regen_timer = 0.0
	_dermal_regen_slot = -1

# ---------------------------------------------------------------------------
# FLIPPER VELCRO
# ---------------------------------------------------------------------------

func _update_flipper_velcro(delta: float) -> void:
	if _flipper_velcro_latched:
		_update_flipper_velcro_slide(delta)
	else:
		_try_latch_to_flipper()

func _try_latch_to_flipper() -> void:
	for body in touching_walls:
		if body is FlipperBase and is_instance_valid(body):
			_latch_to_flipper(body as FlipperBase)
			return

func _latch_to_flipper(flipper: FlipperBase) -> void:
	_flipper_velcro_latched = true
	_flipper_velcro_target = flipper

	var arm_dir: Vector2 = flipper.collision_shape.position.normalized()
	var perp: Vector2 = Vector2(-arm_dir.y, arm_dir.x)
	var rel: Vector2 = global_position - flipper.global_position

	_flipper_velcro_t = clamp(
		rel.dot(arm_dir),
		FLIPPER_VELCRO_ARM_MIN_T,
		FLIPPER_VELCRO_ARM_MAX_T
	)
	_flipper_velcro_normal_side = sign(rel.dot(perp))
	if _flipper_velcro_normal_side == 0.0:
		_flipper_velcro_normal_side = 1.0

	linear_velocity = Vector2.ZERO

func _update_flipper_velcro_slide(delta: float) -> void:
	if not is_instance_valid(_flipper_velcro_target):
		_cancel_flipper_velcro()
		return

	var flipper: FlipperBase = _flipper_velcro_target as FlipperBase
	var arm_dir: Vector2 = flipper.collision_shape.position.normalized()
	var perp: Vector2 = Vector2(-arm_dir.y, arm_dir.x)

	var stick := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if GameSettings.thrust_inverted:
		stick = -stick

	_flipper_velcro_t += stick.dot(arm_dir) * FLIPPER_VELCRO_SLIDE_SPEED * delta
	_flipper_velcro_t = clamp(
		_flipper_velcro_t,
		FLIPPER_VELCRO_ARM_MIN_T,
		FLIPPER_VELCRO_ARM_MAX_T
	)

	global_position = flipper.global_position + arm_dir * _flipper_velcro_t + perp * (_flipper_velcro_normal_side * FLIPPER_VELCRO_PLAYER_OFFSET)
	linear_velocity = Vector2.ZERO

func _launch_from_flipper_velcro() -> void:
	if not is_instance_valid(_flipper_velcro_target):
		_cancel_flipper_velcro()
		return

	var flipper: FlipperBase = _flipper_velcro_target as FlipperBase

	# Trigger the full flipper animation (force-flip for 0.25s then returns to rest)
	flipper.trigger_flip(0.25)
	# Prevent the flipper's hit_body from double-applying force in the next frame
	flipper.hit_bodies[get_instance_id()] = 0.5

	# Compute launch direction: tangent to our position relative to the pivot,
	# oriented in the flip rotation direction.
	var rel: Vector2 = global_position - flipper.global_position
	var dist: float = max(rel.length(), 5.0)
	var rel_dir: Vector2 = rel / dist
	var flip_sign: float = sign(flipper.get_flip_angle() - flipper.get_rest_angle())
	var tangent: Vector2 = Vector2(-rel_dir.y, rel_dir.x)
	if flip_sign < 0:
		tangent = -tangent

	# Multiplier is slightly higher than the regular hit_body formula (0.12 vs 0.10)
	# to compensate for velcro starting from zero velocity while regular flips are additive.
	var impulse: float = clamp(flipper.flip_force * dist * 0.15, flipper.flip_force * 1.2, flipper.flip_force * 4.0)
	linear_velocity = tangent * impulse

	_cancel_flipper_velcro()

func _cancel_flipper_velcro() -> void:
	_flipper_velcro_latched = false
	_flipper_velcro_target = null
	_flipper_velcro_t = 12.0

# ---------------------------------------------------------------------------
# SHOCKWAVE
# ---------------------------------------------------------------------------

func _activate_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.has_method("take_damage"):
			enemy.take_damage(10.0)
	if hud:
		hud.current_energy = 0.0
		hud.update_energy(0.0, hud.max_energy)
	suspend_control(1.0)
	_spawn_shockwave_visual()
	_flash(Color(1.0, 0.55, 0.1), 0.2)

func _spawn_shockwave_visual() -> void:
	var ring := Line2D.new()
	var segs := 32
	var pts: PackedVector2Array = []
	for i in range(segs + 1):
		var a := i * TAU / segs
		pts.append(Vector2(cos(a), sin(a)))
	ring.points = pts
	ring.default_color = Color(1.0, 0.55, 0.1, 0.85)
	ring.width = 2.5
	ring.z_as_relative = false
	ring.z_index = 18
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE * 400.0, 0.5)
	tween.tween_property(ring, "modulate:a", 0.0, 0.5)
	tween.finished.connect(ring.queue_free)

# ---------------------------------------------------------------------------
# THING BRINGER
# ---------------------------------------------------------------------------

func _update_thing_bringer() -> void:
	for node in get_tree().get_nodes_in_group("collectibles"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not node is RigidBody2D:
			continue
		# Don't pull a UFO piece the player just intentionally dropped
		if node is UFOPiece and (node as UFOPiece)._drop_grace_timer > 0.0:
			continue
		var rb := node as RigidBody2D
		if rb.freeze:
			continue
		var to_player := global_position - rb.global_position
		var dist := to_player.length()
		if dist > THING_BRINGER_RADIUS or dist < 1.0:
			continue
		rb.linear_velocity = to_player.normalized() * THING_BRINGER_PULL_SPEED
