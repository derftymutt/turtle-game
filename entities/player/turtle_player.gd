extends RigidBody2D

# Movement properties
@export var thrust_force: float = 30.0
@export var max_velocity: float = 2500.0
@export var kick_animation_duration: float = 0.22 # DECREASED: Was 0.25 - snappier feel, less time for player to get off trajectory with long animation
@export var kick_animation_duration_with_ufo_piece: float = 0.5

# Shooting properties
@export var shoot_cooldown: float = 0.25
@export var rapid_fire_shoot_cooldown: float = 0.1
@export var bullet_speed: float = 500.0
@export var bullet_scene: PackedScene
@export var phase_bullet_scene: PackedScene
@export var laser_bullet_scene: PackedScene

# Thrust strengths
@export var horizontal_thrust: float = 175.0
@export var upward_thrust: float = 75.0
@export var downward_thrust: float = 225.0

@export var horizontal_thrust_with_piece: float = 75.0
@export var upward_thrust_with_piece: float = 25.0
@export var downward_thrust_with_piece: float = 125.0

# Health — discrete hearts. Every damage event costs one whole heart regardless
# of the incoming `amount`; death fires when hearts reach 0. A single shared grace
# window (HEART_DAMAGE_IFRAME) after each loss tames rapid / continuous sources
# that carry no i-frames of their own (drowning, electric shock, projectile
# streams). Hearts carry across levels (LevelManager persists current_hearts).
const MAX_HEARTS: int = 7
const HEART_DAMAGE_IFRAME: float = 0.75
## Sprite tint pulsed in while on the last heart (see _update_sprite_modulate)
const LOW_HEALTH_TINT := Color(1.0, 0.15, 0.15)
var current_hearts: int = MAX_HEARTS
var _heart_iframe_timer: float = 0.0
var _last_damage_source: String = ""  # cause clause for the game over screen, e.g. "killed by a crab"

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

# Mouse mode (GameSettings.mouse_mode): the cursor aims and the turtle fires
# continuously; Tab / middle click (GameSettings.TOGGLE_FIRE_ACTION) toggles firing.
# Resets to on for every fresh player (new level / Continue).
const MOUSE_AIM_DEADZONE: float = 10.0
var mouse_fire_enabled: bool = true

## Set by the tutorial to hold the turtle still until the prompt telling the
## player to swim is on screen. Only blocks thrust — physics still runs.
var swim_locked: bool = false
var _last_mouse_aim: Vector2 = Vector2.RIGHT
var _mouse_crosshair: MouseCrosshair

# Bumped by every shoot() so only the newest return_to_idle_after_delay()
# timer gets to act — stale ones from earlier shots would otherwise snap the
# sprite to idle mid-animation (constant under mouse-mode auto-fire).
var _idle_anim_token: int = 0

var control_suspended: bool = false
var control_suspend_timer: float = 0.0

# Alien Tech state
# Extracted effects (see entities/player/alien_tech_effects/) for
# dispatch-table techs — keyed by AlienTechRegistry id, one instance per
# tech, created once in _ready() and kept for this node's lifetime.
var _tech_effects: Dictionary = {}

const CONTACT_IFRAME_DURATION: float = 0.75
var _contact_iframes_active: bool = false
var _contact_iframes_timer: float = 0.0

# Bravado (hot only) — 1s invincibility granted per enemy hit, from bullet.gd
const BRAVADO_HIT_IFRAME_DURATION: float = 1.0
var _bravado_iframe_active: bool = false
var _bravado_iframe_timer: float = 0.0

var _level_complete: bool = false

const BUBBLE_SHIELD_REGEN_DURATION: float = 15.0
const BUBBLE_SHIELD_RADIUS: float = 18.0
const BUBBLE_SHIELD_BLAST_RADIUS: float = 40.0  # hot only — enemies caught in this on trigger take damage
const BUBBLE_SHIELD_BLAST_DAMAGE: float = 15.0
var bubble_shield_hp: float = 0.0
var bubble_shield_regen_timer: float = 0.0
var _bubble_shield_regen_duration: float = BUBBLE_SHIELD_REGEN_DURATION  # halved when hot
var _bubble_flash_timer: float = 0.0
var _bubble_visual: Line2D = null

# Floating energy bar (drawn above the turtle in screen space)
const FLOAT_BAR_HALF_WIDTH: float = 9.0   # half the bar width in pixels
const FLOAT_BAR_Y_OFFSET: float = -14.0  # screen-space pixels above turtle centre
var _float_energy_bg: Line2D = null
var _float_energy_sweep: Line2D = null
var _float_energy_fg: Line2D = null
var _sweep_phase: float = 0.0

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

