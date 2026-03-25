extends BaseEnemyStatic
class_name BossSubmarine

## ============================================================
## SUBMARINE BOSS
## ============================================================
## The first boss. Moves horizontally near the sea floor between
## attack phases. Only takes damage from super-speed collisions.
##
## STATE MACHINE:
##   INTRO → MOVING → ATTACKING ─┐ (looping)
##                    DEPLOYING_DRONE (can fire between phases)
##                    DYING
##
## ATTACK PATTERNS (chosen randomly each round):
##   1. FAN SALVO     – all missiles launched at once in a spread
##   2. AROUND_WORLD  – one missile per step, sweeping arc over time
##   3. HEAVY_SWEEP   – slower sweep, multiple missiles per step
## ============================================================

# ── Exported references ──────────────────────────────────────
@export var missile_scene: PackedScene
@export var drone_scene: PackedScene

# ── Movement ─────────────────────────────────────────────────
@export_group("Movement")
## How far from left/right edge the sub can patrol
@export var patrol_min_x: float = -220.0
@export var patrol_max_x: float = 220.0
## Y position the sub rests at (just above the sea floor)
@export var floor_patrol_y: float = 145.0
## How fast the sub travels between positions (pixels/sec)
@export var move_speed: float = 90.0
## Pause at destination before starting attack
@export var arrival_pause: float = 2

# ── Attack: Fan Salvo ────────────────────────────────────────
@export_group("Pattern 1: Fan Salvo")
## Total angular spread of the fan in degrees
@export var fan_spread_deg: float = 140.0
## Number of missiles in the simultaneous volley
@export var fan_missile_count: int = 9
@export var fan_missile_speed: float = 160.0

# ── Attack: Around-the-World ─────────────────────────────────
@export_group("Pattern 2: Around the World")
## Total arc swept in degrees
@export var arc_spread_deg: float = 180.0
## Number of steps (one missile per step)
@export var arc_step_count: int = 10
## Delay between each step (seconds)
@export var arc_step_delay: float = 0.18
@export var arc_missile_speed: float = 175.0

# ── Attack: Heavy Sweep ──────────────────────────────────────
@export_group("Pattern 3: Heavy Sweep")
## Number of angular steps in the sweep
@export var heavy_step_count: int = 7
## Missiles fired per step
@export var heavy_missiles_per_step: int = 3
## Angular spread within a single step's burst (degrees)
@export var heavy_burst_spread_deg: float = 12.0
## Delay between steps (slower than around-the-world)
@export var heavy_step_delay: float = 0.32
@export var heavy_missile_speed: float = 130.0

# ── Drones ────────────────────────────────────────────────────
@export_group("Drones")
## How often (seconds) a drone is deployed, regardless of attack phase
@export var drone_deploy_interval: float = 5.0
## Max drones alive at once
@export var max_active_drones: int = 6

# ── Invincibility window after a super-speed hit ─────────────
@export_group("Damage")
## Seconds the sub flashes invincible after a hit (prevents combo)
@export var hit_invincibility_duration: float = 1.2

# ─────────────────────────────────────────────────────────────
# Internal state
# ─────────────────────────────────────────────────────────────
enum State { INTRO, MOVING, PAUSING, ATTACKING, DYING }
var _state: State = State.INTRO

# Which attack to run next (cycles randomly)
enum AttackPattern { FAN_SALVO, AROUND_WORLD, HEAVY_SWEEP }
var _next_pattern: AttackPattern = AttackPattern.FAN_SALVO

# Drone bookkeeping
var _active_drones: Array[Node] = []
var _drone_timer: float = 0.0

# Hit-invincibility (separate from is_invincible — that blocks ALL damage)
var _hit_invincible: bool = false

# Cached node references (set in _enemy_ready)
var _missile_launch: Marker2D = null
var _hatch_point: Marker2D = null
var _player: Node2D = null
var _sprite: AnimatedSprite2D = null

# Original local X of the hatch (mirrored when sprite flips)
var _hatch_point_origin_x: float = 0.0

# ─────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────

