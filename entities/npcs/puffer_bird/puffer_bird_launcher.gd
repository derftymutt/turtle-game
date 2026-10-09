extends Node2D
class_name PufferBirdLauncher

## PUFFER BIRD LAUNCHER — the plunger. Opt-in per level: instance
## puffer_bird_launcher.tscn anywhere in a level, placed where the bird should
## be holding the turtle when the level opens (top middle of the opening
## screen, just above the water). LevelBase finds it and runs it instead of
## the "Press any button to start" prompt.
##
## The level stays frozen (tree paused) the whole time, exactly as it does
## behind the start prompt; this node runs with PROCESS_MODE_ALWAYS and moves
## the turtle by hand, which is also what makes the plunge pass through
## everything — the physics world isn't stepping.
##
## Life cycle:
##   HOLDING  — grab_turtle(): the bird has the turtle and the Picky Puffer's
##              sea urchin is glowing, but the countdown hasn't begun (a
##              BossIntroPopup is still up).
##   AIMING   — begin(): the countdown runs. Left / right pivots the plunge
##              angle, holding the launch button sweeps the power up and down
##              and releasing it plunges — the same inputs as the community
##              UFO. The bird itself stays put. The countdown reaching zero
##              plunges too.
##   PLUNGING — bird and turtle dive along the aim, slowing as they go, held
##              inside the screen and the world boundaries.
##   LEAVING  — the plunge has stopped. Within `eat_radius` of the glowing
##              urchin the bird eats it (gone for good, counted by
##              GameManager.record_puffer_skill_shot()). Either way the level
##              starts and the bird flies off.

## The plunge is over and the level is running (same meaning as
## LevelStartPrompt.started).
signal started
## Emitted with `started`: whether the bird got its sea urchin.
signal plunge_finished(ate_urchin: bool)

@export_group("Countdown")
## Seconds to line the plunge up before the bird goes on its own
@export var countdown_seconds: float = 10.0
## Power (0..1) used if the countdown runs out with the button never pressed
@export_range(0.0, 1.0, 0.05) var timeout_power: float = 0.5

@export_group("Aiming")
## How fast the plunge angle pivots, in degrees per second
@export var pivot_speed_degrees: float = 80.0
## Furthest the plunge can be angled away from straight down
@export var max_pivot_degrees: float = 88.0

@export_group("Plunge")
@export var launch_action: String = "ufo_windup"
## Plunge speed at empty power. Reach = (speed - stop_speed) / plunge_drag,
## so the default is only a few pixels — an urchin right under the bird is still a fair target. Full power isn't set here: it is worked out
## per level so a full plunge aimed at the far bottom corner of the screen
## just gets there (see _full_launch_speed) — aimed anywhere steeper it
## overshoots and bounces back off the floor or wall.
@export var min_launch_speed: float = 60.0
## Seconds for the power to climb from empty to full while the button is held.
## At full it drops straight back to empty and climbs again — the plunger
## being let back in and pulled once more.
@export var charge_sweep_seconds: float = 0.9
## Shape of the climb: 1 = steady, above 1 = the power changes slowly while
## it's low and picks up speed toward full
@export_range(1.0, 3.0, 0.05) var charge_curve: float = 1.0
## How quickly the plunge slows (fraction of speed lost per second, roughly)
@export var plunge_drag: float = 2.5
## How fast the plunge plays out: 2 = the same path and stopping point in half
## the time. Purely the plunge's own clock — reach and bounces don't change.
@export_range(0.5, 4.0, 0.05) var plunge_time_scale: float = 2.5
## The plunge is over once it slows to this
@export var stop_speed: float = 45.0
## The plunge stays this far inside the edges of the screen
@export var screen_margin: float = 12.0
## Blinking no-damage window for the turtle once the level starts
@export var landing_grace_seconds: float = 1.0

@export_group("Skill Shot")
## The bird eats the glowing urchin if the plunge stops within this distance
@export var eat_radius: float = 24.0
## How much bigger the glowing urchin swells at the top of each throb
@export var target_throb: float = 0.35
@export var target_glow_color: Color = Color(1.0, 0.9, 0.3, 1.0)

@export_group("Visual")
## Marks where the plunge will stop while the power is sweeping
@export var show_landing_preview: bool = false
@export var aim_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var flap_fps: float = 6.0

enum State { IDLE, HOLDING, AIMING, PLUNGING, LEAVING }
var _state: State = State.IDLE