# Thing Bringer
const THING_BRINGER_RADIUS: float = 30.0
const THING_BRINGER_PULL_SPEED: float = 220.0

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

	# Carry the exact heart count forward from the previous level (-1 = start full)
	if GameManager.persisted_hearts >= 0:
		current_hearts = clampi(GameManager.persisted_hearts, 0, MAX_HEARTS)
	else:
		current_hearts = MAX_HEARTS

	hud = get_tree().get_first_node_in_group("hud")
	if not hud:
		push_warning("No HUD found! Add HUD scene to level and add it to 'hud' group.")
	else:
		hud.update_hearts(current_hearts, MAX_HEARTS)

	add_to_group("player")

	_setup_super_speed_area()
	_setup_rest_particles()
	_setup_bubble_visual()
	_setup_float_energy_bar()

	_mouse_crosshair = MouseCrosshair.new()
	add_child(_mouse_crosshair)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Every per-tech "active" flag below (inertia_dampener_active, etc.) always
	# starts false on this fresh instance — clear any stale passive-bar
	# override left behind by a previous instance so the HUD doesn't show a
	# hot toggle-style tech as already active before it's actually been used.
	_tech_effects[AlienTechRegistry.GRAVITON_HARNESS] = GravitonHarnessEffect.new()
	_tech_effects[AlienTechRegistry.MAGNETIC_REPULSION] = MagneticRepulsionEffect.new()
	_tech_effects[AlienTechRegistry.HYDRO_FUNNEL] = HydroFunnelEffect.new()
	_tech_effects[AlienTechRegistry.INERTIA_DAMPENER] = InertiaDampenerEffect.new()
	_tech_effects[AlienTechRegistry.LATERAL_THRUST] = LateralThrustEffect.new()
	_tech_effects[AlienTechRegistry.TRANSPORTER] = TransporterEffect.new()
	_tech_effects[AlienTechRegistry.QUANTUM_MIRROR] = QuantumMirrorEffect.new()
	_tech_effects[AlienTechRegistry.SHOCKWAVE] = ShockwaveEffect.new()
	_tech_effects[AlienTechRegistry.DERMAL_REGEN] = DermalRegenEffect.new()
	_tech_effects[AlienTechRegistry.BUMPER_MAGNET] = BumperMagnetEffect.new()
	_tech_effects[AlienTechRegistry.DEFLECTOR_SHIELD] = DeflectorShieldEffect.new()
	_tech_effects[AlienTechRegistry.POWERUP_REPLICATOR] = PowerupReplicatorEffect.new()
	_tech_effects[AlienTechRegistry.TIME_FREEZE] = TimeFreezeEffect.new()
	_tech_effects[AlienTechRegistry.ION_EXCITER] = IonExciterEffect.new()
	_tech_effects[AlienTechRegistry.STIM_SHOT] = StimShotEffect.new()
	_tech_effects[AlienTechRegistry.MULTI_LANCE] = MultiLanceEffect.new()
	_tech_effects[AlienTechRegistry.URCHIN_TRANSMOGRIFY] = UrchinTransmogrifyEffect.new()
	_tech_effects[AlienTechRegistry.FLIPPER_AUTOMATON] = FlipperAutomatonEffect.new()
	for effect in _tech_effects.values():
		(effect as AlienTechEffect).setup(self)

	# Equipped-tech glow around the turtle (left/right halves = slot A/B).
	# After _tech_effects is filled — the aura reads effect state from frame one.
	add_child(TechAura.new())

	# A previous player may have died mid-action (mid-lance, mid-transmogrify...) —
	# start every tech fresh, whether this is a new level or a Continue.
	AlienTechManager.reset_level_state()
	AlienTechManager.tech_activated.connect(_on_alien_tech_activated)
	AlienTechManager.tech_slots_changed.connect(_on_alien_tech_slots_changed_player)
	LevelManager.level_complete.connect(func(): _level_complete = true)
	# Sync state for any tech already in slots before this node was ready (e.g. DevTechSeeder)
	_on_alien_tech_slots_changed_player(AlienTechManager.slots[0], AlienTechManager.slots[1])

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
	# Stim Shot: read once up front — its scale_factor (1.0 when inactive)
	# speeds up the turtle's own cooldown recovery, animation, and ocean drag
	# response without touching thrust_strength or bullet_speed.
	var stim_shot := _tech_effects[AlienTechRegistry.STIM_SHOT] as StimShotEffect
	# Multi Lance: thrust is locked out during its brief aim window (so the
	# stick only steers the preview) and while it's hauling something
	# (shooting is not blocked either way); if it's the turtle being hauled,
	# ocean physics is also suppressed so buoyancy/drag don't fight the pull.
	var multi_lance := _tech_effects[AlienTechRegistry.MULTI_LANCE] as MultiLanceEffect

	# Update cooldown timers
	if not can_thrust:
		thrust_timer -= delta * stim_shot.scale_factor
		if thrust_timer <= 0:
			can_thrust = true
			is_player_controlling_rotation = false

	if not can_shoot:
		shoot_timer -= delta * stim_shot.scale_factor
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
	if (_tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect).attached or _flipper_velcro_latched:
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

	_tech_effects[AlienTechRegistry.INERTIA_DAMPENER].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.GRAVITON_HARNESS].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.HYDRO_FUNNEL].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.QUANTUM_MIRROR].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.LATERAL_THRUST].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.TRANSPORTER].physics_process(self, delta)

	if _bravado_iframe_active:
		_bravado_iframe_timer -= delta
		if _bravado_iframe_timer <= 0.0:
			_bravado_iframe_active = false

	if _contact_iframes_active:
		_contact_iframes_timer -= delta
		if _contact_iframes_timer <= 0.0:
			_contact_iframes_active = false

	if _heart_iframe_timer > 0.0:
		_heart_iframe_timer -= delta

	if AlienTechManager.is_tech_active(AlienTechRegistry.BUBBLE_SHIELD):
		if bubble_shield_hp == 0.0 and bubble_shield_regen_timer > 0.0:
			bubble_shield_regen_timer -= delta
			if bubble_shield_regen_timer <= 0.0:
				bubble_shield_hp = 1.0
				if _bubble_visual:
					_bubble_visual.visible = true
		var _regen_ratio: float = 1.0 if bubble_shield_hp > 0.0 else clamp(1.0 - bubble_shield_regen_timer / _bubble_shield_regen_duration, 0.0, 1.0)
		AlienTechManager.set_passive_bar(AlienTechRegistry.BUBBLE_SHIELD, _regen_ratio)

	if AlienTechManager.is_tech_active(AlienTechRegistry.THING_BRINGER):
		_update_thing_bringer()

	_tech_effects[AlienTechRegistry.MAGNETIC_REPULSION].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.BUMPER_MAGNET].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.DERMAL_REGEN].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.DEFLECTOR_SHIELD].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.TIME_FREEZE].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.ION_EXCITER].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.URCHIN_TRANSMOGRIFY].physics_process(self, delta)

	_tech_effects[AlienTechRegistry.FLIPPER_AUTOMATON].physics_process(self, delta)

	multi_lance.physics_process(self, delta)

	stim_shot.physics_process(self, delta)

	# Ocean physics — suppressed while pinned to a bumper or flipper
	if not (_tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect).attached and not _flipper_velcro_latched and not multi_lance.pulling_player:
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
		animated_sprite.speed_scale = stim_shot.scale_factor

	# HUD systems
	if hud:
		var depth = ocean.get_depth(global_position) if ocean else 0.0
		var is_underwater = depth > 3

		_is_underwater = is_underwater

		if is_underwater:
			# Stim Shot's balancing cost: air drains at air_drain_scale
			# (3x) while active — see StimShotEffect.AIR_DRAIN_MULT.
			var out_of_air = hud.drain_air(delta * stim_shot.air_drain_scale)
			if out_of_air:
				take_damage(10.0 * delta, false, "ran out of breath")
		else:
			hud.refill_air(delta)

		var at_surface: bool = depth <= 8  # wider than air threshold so idle surface float triggers fast recharge
		# Stim Shot drains energy faster on its own (more thrusts fit in the
		# same real second, each still costing its normal try_thrust() price).
		# energy_recovery_scale outpaces scale_factor on purpose — see
		# StimShotEffect's ENERGY_RECOVERY_BOOST — so the tech is actually
		# sustainable away from walls, not just break-even.
		hud.recover_energy(delta * stim_shot.energy_recovery_scale, (touching_walls.size() > 0 or at_surface) and not (_tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect).attached)

	_update_rest_particles()

	if GameSettings.mouse_mode and Input.is_action_just_pressed(GameSettings.TOGGLE_FIRE_ACTION):
		mouse_fire_enabled = not mouse_fire_enabled
	_mouse_crosshair.firing = mouse_fire_enabled

	# Control suspension timer — runs even while suspended so it keeps counting down
	control_suspend_timer -= delta
	if control_suspend_timer <= 0 and control_suspended:
		control_suspended = false
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.scale = Vector2.ONE
			animated_sprite.position = Vector2.ZERO

	if control_suspended:
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.position = Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
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
			# Hot: shooting still works while gripping the flipper. Everything
			# else (movement, other tech slots, etc.) stays locked out either way.
			if AlienTechManager.is_tech_hot(AlienTechRegistry.FLIPPER_VELCRO):
				var fv_shoot_input := get_shoot_input()
				if fv_shoot_input != Vector2.ZERO and can_shoot:
					shoot(fv_shoot_input.normalized())
			return

	# Input
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	var shoot_input := get_shoot_input()

	# Movement — check energy unless energy freeze is active
	var can_actually_thrust = can_thrust
	if hud and movement_input.length() > 0.1 and not energy_freeze_active:
		can_actually_thrust = can_actually_thrust and hud.can_thrust()

	if movement_input.length() > 0.1 and can_actually_thrust and not swim_locked and not multi_lance.pulling and not multi_lance.aiming:
		apply_thrust(movement_input.normalized())

	if shoot_input != Vector2.ZERO and can_shoot:
		shoot(shoot_input)
		
	# Drop all carried UFO pieces on button press (intentional = grace period before re-pickup)
	if Input.is_action_just_pressed("drop_piece"):
		if GameManager.is_carrying_piece:
			for piece in GameManager.carried_pieces.duplicate():
				if is_instance_valid(piece):
					piece.drop_piece(true)
			$SfxUfoDrop.play()

	# Alien Tech active slot buttons
	var _rpl_slot := AlienTechManager.get_slot_index_for_tech(AlienTechRegistry.POWERUP_REPLICATOR)
	for _slot_idx in [0, 1]:
		var _action: String = "tech_slot_left" if _slot_idx == 0 else "tech_slot_right"
		if _slot_idx == _rpl_slot:
			(_tech_effects[AlienTechRegistry.POWERUP_REPLICATOR] as PowerupReplicatorEffect).handle_input(self, _slot_idx, _action, delta)
		else:
			if _fv_slot != _slot_idx and Input.is_action_just_pressed(_action):
				AlienTechManager.try_activate_slot(_slot_idx)

	var bumper_magnet := _tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect
	bumper_magnet.check_release_launch(self)

	# While attached the orbit function owns position/velocity — skip normal movement
	if bumper_magnet.attached:
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
	(_tech_effects[AlienTechRegistry.DEFLECTOR_SHIELD] as DeflectorShieldEffect).update_visual_pulse()
	if _bubble_visual and _bubble_visual.visible:
		var pulse := (sin(Time.get_ticks_msec() * 0.005) + 1.0) * 0.5
		_bubble_visual.default_color = Color(0.5, 0.9, 1.0, 0.35 + pulse * 0.4)
	var mirror_ghost := (_tech_effects[AlienTechRegistry.QUANTUM_MIRROR] as QuantumMirrorEffect).ghost
	if mirror_ghost and is_instance_valid(mirror_ghost):
		var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
		mirror_ghost.modulate.a = lerpf(0.25, 0.45, pulse)
	_update_float_energy_bar(delta)