func _enemy_ready() -> void:
	max_health = 500.0
	current_health = max_health
	contact_damage = 20.0
	knockback_force = 500.0

	# The sub is invincible to everything EXCEPT super-speed hits.
	# Bullets, normal contact, etc. will trigger the shake feedback
	# but deal no damage — which is the correct "you need super speed" cue.
	is_invincible = true

	add_to_group("submarine_boss")

	_missile_launch = get_node_or_null("MissileLaunchPoint")
	_hatch_point    = get_node_or_null("HatchPoint")
	_player         = get_tree().get_first_node_in_group("player")
	_sprite         = get_node_or_null("AnimatedSprite2D")

	if _hatch_point:
		_hatch_point_origin_x = _hatch_point.position.x

	if not _missile_launch:
		push_warning("SubmarineBoss: No MissileLaunchPoint Marker2D found!")
	if not _hatch_point:
		push_warning("SubmarineBoss: No HatchPoint Marker2D found!")
	if not missile_scene:
		push_warning("SubmarineBoss: missile_scene not assigned!")
	if not drone_scene:
		push_warning("SubmarineBoss: drone_scene not assigned!")

	# Start the main behaviour loop after a short intro pause
	_state = State.INTRO
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		_begin_move_phase()

# ─────────────────────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _state == State.DYING:
		return

	_tick_drone_timer(delta)
	_prune_dead_drones()

# ─────────────────────────────────────────────────────────────
# SUPER-SPEED HIT — called by the SuperSpeedHitArea signal
# ─────────────────────────────────────────────────────────────

## Called externally by the SuperSpeedHitArea's body_entered signal
## (connected in the scene via the Inspector).
func on_super_speed_hit(body: Node2D) -> void:
	# Only react to the player
	if not body.is_in_group("player"):
		return
	# Accept hits during active super speed OR the cooldown window.
	# The cooldown is a half-second grace period that visually looks like
	# super speed — this is exactly when most contacts happen, because the
	# collision response slows the turtle below the threshold on the same
	# frame the signal fires, so is_super_speed is often already false.
	var in_window: bool = body.get("is_super_speed") or body.get("is_super_speed_cooldown")
	if not in_window:
		return
	# Don't double-hit during invincibility window
	if _hit_invincible:
		return
	if _state == State.DYING:
		return

	# Bypass is_invincible — call internal damage directly
	_apply_super_speed_damage(body.get("super_speed_damage") if body.get("super_speed_damage") else 50.0)

func _apply_super_speed_damage(amount: float) -> void:
	current_health -= amount
	_play_damage_feedback()
	_start_hit_invincibility()

	if current_health <= 0:
		die()

func _start_hit_invincibility() -> void:
	_hit_invincible = true
	await get_tree().create_timer(hit_invincibility_duration).timeout
	if is_instance_valid(self):
		_hit_invincible = false

# ─────────────────────────────────────────────────────────────
# STATE: MOVING
# ─────────────────────────────────────────────────────────────

func _begin_move_phase() -> void:
	if _state == State.DYING:
		return
	_state = State.MOVING

	var target_x := randf_range(patrol_min_x, patrol_max_x)
	var target_pos := Vector2(target_x, floor_patrol_y)
	var distance := global_position.distance_to(target_pos)
	var travel_time := distance / move_speed

	# Flip sprite and markers to face the direction of travel
	_set_facing(target_x > global_position.x)

	# Tween handles the actual movement; AnimatableBody2D works perfectly with tweens.
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "global_position", target_pos, travel_time)
	await tween.finished

	if _state == State.DYING or not is_instance_valid(self):
		return

	# Arrival pause — sub slows to a stop
	_state = State.PAUSING
	await get_tree().create_timer(arrival_pause).timeout

	if _state == State.DYING or not is_instance_valid(self):
		return

	_begin_attack_phase()

# ─────────────────────────────────────────────────────────────
# STATE: ATTACKING
# ─────────────────────────────────────────────────────────────