## Presses this soon after the countdown starts are ignored — the player may
## still be mashing through the screen that led here.
const _ARM_DELAY_MSEC: int = 400
## The turtle hangs from the bird's feet, a little under the node's origin
const _TURTLE_OFFSET := Vector2(0.0, 8.0)
const _LEAVE_SPEED := Vector2(70.0, -260.0)
const _LEAVE_SECONDS: float = 2.5
const _EAT_SECONDS: float = 0.3
## Under the pause menu (layer 8), which can open on top of this
const _UI_LAYER: int = 5
## The bird itself draws over the HUD (layer 1), which covers the top of the sky
const _BIRD_LAYER: int = 2
## The power gauge, relative to this node: right of the bird, clear of the HUD
const _POWER_METER := Rect2(28.0, -16.0, 8.0, 56.0)
const _COUNTDOWN_SIZE := Vector2(36.0, 32.0)
## The two text lines sit this far under the ocean surface, one in each half
## of the screen so the bird's aim runs down between them
const _TEXT_BELOW_SURFACE: float = 6.0
const _TEXT_HEIGHT: float = 16.0
const _TARGET_TEXT: String = "Picky Puffer wants her sea urchin!"

## The TurtlePlayer (it has no class_name, so its own methods go through call())
var _turtle: RigidBody2D = null
var _target: SeaUrchin = null
## Plunge angle away from straight down, in radians (positive = to the right)
var _aim: float = 0.0
var _remaining: float = 0.0
var _begin_msec: int = 0
var _charging: bool = false
var _power: float = 0.0
## Where the climb is, 0..1 before `charge_curve` shapes it into power
var _charge_phase: float = 0.0
## Plunge speed at full power, from the level's bounds (see min_launch_speed)
var _full_launch_speed: float = 1200.0
var _velocity: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()
var _leave_timer: float = 0.0
var _facing: float = 1.0
var _draw_time: float = 0.0
var _eat_tween: Tween = null
## The urchin the bird caught, on its way out of the level with it
var _carried_urchin: SeaUrchin = null
## The viewport-following layer over the HUD that the bird sprite lives on
var _bird_layer: CanvasLayer = null
## The bird sprite's place relative to this node (its position in the scene)
var _bird_offset: Vector2 = Vector2.ZERO

var _ui: CanvasLayer = null
var _countdown_label: Label = null
var _hint_label: Label = null

@onready var _bird: Sprite2D = $Bird

func _ready() -> void:
	add_to_group("plunge_launchers")
	# Nothing to see in a level that never runs it (training mode)
	visible = false
	set_process(false)

# ---------------------------------------------------------------------------
# PUBLIC — driven by LevelBase
# ---------------------------------------------------------------------------

## The bird takes hold of the turtle and picks its sea urchin. Called at level
## load, before any frame runs; safe to call twice.
func grab_turtle() -> void:
	if _state != State.IDLE:
		return
	_turtle = get_tree().get_first_node_in_group("player") as RigidBody2D
	if _turtle == null:
		push_warning("PufferBirdLauncher: no turtle to hold")
		return
	_state = State.HOLDING
	visible = true
	_lift_bird_above_hud()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_carry_turtle()
	# The camera framed wherever the turtle sat in the scene, and won't run
	# again until the level does
	var camera := get_viewport().get_camera_2d()
	if camera:
		if camera.has_method("snap_to_target"):
			camera.snap_to_target()
		camera.force_update_scroll()
	_bounds = _play_bounds()
	global_position = _clamp_to_bounds(global_position)
	if _bounds.has_area():
		# Far enough for the further of the two bottom corners
		var corner_reach: float = maxf(
			global_position.distance_to(Vector2(_bounds.position.x, _bounds.end.y)),
			global_position.distance_to(_bounds.end))
		_full_launch_speed = maxf(min_launch_speed, corner_reach * plunge_drag + stop_speed)
	_carry_turtle()
	_target = _pick_target()

## Moves the bird sprite onto its own canvas layer over the HUD. The layer
## follows the viewport, so the sprite still lives in level coordinates — but
## it no longer inherits this node's transform or modulate, hence
## _update_bird() placing it every frame.
func _lift_bird_above_hud() -> void:
	_bird_offset = _bird.position
	_bird_layer = CanvasLayer.new()
	_bird_layer.layer = _BIRD_LAYER
	_bird_layer.follow_viewport_enabled = true
	add_child(_bird_layer)
	_bird.reparent(_bird_layer)

## Freezes the level and starts the countdown.
func begin() -> void:
	grab_turtle()
	if _state != State.HOLDING:
		# Nothing to launch — don't leave the level waiting on us
		get_tree().paused = false
		started.emit()
		return
	get_tree().paused = true
	_state = State.AIMING
	_remaining = countdown_seconds
	_begin_msec = Time.get_ticks_msec()
	_build_ui()

# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_draw_time += delta
	match _state:
		State.HOLDING:
			_carry_turtle()
		State.AIMING:
			# Everything waits while the pause menu is open over it
			var pause_menu := get_tree().get_first_node_in_group("pause_menu") as CanvasLayer
			var menu_open: bool = pause_menu != null and pause_menu.visible
			_ui.visible = not menu_open
			if not menu_open:
				_aim_tick(delta)
		State.PLUNGING:
			_plunge_tick(delta)
		State.LEAVING:
			_leave_tick(delta)
	_update_bird()
	_throb_target()
	queue_redraw()

func _aim_tick(delta: float) -> void:
	# Left / right swings the aim that way; the bird stays where it is
	var pivot: float = Input.get_axis("move_left", "move_right")
	var max_pivot: float = deg_to_rad(max_pivot_degrees)
	_aim = clampf(_aim + clampf(pivot, -1.0, 1.0) * deg_to_rad(pivot_speed_degrees) * delta, -max_pivot, max_pivot)
	if absf(_aim) > 0.02:
		_facing = signf(_aim)
	_carry_turtle()

	_remaining -= delta
	_countdown_label.text = str(maxi(1, ceili(_remaining)))
	_place_countdown()
	_hint_label.text = "Hold %s for power, release to plunge" % ("A" if GameSettings.using_gamepad else "Z")

	if Time.get_ticks_msec() - _begin_msec >= _ARM_DELAY_MSEC:
		if not _charging:
			if Input.is_action_just_pressed(launch_action):
				_charging = true
				_power = 0.0
				_charge_phase = 0.0
		elif Input.is_action_pressed(launch_action):
			_charge_phase = fposmod(_charge_phase + delta / maxf(charge_sweep_seconds, 0.05), 1.0)
			_power = pow(_charge_phase, charge_curve)
		else:
			_plunge(_power)
			return
	if _remaining <= 0.0:
		_plunge(_power if _charging else timeout_power)

func _plunge(power: float) -> void:
	_state = State.PLUNGING
	_velocity = _aim_direction() * _launch_speed(power)
	if absf(_velocity.x) > 1.0:
		_facing = signf(_velocity.x)
	_ui.queue_free()
	_ui = null

func _plunge_tick(delta: float) -> void:
	# Exact for exponential slowing, so the plunge stops where the preview said
	delta *= plunge_time_scale
	var decay: float = exp(-plunge_drag * delta)
	var moved: Vector2 = global_position + _velocity * (1.0 - decay) / plunge_drag
	_velocity *= decay
	# Bounces off the edges of the play bounds, losing nothing
	if _bounds.has_area():
		if moved.x < _bounds.position.x or moved.x > _bounds.end.x:
			_velocity.x = -_velocity.x
			_facing = signf(_velocity.x)
		if moved.y < _bounds.position.y or moved.y > _bounds.end.y:
			_velocity.y = -_velocity.y
	global_position = _fold_into_bounds(moved)
	_carry_turtle()
	if _velocity.length() <= stop_speed:
		_finish()

## The plunge has stopped: eat the urchin if it's in reach, hand the turtle
## back to the physics world and start the level.
func _finish() -> void:
	var ate: bool = is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= eat_radius
	if is_instance_valid(_target) and _target.sprite:
		_target.sprite.scale = Vector2.ONE
	if ate:
		GameManager.record_puffer_skill_shot()
		_eat(_target)
	_target = null

	if is_instance_valid(_turtle):
		_carry_turtle()
		_turtle.linear_velocity = _velocity
		_turtle.call("grant_grace_iframes", landing_grace_seconds)
	_turtle = null

	_state = State.LEAVING
	_leave_timer = 0.0
	# From here on the bird pauses with the game like anything else
	process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = false
	started.emit()
	plunge_finished.emit(ate)

## The bird lets the turtle go and snatches the urchin up into its feet
## instead; _leave_tick() then carries it off.
func _eat(urchin: SeaUrchin) -> void:
	urchin.be_eaten()
	_carried_urchin = urchin
	# Onto the bird's layer, behind the bird, so the pair cross the HUD together
	if _bird_layer:
		urchin.reparent(_bird_layer)
		_bird_layer.move_child(urchin, 0)
	if urchin.sprite:
		urchin.sprite.position = Vector2.ZERO
	urchin.rotation = 0.0
	_eat_tween = create_tween()
	_eat_tween.tween_property(urchin, "global_position", global_position + _TURTLE_OFFSET, _EAT_SECONDS)