func _update_sprite_modulate():
	var sprite = $AnimatedSprite2D
	if not sprite or not is_instance_valid(sprite):
		return
	var transporter := _tech_effects[AlienTechRegistry.TRANSPORTER] as TransporterEffect
	var quantum_mirror := _tech_effects[AlienTechRegistry.QUANTUM_MIRROR] as QuantumMirrorEffect
	var dermal_regen := _tech_effects[AlienTechRegistry.DERMAL_REGEN] as DermalRegenEffect
	var bumper_magnet := _tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect
	var deflector_shield := _tech_effects[AlienTechRegistry.DEFLECTOR_SHIELD] as DeflectorShieldEffect
	var time_freeze := _tech_effects[AlienTechRegistry.TIME_FREEZE] as TimeFreezeEffect
	if _health_restore_flash_timer > 0.0:
		sprite.modulate = Color.GREEN
	elif transporter.windup:
		var flash = (sin(Time.get_ticks_msec() * 0.25) + 1.0) * 0.5
		sprite.modulate = Color(0.6, 0.3, 1.0).lerp(Color.WHITE, flash * 0.6)
	elif transporter.invincible:
		var flash = (sin(Time.get_ticks_msec() * 0.06) + 1.0) * 0.5
		sprite.modulate = Color(0.6, 0.3, 1.0).lerp(Color.WHITE, flash)
	elif quantum_mirror.active:
		var flash = (sin(Time.get_ticks_msec() * 0.05) + 1.0) * 0.5
		sprite.modulate = Color(0.85, 0.3, 0.95).lerp(Color.WHITE, flash * 0.7)
	elif _bravado_iframe_active:
		var flash = (sin(Time.get_ticks_msec() * 0.08) + 1.0) * 0.5
		sprite.modulate = Color(1.0, 0.4, 0.2).lerp(Color.WHITE, flash)
	elif _bubble_flash_timer > 0.0:
		sprite.modulate = Color(0.3, 0.9, 1.0)
	elif dermal_regen.active:
		var progress := dermal_regen.progress()
		var flash := (sin(Time.get_ticks_msec() * (0.06 + progress * 0.18)) + 1.0) * 0.5
		sprite.modulate = Color(0.1, 0.9, 0.3).lerp(Color(0.7, 1.0, 0.7), flash)
	elif bumper_magnet.active:
		if bumper_magnet.attached:
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
	elif deflector_shield.active:
		var flash := (sin(Time.get_ticks_msec() * 0.04) + 1.0) * 0.5
		sprite.modulate = Color(0.3, 0.7, 1.0).lerp(Color.WHITE, flash * 0.5)
	elif time_freeze.active:
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

	# Last-heart warning: slow red pulse blended over whatever color was set
	# above, so it stays visible even while a tech/powerup tint is active.
	if current_hearts == 1:
		var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
		var a: float = sprite.modulate.a
		sprite.modulate = sprite.modulate.lerp(LOW_HEALTH_TINT, lerpf(0.5, 0.9, pulse))
		sprite.modulate.a = a

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
	if (_tech_effects[AlienTechRegistry.LATERAL_THRUST] as LateralThrustEffect).active:
		return

	var depth = ocean.get_depth(global_position)
	var dampener := _tech_effects[AlienTechRegistry.INERTIA_DAMPENER] as InertiaDampenerEffect
	# Stim Shot: drag is a flat per-tick multiply that has no idea the
	# turtle is on a faster clock — raising it to scale_factor's power keeps
	# the decay-per-turtle-second the same as at 1x. Buoyancy is scaled the
	# same way since it's also an ambient force integrated by the engine's
	# own fixed tick rather than our local clock. See stim_shot_effect.gd.
	var time_scale: float = (_tech_effects[AlienTechRegistry.STIM_SHOT] as StimShotEffect).scale_factor

	# Inertia Dampener in air: skip gravity calculation entirely and treat air
	# as shallow ocean so the turtle can swim freely above the surface.
	if dampener.active and depth <= 0:
		apply_central_force(Vector2(0, -ocean.shallow_buoyancy * mass * time_scale))
		linear_velocity *= pow(ocean.water_drag, time_scale)
		linear_damp = 1.0
		return

	# Inertia Dampener underwater: clamp depth to shallow zone so deep buoyancy never fires
	if dampener.active:
		depth = min(depth, ocean.shallow_depth - 1.0)

	var buoyancy_force = ocean.calculate_buoyancy_force(depth, mass) * time_scale
	apply_central_force(Vector2(0, -buoyancy_force))

	if depth > 0:
		linear_velocity *= pow(ocean.water_drag, time_scale)
		var depth_factor = clamp(depth / 100.0, 0.0, 1.0)
		linear_damp = lerp(1.0, 2.0, depth_factor)
	else:
		linear_velocity *= pow(ocean.air_drag, time_scale)
		linear_damp = 1.2

