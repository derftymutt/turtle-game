extends BaseEnemy
class_name PufferFish

## Slow, calm swimmer that drifts with only a light pull toward the player.
##
## States:
##   NORMAL   — takes spit damage normally.
##   PUFFED   — entered when its contact actually costs the turtle a heart.
##              Grows, and is invincible to spit (is_invincible — so bullets,
##              flipper automaton and Multi-Beam all treat it like the urchin)
##              until puff_duration runs out. Still deals contact damage.
##   CAPTURED — the turtle rammed it at super speed (from either state) and
##              is inside. The fish puffs, stops, and spins; the turtle is
##              shot out of the mouth on the eject button, or automatically
##              after capture_duration. The fish then dies.
##
## While CAPTURED the turtle drives update_capture() from its own
## _physics_process, so the capture keeps ticking even when this body's
## callbacks are switched off (Time Freeze, Multi-Beam shock).

@export_group("Swimming")
@export var swim_force: float = 60.0
@export var max_speed: float = 40.0
@export var patrol_radius: float = 60.0
@export var patrol_change_interval: float = 3.0
@export var detection_range: float = 180.0
## 0 = ignores the player, 1 = swims straight at them. Kept low on purpose —
## the puffer drifts toward the turtle, it never chases.
@export_range(0.0, 1.0) var player_tracking: float = 0.25
## Swim force multiplier while puffed (a puffed fish mostly just drifts)
@export var puffed_swim_multiplier: float = 0.3
@export var steer_probe: float = 40.0

@export_group("Depth")
@export var preferred_depth_min: float = 40.0
@export var preferred_depth_max: float = 160.0
@export var depth_correction_force: float = 30.0

@export_group("Puff")
@export var puff_duration: float = 5.0
## Collision (body + DamageArea) grows by this factor while puffed. Set the
## normal-state shape sizes in the scene; the puffed size follows from this.
@export var puffed_collision_scale: float = 1.5
@export var puff_grow_time: float = 0.12

@export_group("Capture")
@export var capture_duration: float = 2.0
@export var eject_action: String = "ufo_windup"
## Eject presses are ignored this long into a capture, so the press that
## dismisses the first-time tutorial popup doesn't also fire the turtle out.
@export var eject_input_grace: float = 0.2
## Spin speed while the turtle is inside, in turns per second
@export var spin_turns_per_second: float = 1.0
## Launch speed out of the mouth. Must stay above the turtle's
## super_speed_threshold (300) long enough to reach the next puffer —
## ~700 carries super speed roughly 150px through water.
@export var eject_speed: float = 700.0

enum State { NORMAL, PUFFED, CAPTURED, DYING }
var state: State = State.NORMAL

var player: Node2D = null
var ocean: Ocean = null

var _patrol_center: Vector2
var _patrol_target: Vector2
var _patrol_timer: float = 0.0
var _puff_timer: float = 0.0
var _capture_timer: float = 0.0
var _captured_player: Node2D = null
var _spin_sign: float = 1.0
var _grow_tween: Tween = null

@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _damage_shape: CollisionShape2D = $DamageArea/CollisionShape2D
## Place this on the fish's mouth (right side of the unflipped sprite).
## It's mirrored and rotated in code to follow the sprite.
@onready var _mouth: Marker2D = $Mouth

func _enemy_ready():
	gravity_scale = 0.0
	linear_damp = 2.0
	angular_damp = 5.0
	lock_rotation = true  # only the sprite spins, never the body
	mass = 1.0

	max_health = 60.0
	current_health = max_health
	contact_damage = 15.0
	knockback_force = 200.0
	death_label = "a puffer fish"
	add_to_group("puffers")  # PufferSpawner counts these against its cap

	ocean = get_tree().get_first_node_in_group("ocean")
	player = get_tree().get_first_node_in_group("player")

	_patrol_center = global_position
	_choose_new_patrol_target()
	_patrol_timer = randf() * patrol_change_interval

func _physics_process(delta: float):
	match state:
		State.NORMAL:
			_swim(delta, 1.0)
		State.PUFFED:
			_swim(delta, puffed_swim_multiplier)
			_puff_timer -= delta
			if _puff_timer <= 0.0:
				_deflate()
		_:
			return  # CAPTURED is ticked by the turtle; DYING does nothing

	_maintain_depth()
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