func _begin_attack_phase() -> void:
	if _state == State.DYING:
		return
	_state = State.ATTACKING

	# Choose next pattern randomly
	_next_pattern = _pick_random_pattern()

	match _next_pattern:
		AttackPattern.FAN_SALVO:
			await _do_fan_salvo()
		AttackPattern.AROUND_WORLD:
			await _do_around_world()
		AttackPattern.HEAVY_SWEEP:
			await _do_heavy_sweep()

	# After attacking, move again
	if _state != State.DYING and is_instance_valid(self):
		_begin_move_phase()

func _pick_random_pattern() -> AttackPattern:
	var patterns := [
		AttackPattern.FAN_SALVO,
		AttackPattern.AROUND_WORLD,
		AttackPattern.HEAVY_SWEEP,
	]
	return patterns[randi() % patterns.size()]

# ─────────────────────────────────────────────────────────────
# PATTERN 1: FAN SALVO
# All missiles fire simultaneously in a wide arc aimed upward.
# The turtle must hide in the gaps between missile lines.
# ─────────────────────────────────────────────────────────────

func _do_fan_salvo() -> void:
	if not _missile_launch or not missile_scene:
		return

	# The fan is centred on "straight up" (angle = -90°).
	# We spread evenly across fan_spread_deg total.
	var half_spread := deg_to_rad(fan_spread_deg * 0.5)
	var step := deg_to_rad(fan_spread_deg) / (fan_missile_count - 1) if fan_missile_count > 1 else 0.0
	var start_angle := -PI * 0.5 - half_spread  # Top-left edge of fan

	for i in fan_missile_count:
		var angle := start_angle + step * i
		var dir := Vector2(cos(angle), sin(angle))
		_spawn_missile(dir * fan_missile_speed)

	# Small pause so the volley has time to leave before the sub moves
	await get_tree().create_timer(1.2).timeout

# ─────────────────────────────────────────────────────────────
# PATTERN 2: AROUND THE WORLD
# One missile per step, sweeping from left to right (or right to left)
# across a wide arc. Forces the turtle to keep moving.
# ─────────────────────────────────────────────────────────────

func _do_around_world() -> void:
	if not _missile_launch or not missile_scene:
		return

	# Sweep arc starts pointing upper-left, ends upper-right (through straight up)
	var half_spread := deg_to_rad(arc_spread_deg * 0.5)
	var step := deg_to_rad(arc_spread_deg) / float(max(arc_step_count - 1, 1))
	var start_angle := -PI * 0.5 - half_spread
	# Randomly choose sweep direction for variety
	var reverse := randi() % 2 == 1

	for i in arc_step_count:
		if _state == State.DYING or not is_instance_valid(self):
			return
		var idx := (arc_step_count - 1 - i) if reverse else i
		var angle := start_angle + step * idx
		var dir := Vector2(cos(angle), sin(angle))
		_spawn_missile(dir * arc_missile_speed)
		await get_tree().create_timer(arc_step_delay).timeout

	# Brief pause after sweep
	await get_tree().create_timer(0.5).timeout

# ─────────────────────────────────────────────────────────────
# PATTERN 3: HEAVY SWEEP
# Like Around-the-World but slower, with a small burst of
# missiles at each angular step instead of a single shot.
# Creates denser walls but with a slower overall rhythm.
# ─────────────────────────────────────────────────────────────

func _do_heavy_sweep() -> void:
	if not _missile_launch or not missile_scene:
		return

	var half_spread := deg_to_rad(arc_spread_deg * 0.5)
	var step := deg_to_rad(arc_spread_deg) / float(max(heavy_step_count - 1, 1))
	var start_angle := -PI * 0.5 - half_spread
	var half_burst := deg_to_rad(heavy_burst_spread_deg * 0.5)
	var burst_step := heavy_burst_spread_deg / (heavy_missiles_per_step - 1) if heavy_missiles_per_step > 1 else 0.0

	for i in heavy_step_count:
		if _state == State.DYING or not is_instance_valid(self):
			return

		var sweep_angle := start_angle + step * i
		# Fire a small burst spread around the sweep angle
		for b in heavy_missiles_per_step:
			var burst_offset := deg_to_rad(-heavy_burst_spread_deg * 0.5 + burst_step * b)
			var angle := sweep_angle + burst_offset
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_missile(dir * heavy_missile_speed)

		await get_tree().create_timer(heavy_step_delay).timeout

	await get_tree().create_timer(0.6).timeout