# ---------------------------------------------------------------------------
# MOVEMENT & SHOOTING
# ---------------------------------------------------------------------------

## Unit shot direction for this frame, or Vector2.ZERO for "not shooting".
## The one place shooting input is read — TutorialDirector calls it too, so
## its paused shoot lesson matches real gameplay. Explicit aim (IJKL / right
## stick) always wins; in mouse mode, otherwise fire at the cursor unless
## auto-fire has been toggled off or the gamepad is the active device (see
## GameSettings.mouse_aim_active()). Safe to call while the tree is paused.
func get_shoot_input() -> Vector2:
	var stick := Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)
	if stick.length() > 0.1:
		return stick.normalized()
	if not GameSettings.mouse_aim_active() or not mouse_fire_enabled:
		return Vector2.ZERO
	# Cursor sitting on the turtle gives a jittery angle — keep the last one.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() > MOUSE_AIM_DEADZONE:
		_last_mouse_aim = to_mouse.normalized()
	return _last_mouse_aim

func return_to_idle_after_delay():
	_idle_anim_token += 1
	var token := _idle_anim_token
	await get_tree().create_timer(current_kick_animation_duration).timeout
	if not is_inside_tree() or token != _idle_anim_token:
		return
	var animated_sprite = $AnimatedSprite2D
	# Only undo our own shoot pose — a kick that started since keeps playing.
	if animated_sprite and is_instance_valid(animated_sprite) and String(animated_sprite.animation).begins_with("shoot_"):
		animated_sprite.play("idle_" + facing_direction)