# ---------------------------------------------------------------------------
# SWIMMING
# ---------------------------------------------------------------------------

func _swim(delta: float, force_multiplier: float) -> void:
	_patrol_timer += delta
	if _patrol_timer >= patrol_change_interval or global_position.distance_to(_patrol_target) < 8.0:
		_patrol_timer = 0.0
		_choose_new_patrol_target()

	var desired := (_patrol_target - global_position).normalized()
	if is_instance_valid(player):
		var to_player: Vector2 = player.global_position - global_position
		if to_player.length() < detection_range:
			desired = desired.lerp(to_player.normalized(), player_tracking).normalized()

	if desired == Vector2.ZERO:
		return
	apply_central_force(_steer_toward(desired, steer_probe) * swim_force * force_multiplier)
	if sprite and absf(desired.x) > 0.1:
		sprite.flip_h = desired.x < 0

func _choose_new_patrol_target() -> void:
	var angle := randf() * TAU
	_patrol_target = _patrol_center + Vector2(cos(angle), sin(angle)) * randf_range(patrol_radius * 0.4, patrol_radius)

func _maintain_depth() -> void:
	if not ocean:
		return
	var depth := ocean.get_depth(global_position)
	if depth < 0:
		global_position.y = ocean.surface_y
		linear_velocity.y = maxf(linear_velocity.y, 0.0)
	elif depth < preferred_depth_min:
		apply_central_force(Vector2(0, depth_correction_force))
	elif depth > preferred_depth_max:
		apply_central_force(Vector2(0, -depth_correction_force))

# ---------------------------------------------------------------------------
# DAMAGE / PUFF
# ---------------------------------------------------------------------------

## Puffs only when the hit actually cost the turtle a heart — not when it was
## blocked by i-frames, a shield, super speed, etc.
func _deal_damage_to_player(target: Node2D):
	var hearts_before: int = target.get("current_hearts")
	super(target)
	var hearts_after: int = target.get("current_hearts")
	if hearts_after < hearts_before and state == State.NORMAL:
		_puff()

func take_damage(amount: float):
	if state == State.CAPTURED or state == State.DYING:
		return
	super(amount)
	# Any hit that doesn't kill it makes it puff — so killing it with spit
	# alone means waiting out the invincible window between shots.
	if state == State.NORMAL and current_health > 0.0:
		_puff()

func _puff() -> void:
	state = State.PUFFED
	_puff_timer = puff_duration
	is_invincible = true
	_play_anim("puff")
	_set_collision_scale(puffed_collision_scale)

func _deflate() -> void:
	state = State.NORMAL
	is_invincible = false
	_play_anim(_unpuffed_anim())
	_set_collision_scale(1.0)

func _set_collision_scale(target: float) -> void:
	if _grow_tween and _grow_tween.is_valid():
		_grow_tween.kill()
	_grow_tween = create_tween().set_parallel(true)
	_grow_tween.tween_property(_body_shape, "scale", Vector2.ONE * target, puff_grow_time)
	_grow_tween.tween_property(_damage_shape, "scale", Vector2.ONE * target, puff_grow_time)
	if sprite:
		# Quick overshoot pop so the change reads instantly
		var pop := create_tween()
		pop.tween_property(sprite, "scale", Vector2.ONE * 1.25, puff_grow_time * 0.5)
		pop.tween_property(sprite, "scale", Vector2.ONE, puff_grow_time)

func _play_anim(anim_name: String) -> void:
	if sprite is AnimatedSprite2D:
		var anim := sprite as AnimatedSprite2D
		if anim.sprite_frames and anim.sprite_frames.has_animation(anim_name):
			anim.play(anim_name)

## Unpuffed look: near_death once one more spit would kill it (same 10hp
## threshold BaseEnemy uses), otherwise default.
func _unpuffed_anim() -> String:
	if current_health <= 10.0 and sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames.has_animation("near_death"):
		return "near_death"
	return "default"