# ─────────────────────────────────────────────────────────────
# MISSILE SPAWNING HELPER
# ─────────────────────────────────────────────────────────────

func _spawn_missile(velocity: Vector2) -> void:
	if not missile_scene or not _missile_launch:
		return
	if _state == State.DYING or not is_instance_valid(self):
		return

	var missile = missile_scene.instantiate()
	# Add to parent level so missile outlives any sub movement tweens
	get_parent().add_child(missile)
	missile.global_position = _missile_launch.global_position

	if missile.has_method("set_velocity"):
		missile.set_velocity(velocity)
	else:
		missile.linear_velocity = velocity

# ─────────────────────────────────────────────────────────────
# DRONE DEPLOYMENT
# Drone timer ticks every frame during normal behaviour.
# When it fires, a drone is deployed from the hatch if we're
# not already at the max drone cap.
# ─────────────────────────────────────────────────────────────

func _tick_drone_timer(delta: float) -> void:
	if _state == State.INTRO or _state == State.DYING:
		return

	_drone_timer += delta
	if _drone_timer >= drone_deploy_interval:
		_drone_timer = 0.0
		_try_deploy_drone()

func _prune_dead_drones() -> void:
	_active_drones = _active_drones.filter(func(d): return is_instance_valid(d))

func _try_deploy_drone() -> void:
	_prune_dead_drones()
	if _active_drones.size() >= max_active_drones:
		return
	if not drone_scene or not _hatch_point:
		return

	# Play open_hatch animation and deploy drone immediately while it plays,
	# then return to default once the animation duration has elapsed.
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation("open_hatch"):
		_sprite.play("open_hatch")

	var drone = drone_scene.instantiate()
	get_parent().add_child(drone)
	drone.global_position = _hatch_point.global_position
	_active_drones.append(drone)

	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation("open_hatch"):
		var duration := _get_animation_duration("open_hatch")
		await get_tree().create_timer(duration).timeout
		if not is_instance_valid(self) or _state == State.DYING:
			return
		_sprite.play("default")

func _set_facing(facing_right: bool) -> void:
	if _sprite:
		_sprite.flip_h = facing_right
	if _hatch_point:
		_hatch_point.position.x = -_hatch_point_origin_x if facing_right else _hatch_point_origin_x

func _get_animation_duration(anim_name: String) -> float:
	if not _sprite or not _sprite.sprite_frames:
		return 0.5
	var frame_count := _sprite.sprite_frames.get_frame_count(anim_name)
	var fps := _sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.5
	return frame_count / fps

# ─────────────────────────────────────────────────────────────
# DEATH
# ─────────────────────────────────────────────────────────────

func die() -> void:
	if _state == State.DYING:
		return  # Guard against double-death
	_state = State.DYING

	# Kill all active drones
	for drone in _active_drones:
		if is_instance_valid(drone):
			drone.queue_free()
	_active_drones.clear()

	# Disable collision so nothing can interact during death sequence
	collision_layer = 0
	collision_mask = 0

	# Death sequence: rapid flashes, sink, fade
	var tween := create_tween()
	tween.set_parallel(true)

	# Rapid color flickering
	for i in 6:
		tween.tween_property(self, "modulate", Color(2.0, 0.5, 0.1, 1.0), 0.1) \
			.set_delay(i * 0.2)
		tween.tween_property(self, "modulate", Color.WHITE, 0.1) \
			.set_delay(i * 0.2 + 0.1)

	# Sink downward
	tween.tween_property(self, "global_position:y", global_position.y + 80.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Fade out (starts after flashes)
	tween.tween_property(self, "modulate:a", 0.0, 0.6).set_delay(1.0)

	tween.finished.connect(_on_death_sequence_complete)

func _on_death_sequence_complete() -> void:
	LevelManager.boss_defeated()
	queue_free()