func apply_thrust(direction: Vector2):
	var kick_direction = -direction if GameSettings.thrust_inverted else direction

	# No upward thrust in air (dampener converts air to shallow ocean, so allow all directions)
	if ocean and ocean.get_depth(global_position) <= 0 and kick_direction.y < 0 and not (_tech_effects[AlienTechRegistry.INERTIA_DAMPENER] as InertiaDampenerEffect).active:
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
	if GameManager.is_carrying_piece and not (_tech_effects[AlienTechRegistry.GRAVITON_HARNESS] as GravitonHarnessEffect).is_weightless(self):
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

	$SfxShoot.play()

	# Phase Shifter: hold slot button while shooting → fire phase bullet instead
	var _phase_slot := AlienTechManager.get_slot_index_for_tech(AlienTechRegistry.PHASE_SHIFTER)
	if _phase_slot != -1 and Input.is_action_pressed(_slot_action(_phase_slot)):
		if AlienTechManager.consume_phase_bullet():
			_shoot_phase_bullet(direction)
		can_shoot = false
		shoot_timer = active_shoot_cooldown
		return

	# Plasma Spit: passive — every regular shot becomes a piercing plasma beam
	var bullet
	if AlienTechManager.is_tech_active(AlienTechRegistry.PLASMA_SPIT) and laser_bullet_scene:
		bullet = laser_bullet_scene.instantiate()
		if AlienTechManager.is_tech_hot(AlienTechRegistry.PLASMA_SPIT):
			bullet.damage *= 2.0
			bullet.lifetime *= 1.6  # hot: longer beam
	else:
		bullet = bullet_scene.instantiate()

	get_parent().add_child(bullet)
	bullet.global_position = _safe_bullet_spawn(direction)
	bullet.set_velocity(direction * bullet_speed)
	if AlienTechManager.is_tech_active(AlienTechRegistry.SALIVA_NANOBOTS):
		bullet.is_homing = true
		if AlienTechManager.is_tech_hot(AlienTechRegistry.SALIVA_NANOBOTS):
			bullet.damage = 40.0
			bullet.homing_turn_speed_deg = 300.0
		else:
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