func _leave_tick(delta: float) -> void:
	# Get a grip on the urchin first
	if _eat_tween and _eat_tween.is_valid() and _eat_tween.is_running():
		return
	_leave_timer += delta
	global_position += Vector2(_LEAVE_SPEED.x * _facing, _LEAVE_SPEED.y) * delta
	modulate.a = clampf((_LEAVE_SECONDS - _leave_timer) / 0.4, 0.0, 1.0)
	# The urchin leaves in the bird's clutches, the way the turtle arrived
	if is_instance_valid(_carried_urchin):
		_carried_urchin.global_position = global_position + _TURTLE_OFFSET
		_carried_urchin.modulate.a = modulate.a
	if _leave_timer >= _LEAVE_SECONDS:
		if is_instance_valid(_carried_urchin):
			_carried_urchin.queue_free()
		queue_free()

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

func _aim_direction() -> Vector2:
	return Vector2(sin(_aim), cos(_aim))

func _launch_speed(power: float) -> float:
	return lerpf(min_launch_speed, _full_launch_speed, clampf(power, 0.0, 1.0))

## Where a plunge at `power` would stop.
func _landing_point(power: float) -> Vector2:
	var reach: float = maxf(0.0, _launch_speed(power) - stop_speed) / plunge_drag
	return _fold_into_bounds(global_position + _aim_direction() * reach)

## The turtle is paused with the rest of the level; it goes where the bird does.
func _carry_turtle() -> void:
	if is_instance_valid(_turtle):
		_turtle.global_position = global_position + _TURTLE_OFFSET
		_turtle.linear_velocity = Vector2.ZERO
		_turtle.angular_velocity = 0.0

## The screen the level opens on, less a margin, cut down to the world
## boundaries where those are closer.
func _play_bounds() -> Rect2:
	var view_size: Vector2 = get_viewport_rect().size
	var view := Rect2(Vector2.ZERO, view_size)
	var camera := get_viewport().get_camera_2d()
	if camera:
		var world_size: Vector2 = view_size / camera.zoom
		view = Rect2(camera.get_screen_center_position() - world_size * 0.5, world_size)
	else:
		view = get_viewport().get_canvas_transform().affine_inverse() * view
	var left: float = view.position.x + screen_margin
	var right: float = view.end.x - screen_margin
	var top: float = view.position.y + screen_margin
	var bottom: float = view.end.y - screen_margin
	if is_instance_valid(_turtle):
		var limits: Dictionary = _turtle.call("_get_boundary_limits")
		left = maxf(left, limits.min_x)
		right = minf(right, limits.max_x)
		bottom = minf(bottom, limits.max_y - _TURTLE_OFFSET.y)
	return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))

## A straight path that left the bounds, bounced back in off every edge it
## crossed: where it actually ends up.
func _fold_into_bounds(point: Vector2) -> Vector2:
	if not _bounds.has_area():
		return point
	return _bounds.position + Vector2(
		pingpong(point.x - _bounds.position.x, _bounds.size.x),
		pingpong(point.y - _bounds.position.y, _bounds.size.y))

func _clamp_to_bounds(point: Vector2) -> Vector2:
	if not _bounds.has_area():
		return point
	return point.clamp(_bounds.position, _bounds.end)

## One sea urchin the bird can actually reach from where it sits (on the
## opening screen, inside the pivot range and the plunge's reach), at random.
## Null if there is none — the plunge still works, just with no skill shot.
func _pick_target() -> SeaUrchin:
	var candidates: Array[SeaUrchin] = []
	for node in get_tree().get_nodes_in_group("sea_urchins"):
		var urchin := node as SeaUrchin
		if urchin == null or not urchin.visible:
			continue
		var at: Vector2 = urchin.global_position
		var offset: Vector2 = at - global_position
		var angle: float = absf(atan2(offset.x, offset.y))
		var reach: float = (_full_launch_speed - stop_speed) / plunge_drag
		# An urchin tucked against a wall sits just outside the bounds the
		# plunge travels in, but still inside eating distance of them
		var near_bounds: Rect2 = _bounds.grow(eat_radius * 0.75)
		# Not so close that even an empty-power plunge sails past it
		var min_reach: float = maxf(0.0, min_launch_speed - stop_speed) / plunge_drag - eat_radius
		if near_bounds.has_point(at) and angle <= deg_to_rad(max_pivot_degrees) and offset.length() <= reach and offset.length() >= min_reach:
			candidates.append(urchin)
	if candidates.is_empty():
		return null
	return candidates.pick_random()