## The base damage animation resumes whatever was playing before the hit —
## make sure that's the right look for the current state.
func _resume_animation_after_damage(animated_sprite: AnimatedSprite2D, _previous_animation: String, _previous_frame: int) -> void:
	var anim_name := _unpuffed_anim() if state == State.NORMAL else "puff"
	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)

# ---------------------------------------------------------------------------
# CAPTURE
# ---------------------------------------------------------------------------

## Called by the turtle's SuperSpeedArea instead of take_damage().
func on_super_speed_contact(turtle: Node2D) -> void:
	if state == State.CAPTURED or state == State.DYING:
		return
	if not turtle.enter_puffer(self):
		return  # already inside another puffer

	if state == State.NORMAL:
		_set_collision_scale(puffed_collision_scale)
		_play_anim("puff")
	state = State.CAPTURED
	_captured_player = turtle
	_capture_timer = capture_duration
	is_invincible = true

	# Hold still while the turtle is inside
	linear_velocity = Vector2.ZERO
	set_deferred("freeze", true)
	_contact_players.clear()
	if damage_area:
		damage_area.set_deferred("monitoring", false)

	# Spin toward the side the turtle came in from, so it feels like the hit
	# set the fish turning
	var incoming: Vector2 = turtle.linear_velocity
	_spin_sign = 1.0 if incoming.cross(global_position - turtle.global_position) >= 0.0 else -1.0

	PufferTutorialPopup.show_once(get_tree(), eject_action)

## Ticked by the turtle every physics frame while it's inside.
func update_capture(turtle: Node2D, delta: float) -> void:
	if sprite:
		sprite.rotation += _spin_sign * spin_turns_per_second * TAU * delta
	turtle.global_position = global_position

	_capture_timer -= delta
	var eject_pressed := Input.is_action_just_pressed(eject_action) and capture_duration - _capture_timer >= eject_input_grace
	if eject_pressed or _capture_timer <= 0.0:
		_eject(turtle)

func _eject(turtle: Node2D) -> void:
	var mouth_dir := _mouth_offset().normalized()
	if mouth_dir == Vector2.ZERO:
		mouth_dir = Vector2.RIGHT
	turtle.exit_puffer(_safe_mouth_position(turtle), mouth_dir * eject_speed)
	_captured_player = null
	_report_kill()
	die()

## Mouth position relative to the fish, following the sprite's mirror + spin.
func _mouth_offset() -> Vector2:
	var local := _mouth.position if _mouth else Vector2(12, 0)
	if sprite and sprite.flip_h:
		local.x = -local.x
	var spin: float = sprite.rotation if sprite else 0.0
	return local.rotated(spin)

## Raycast out to the mouth so the turtle is never placed inside a wall.
func _safe_mouth_position(turtle: Node2D) -> Vector2:
	var target := global_position + _mouth_offset()
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collision_mask = 1
	query.exclude = [self, turtle]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	var hit_pos: Vector2 = hit.position
	return global_position + (hit_pos - global_position) * 0.5

## The turtle is going away without ejecting (freed, level ending, etc.).
func release_captured() -> void:
	_captured_player = null
	if state == State.CAPTURED:
		die()

# ---------------------------------------------------------------------------
# DEATH
# ---------------------------------------------------------------------------

func die():
	if state == State.DYING:
		return
	# Still holding the turtle (killed some other way) — let it out first
	if _captured_player and is_instance_valid(_captured_player):
		var turtle := _captured_player
		_captured_player = null
		turtle.exit_puffer(global_position, Vector2.ZERO)
	state = State.DYING
	current_health = 0.0
	_contact_players.clear()
	collision_layer = 0
	collision_mask = 0
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	if randf() < 0.02:
		_drop_alien_tech_piece()
	_play_die_sound()

	# Deflate and float up, same flavour as the piranha
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	if sprite:
		tween.tween_property(sprite, "scale", Vector2.ONE * 0.6, 0.8)
	tween.tween_property(self, "global_position:y", global_position.y - 60, 0.8)
	tween.finished.connect(queue_free)

func _exit_tree() -> void:
	if _captured_player and is_instance_valid(_captured_player):
		var turtle := _captured_player
		_captured_player = null
		turtle.exit_puffer(global_position, Vector2.ZERO)