func take_damage(amount: float, use_iframes: bool = false, source: String = ""):
	if _level_complete:
		return
	if use_iframes and _contact_iframes_active:
		return
	if is_super_speed or is_super_speed_cooldown or shield_active or (_tech_effects[AlienTechRegistry.TRANSPORTER] as TransporterEffect).invincible or (_tech_effects[AlienTechRegistry.DEFLECTOR_SHIELD] as DeflectorShieldEffect).active or _bravado_iframe_active or (_tech_effects[AlienTechRegistry.QUANTUM_MIRROR] as QuantumMirrorEffect).active:
		return
	# Shared grace window after any heart loss — this is what tames rapid /
	# continuous sources with no i-frames of their own (drowning, shock, volleys).
	if _heart_iframe_timer > 0.0:
		return

	if AlienTechManager.is_tech_active(AlienTechRegistry.BUBBLE_SHIELD) and bubble_shield_hp > 0.0:
		var bubble_hot := AlienTechManager.is_tech_hot(AlienTechRegistry.BUBBLE_SHIELD)
		bubble_shield_hp = 0.0
		_bubble_shield_regen_duration = BUBBLE_SHIELD_REGEN_DURATION * (0.5 if bubble_hot else 1.0)
		bubble_shield_regen_timer = _bubble_shield_regen_duration
		if _bubble_visual:
			_bubble_visual.visible = false
		_bubble_flash_timer = 0.4
		if bubble_hot:
			_bubble_shield_blast()
		return  # Shield absorbed — transporter windup NOT canceled

	# Real damage lands — cancel active techs that need aborting
	_tech_effects[AlienTechRegistry.TRANSPORTER].cancel_on_damage(self)
	_tech_effects[AlienTechRegistry.DERMAL_REGEN].cancel_on_damage(self)
	_tech_effects[AlienTechRegistry.BUMPER_MAGNET].cancel_on_damage(self)
	_tech_effects[AlienTechRegistry.MULTI_LANCE].cancel_on_damage(self)
	if _flipper_velcro_latched:
		_cancel_flipper_velcro()

	# One damage event = one heart, regardless of `amount`.
	current_hearts = max(0, current_hearts - 1)
	_heart_iframe_timer = HEART_DAMAGE_IFRAME
	if not source.is_empty():
		_last_damage_source = source
	$SfxDamage.play()

	if hud:
		hud.update_hearts(current_hearts, MAX_HEARTS)
		hud.flash_damage_vignette()

	# Drop piece(s) and check death BEFORE any await — these must fire immediately
	# and must not be triggered multiple times from repeated per-frame damage.
	if GameManager.is_carrying_piece:
		for piece in GameManager.carried_pieces.duplicate():
			if is_instance_valid(piece):
				piece.drop_piece()

	if current_hearts <= 0:
		die()
		return  # die() handles everything from here

	# Reuse the contact-iframe blink so the player reads the grace window
	_contact_iframes_active = true
	_contact_iframes_timer = HEART_DAMAGE_IFRAME
	_flash(Color.RED, 0.3)

func restore_hearts(amount: int) -> void:
	if amount <= 0:
		return
	current_hearts = min(MAX_HEARTS, current_hearts + amount)
	if hud:
		hud.update_hearts(current_hearts, MAX_HEARTS)
	_health_restore_flash_timer = 0.2

## Called by bullet.gd when hot Bravado lands a hit — refreshes the 1s window
## rather than stacking, so repeated hits just keep it topped up.
func grant_bravado_iframe() -> void:
	_bravado_iframe_active = true
	_bravado_iframe_timer = BRAVADO_HIT_IFRAME_DURATION

func die():
	var final_score = 0
	if hud:
		final_score = hud.current_score

	GameManager.current_score = final_score

	var level = get_tree().get_first_node_in_group("level")
	if level and level.has_method("on_player_died"):
		level.on_player_died(final_score, _last_damage_source)
	else:
		var game_over_screen = get_tree().get_first_node_in_group("game_over_screen")
		if game_over_screen and game_over_screen.has_method("show_game_over"):
			game_over_screen.show_game_over(final_score, GameManager.total_score, _last_damage_source)
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
	if AlienTechManager.has_tech(AlienTechRegistry.POWERUP_REPLICATOR) and not (_tech_effects[AlienTechRegistry.POWERUP_REPLICATOR] as PowerupReplicatorEffect).using_replicator:
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
	if hud:
		hud.set_hearts_blinking(true)
	print("SHIELD ACTIVATED! Invincible for ", shield_duration, " seconds!")

func deactivate_shield():
	shield_active = false
	if hud:
		hud.set_hearts_blinking(false)
	print("Shield expired")

func activate_air_reserve():
	if hud:
		hud.max_air += air_reserve_bonus
		hud.current_air = hud.max_air
		hud.update_air(hud.current_air, hud.max_air)
		hud.flash_air_bar()
		print("AIR RESERVE! +", air_reserve_bonus, " max air! (new max: ", hud.max_air, ")")
	else:
		push_error("No HUD found! Can't apply air reserve.")

func activate_energy_freeze():
	energy_freeze_active = true
	energy_freeze_timer = energy_freeze_duration
	if hud:
		hud.update_energy(hud.max_energy, hud.max_energy)
		hud.set_energy_blinking(true)
	print("ENERGY FREEZE! No energy drain for ", energy_freeze_duration, " seconds!")

func deactivate_energy_freeze():
	energy_freeze_active = false
	if hud:
		hud.set_energy_blinking(false)
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
	if _tech_effects.has(tech_id):
		_tech_effects[tech_id].activate(self, slot_index)

## Public wrapper for other entities (e.g. BossSubmarine) that want to react
## to the tech without duplicating its active-flag/timer/hot bookkeeping,
## which all lives on the effect object.
func is_magnetic_repulsion_in_effect() -> bool:
	return (_tech_effects[AlienTechRegistry.MAGNETIC_REPULSION] as MagneticRepulsionEffect).is_active_effect()