func _throb_target() -> void:
	if _state == State.LEAVING or not is_instance_valid(_target) or _target.sprite == null:
		return
	_target.sprite.scale = Vector2.ONE * (1.0 + target_throb * _pulse())

func _pulse() -> float:
	return 0.5 + 0.5 * sin(_draw_time * 6.0)

func _update_bird() -> void:
	_bird.global_position = global_position + _bird_offset
	_bird.modulate.a = modulate.a
	_bird.flip_h = _facing < 0.0
	match _state:
		State.PLUNGING:
			_bird.frame = 0
		State.LEAVING:
			_bird.frame = int(_draw_time * flap_fps * 2.0) % _bird.hframes
		_:
			_bird.frame = int(_draw_time * flap_fps) % _bird.hframes

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = _UI_LAYER
	add_child(_ui)
	# Just under the water line: controls left of centre, the urchin right
	var screen: Vector2 = get_viewport_rect().size
	var ocean := get_tree().get_first_node_in_group("ocean") as Ocean
	var surface_y: float = ocean.surface_y if ocean else global_position.y
	var text_y: float = (get_viewport().get_canvas_transform() * Vector2(0.0, surface_y)).y + _TEXT_BELOW_SURFACE
	_hint_label = _make_label(16)
	_hint_label.position = Vector2(0.0, text_y)
	_hint_label.size = Vector2(screen.x * 0.5, _TEXT_HEIGHT)
	if is_instance_valid(_target):
		var target_label := _make_label(16)
		target_label.text = _TARGET_TEXT
		target_label.position = Vector2(screen.x * 0.5, text_y)
		target_label.size = Vector2(screen.x * 0.5, _TEXT_HEIGHT)
	# The countdown rides beside the bird, where the player is looking
	_countdown_label = _make_label(32)
	_countdown_label.size = _COUNTDOWN_SIZE
	_place_countdown()

## Left of the bird (the power bar is on its right), or right of it when the
## bird is up against the left edge of the screen.
func _place_countdown() -> void:
	var bird_on_screen: Vector2 = get_global_transform_with_canvas().origin + _bird_offset
	var side: float = -1.0 if bird_on_screen.x > _COUNTDOWN_SIZE.x * 2.0 else 1.6
	_countdown_label.position = bird_on_screen + Vector2(side * _COUNTDOWN_SIZE.x, 0.0) - _COUNTDOWN_SIZE * 0.5

func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	_ui.add_child(label)
	return label

func _draw() -> void:
	# The Picky Puffer's urchin
	if _state != State.LEAVING and is_instance_valid(_target):
		var at: Vector2 = to_local(_target.global_position)
		var pulse: float = _pulse()
		for i in 3:
			draw_circle(at, 9.0 + i * 4.0 + pulse * 3.0, Color(target_glow_color, 0.24 - i * 0.07))
		draw_arc(at, 13.0 + pulse * 4.0, 0.0, TAU, 24, Color(target_glow_color, 0.9), 1.0)
	if _state != State.AIMING:
		return
	# Aim: blinking dots down the plunge line
	var dir := _aim_direction()
	for i in 5:
		var blink: float = 0.45 + 0.55 * absf(sin(_draw_time * 6.0 - i * 0.9))
		draw_circle(_TURTLE_OFFSET + dir * (16.0 + i * 9.0), 2.0 - i * 0.25, Color(aim_color, blink))
	_draw_power_meter()
	if not _charging:
		return
	if show_landing_preview:
		var landing: Vector2 = to_local(_landing_point(_power))
		draw_arc(landing, 5.0, 0.0, TAU, 16, Color(aim_color, 0.95), 1.0)
		draw_circle(landing, 1.5, Color(aim_color, 0.95))

## The plunger gauge beside the bird: the one thing to read the strength from.
## Always up while aiming, empty until the button is held.
func _draw_power_meter() -> void:
	var bar := _POWER_METER
	draw_rect(bar.grow(2.0), Color(0.0, 0.0, 0.0, 0.85))
	draw_rect(bar, Color(0.16, 0.18, 0.24, 1.0))
	if _charging:
		var fill: float = bar.size.y * _power
		draw_rect(Rect2(bar.position.x, bar.end.y - fill, bar.size.x, fill), Color(1.0, 0.9, 0.3).lerp(Color(1.0, 0.25, 0.1), _power))
	# Quarter marks
	for i in range(1, 4):
		var y: float = bar.end.y - bar.size.y * i / 4.0
		draw_line(Vector2(bar.position.x, y), Vector2(bar.position.x + bar.size.x * 0.5, y), Color(1.0, 1.0, 1.0, 0.7), 1.0)