## Public wrapper for CircularBumper, which needs to know whether this
## player is currently magnetically attached to it specifically, to
## suppress its normal hit response while the player orbits it.
func is_magnet_attached_to(bumper) -> bool:
	return (_tech_effects[AlienTechRegistry.BUMPER_MAGNET] as BumperMagnetEffect).is_attached_to(bumper)

## Public wrapper for FlipperBase and CircularBumper, which need to know
## whether to double the launch speed they impart to this player.
func is_ion_exciter_active() -> bool:
	return (_tech_effects[AlienTechRegistry.ION_EXCITER] as IonExciterEffect).active

## Reflects `pos` across the play area's horizontal center (always) and,
## when mirror_y is true (hot Quantum Mirror), its vertical center too —
## the midpoint between the ocean surface and the floor boundary, so a
## near-surface position and a near-floor position mirror each other.
## Leaves an axis unchanged if its boundary data isn't available.
func _mirrored_position(pos: Vector2, mirror_y: bool) -> Vector2:
	var lim := _get_boundary_limits()
	var mirrored := pos
	if lim.min_x > -INF and lim.max_x < INF:
		mirrored.x = lim.min_x + lim.max_x - pos.x
	if mirror_y and ocean and lim.max_y < INF:
		mirrored.y = ocean.surface_y + lim.max_y - pos.y
	return mirrored

## Shared arrival-pop tween for teleport-style effects. Transporter has its
## own inline copy of this predating Quantum Mirror — left alone rather than
## refactored, to avoid touching its already-working code for this change.
func _play_teleport_pop() -> void:
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
		if _bubble_visual:
			_bubble_visual.visible = bubble_shield_hp > 0.0
	else:
		# Tech was swapped out (or fried) — bubble_shield_hp/_bubble_visual are
		# only ever updated while the tech is equipped (see _process), so
		# without this the ring keeps drawing around the turtle forever with
		# a slot that no longer holds the tech.
		bubble_shield_hp = 0.0
		bubble_shield_regen_timer = 0.0
		if _bubble_visual:
			_bubble_visual.visible = false

	for effect in _tech_effects.values():
		(effect as AlienTechEffect).on_slots_changed(self)

# ---------------------------------------------------------------------------
# BUBBLE SHIELD VISUAL
# ---------------------------------------------------------------------------

## Hot only — damages every enemy within BUBBLE_SHIELD_BLAST_RADIUS the moment
## the shield absorbs a hit.
func _bubble_shield_blast() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if not enemy is Node2D or not enemy.has_method("take_damage"):
			continue
		if global_position.distance_to((enemy as Node2D).global_position) <= BUBBLE_SHIELD_BLAST_RADIUS:
			enemy.take_damage(BUBBLE_SHIELD_BLAST_DAMAGE)

func _setup_bubble_visual() -> void:
	_bubble_visual = Line2D.new()
	_bubble_visual.name = "BubbleVisual"
	var _pts: PackedVector2Array = []
	var _segs := 36
	for i in range(_segs + 1):
		var a := i * TAU / _segs
		_pts.append(Vector2(cos(a), sin(a)) * BUBBLE_SHIELD_RADIUS)
	_bubble_visual.points = _pts
	_bubble_visual.default_color = Color(0.5, 0.9, 1.0, 0.65)
	_bubble_visual.width = 1.5
	_bubble_visual.z_as_relative = false
	_bubble_visual.z_index = 12
	_bubble_visual.visible = false
	add_child(_bubble_visual)

func _setup_float_energy_bar() -> void:
	_float_energy_bg = Line2D.new()
	_float_energy_bg.name = "FloatEnergyBg"
	_float_energy_bg.points = PackedVector2Array([Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0), Vector2(FLOAT_BAR_HALF_WIDTH, 0.0)])
	_float_energy_bg.default_color = Color(0.15, 0.15, 0.15, 0.8)
	_float_energy_bg.width = 2.0
	_float_energy_bg.z_as_relative = false
	_float_energy_bg.z_index = 25
	add_child(_float_energy_bg)

	_float_energy_sweep = Line2D.new()
	_float_energy_sweep.name = "FloatEnergySweep"
	_float_energy_sweep.points = PackedVector2Array([Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0), Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0)])
	_float_energy_sweep.default_color = Color(0.0, 1.0, 1.0, 0.95)
	_float_energy_sweep.width = 2.0
	_float_energy_sweep.z_as_relative = false
	_float_energy_sweep.z_index = 26
	_float_energy_sweep.visible = false
	add_child(_float_energy_sweep)

	_float_energy_fg = Line2D.new()
	_float_energy_fg.name = "FloatEnergyFg"
	_float_energy_fg.points = PackedVector2Array([Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0), Vector2(FLOAT_BAR_HALF_WIDTH, 0.0)])
	_float_energy_fg.default_color = Color.YELLOW
	_float_energy_fg.width = 2.0
	_float_energy_fg.z_as_relative = false
	_float_energy_fg.z_index = 27
	add_child(_float_energy_fg)

func _update_float_energy_bar(delta: float) -> void:
	if not _float_energy_bg or not _float_energy_fg or not _float_energy_sweep:
		return
	var show := hud != null and hud.energy_enabled and not _level_complete
	_float_energy_bg.visible = show
	_float_energy_fg.visible = show
	if not show:
		_float_energy_sweep.visible = false
		return

	# Keep bar screen-aligned and fixed above turtle regardless of body rotation.
	# global_rotation = 0 cancels the parent body's spin; rotation = 0 would only
	# set local rotation and the parent's spin would still be applied on top.
	var screen_offset := Vector2(0.0, FLOAT_BAR_Y_OFFSET)
	for node: Line2D in [_float_energy_bg, _float_energy_sweep, _float_energy_fg]:
		node.global_position = global_position + screen_offset
		node.global_rotation = 0.0

	var ratio := clampf(hud.current_energy / hud.max_energy, 0.0, 1.0)
	var fill_x := -FLOAT_BAR_HALF_WIDTH + FLOAT_BAR_HALF_WIDTH * 2.0 * ratio
	_float_energy_fg.points = PackedVector2Array([Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0), Vector2(fill_x, 0.0)])

	if ratio > 0.2:
		_float_energy_fg.default_color = Color.YELLOW
	else:
		_float_energy_fg.default_color = Color.RED

	# Fast-recharge sweep: bright cyan bar sweeps left→right beneath the yellow fill.
	# Visible only while wall_recovery_active so it directly telegraphs the mechanic.
	var fast_charging := hud.wall_recovery_active and hud.current_energy < hud.max_energy
	_float_energy_sweep.visible = fast_charging
	if fast_charging:
		_sweep_phase = fmod(_sweep_phase + delta * 5.0, 1.0)
		var sweep_x := -FLOAT_BAR_HALF_WIDTH + FLOAT_BAR_HALF_WIDTH * 2.0 * _sweep_phase
		_float_energy_sweep.points = PackedVector2Array([Vector2(-FLOAT_BAR_HALF_WIDTH, 0.0), Vector2(sweep_x, 0.0)])
	else:
		_sweep_phase = 0.0

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

func end_control_suspension():
	"""Cut a stun short (e.g. Dermal Regenerator's channel ending early)"""
	control_suspend_timer = 0.0

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

	GameManager.mark_flipper_used()

	# Trigger the full flipper animation (force-flip for 0.25s then returns to rest).
	# The flipper holds its swing back a few ticks so the arm doesn't jump over us, and
	# exempts us from its own hit_body so the launch below isn't double-applied.
	flipper.trigger_flip(0.25, self)
	flipper.play_launch_sound()

	# Compute launch direction: tangent to our position relative to the pivot,
	# oriented in the flip rotation direction.
	var rel: Vector2 = global_position - flipper.global_position
	var dist: float = max(rel.length(), 5.0)
	var rel_dir: Vector2 = rel / dist
	var flip_sign: float = sign(flipper.get_flip_angle() - flipper.get_rest_angle())
	var tangent: Vector2 = Vector2(-rel_dir.y, rel_dir.x)
	if flip_sign < 0:
		tangent = -tangent

	# The swing direction only clears the arm when latched on its leading side. From the
	# trailing (underside) the tangent points into the arm, and at launch speed (~35px per
	# physics tick vs a 12px-thick arm) the turtle tunnels straight through. Mirror that
	# component across the arm so the turtle is launched away from it on the side it's gripping.
	var arm_dir: Vector2 = flipper.collision_shape.position.normalized()
	var outward: Vector2 = Vector2(-arm_dir.y, arm_dir.x) * _flipper_velcro_normal_side
	var into_arm: float = tangent.dot(outward)
	if into_arm < 0.0:
		tangent -= 2.0 * into_arm * outward

	# Multiplier is slightly higher than the regular hit_body formula (0.12 vs 0.10)
	# to compensate for velcro starting from zero velocity while regular flips are additive.
	var impulse: float = clamp(flipper.flip_force * dist * 0.15, flipper.flip_force * 1.2, flipper.flip_force * 4.0)
	if AlienTechManager.is_tech_hot(AlienTechRegistry.FLIPPER_VELCRO):
		impulse *= 1.75  # hot: releases at much faster speed
	linear_velocity = tangent * impulse

	_cancel_flipper_velcro()

func _cancel_flipper_velcro() -> void:
	_flipper_velcro_latched = false
	_flipper_velcro_target = null
	_flipper_velcro_t = 12.0

# ---------------------------------------------------------------------------
# THING BRINGER
# ---------------------------------------------------------------------------

func _update_thing_bringer() -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.THING_BRINGER)
	var radius := THING_BRINGER_RADIUS * (2.0 if hot else 1.0)
	var pull_speed := THING_BRINGER_PULL_SPEED * (2.0 if hot else 1.0)
	for node in get_tree().get_nodes_in_group("collectibles"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not node is RigidBody2D:
			continue
		# Don't pull a UFO piece the player is currently carrying, or one
		# recently dropped (intentionally or via damage) — otherwise this
		# yanks a just-dropped piece straight back into the player every
		# frame, before it's had a chance to separate, leaving it stuck
		# rattling inside the player's body, uncarried and undeliverable.
		if node is UFOPiece and ((node as UFOPiece).is_carried or (node as UFOPiece)._drop_grace_timer > 0.0):
			continue
		var rb := node as RigidBody2D
		if rb.freeze:
			continue
		var to_player := global_position - rb.global_position
		var dist := to_player.length()
		if dist > radius or dist < 1.0:
			continue
		rb.linear_velocity = to_player.normalized() * pull_speed
