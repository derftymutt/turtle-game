extends Node2D
class_name PuffinLauncher

## PUFFIN LAUNCHER — the plunger. Opt-in per level: instance
## puffin_launcher.tscn anywhere in a level, placed where the bird should
## be holding the turtle when the level opens (top middle of the opening
## screen, just above the water). LevelBase finds it and runs it instead of
## the start countdown.
##
## The level stays frozen (tree paused) the whole time, exactly as it does
## behind the start prompt; this node runs with PROCESS_MODE_ALWAYS and moves
## the turtle by hand, which is also what makes the plunge pass through
## everything — the physics world isn't stepping.
##
## Life cycle:
##   HOLDING  — grab_turtle(): the bird has the turtle and the Picky Puffin's
##              sea urchin is glowing, but the countdown hasn't begun (a
##              BossIntroPopup is still up).
##   SPOTTING — begin(): a yellow twinkle shoots from the bird's eye to its
##              urchin, which starts glowing as it lands. Skipped if the
##              level has no urchin for it.
##   AIMING   — the countdown runs. Left / right pivots the plunge
##              angle, holding the launch button sweeps the power up and down
##              and releasing it plunges — the same inputs as the community
##              UFO. The bird itself stays put. The countdown reaching zero
##              plunges too.
##   PLUNGING — bird and turtle dive along the aim, slowing as they go, held
##              inside the screen and the world boundaries.
##   LEAVING  — the plunge has stopped. Within `eat_radius` of the glowing
##              urchin the bird eats it (gone for good, counted by
##              GameManager.record_puffin_skill_shot()). Either way the level
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
## Seconds after a catch before its bonus trash bag drifts in
@export var trash_bag_delay: float = 2.0
@export var target_glow_color: Color = Color(1.0, 0.9, 0.3, 1.0)

@export_group("Visual")
## Marks where the plunge will stop while the power is sweeping
@export var show_landing_preview: bool = false
## The solid boxes behind the two text lines beside the bird (a dark take on
## the orange of a puffin's beak)
@export var text_box_color: Color = Color(0.82, 0.4, 0.04, 1.0)
## The glow behind the bird and turtle before the plunge, and how far it reaches
@export var halo_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var halo_radius: float = 60.0
@export var aim_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var flap_fps: float = 6.0

enum State { IDLE, HOLDING, SPOTTING, AIMING, PLUNGING, LEAVING }
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
const _COUNTDOWN_SIZE := Vector2(40.0, 32.0)
## How far below the bird's centre the text line sits — clear of the HUD's
## top bar, which the bird itself overlaps
const _TEXT_LINE_DROP: float = 11.0
const _YUM_TEXT: String = "Yum!"
const _YUM_SIZE := Vector2(48.0, 16.0)
## From the bird's centre to the middle of the "Yum!"
const _YUM_DISTANCE: float = 46.0
## Spotting the urchin: a beat for the screen to be seen, the twinkle's
## flight, then its burst on the urchin
const _SPOT_DELAY: float = 0.35
const _SPOT_FLIGHT_SECONDS: float = 0.75
const _SPOT_BURST_SECONDS: float = 0.35
## The bird's eye, from the centre of its sprite (art facing right)
const _EYE_OFFSET := Vector2(13.0, -5.0)
## Centre of the halo, between the bird and the turtle
const _HALO_OFFSET := Vector2(0.0, -5.0)
const _HALO_FADE_SECONDS: float = 0.25
const _HALO_Z_INDEX: int = 14
## Room between a text box's edge and its text (sides, top / bottom)
const _TEXT_BOX_PADDING := Vector2(5.0, 2.0)
## Space between the power gauge and the countdown right of it
const _GAUGE_GAP: float = 4.0
## Space between the end of the urchin line and the bird's centre line
const _TARGET_TEXT_GAP: float = 30.0
const _TEXT_HEIGHT: float = 16.0
## Hint line: prefix, the button name (which blinks), suffix. Same blink as
## the alien tech key prompts on the HUD (tech_slot_ui.gd).
const _HINT_TEXT: Array[String] = ["Hold ", " to charge"]
const _HINT_BLINK_PERIOD_MSEC: float = 350.0
const _HINT_BLINK_COLOR := Color(0.65, 0.12, 1.0)
const _TARGET_TEXT: String = "Picky Puffin wants her sea urchin!"

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
var _halo: Sprite2D = null
var _yum_label: Label = null
## Which side of the bird the "Yum!" rides on (-1 left, 1 right)
var _yum_side: float = 1.0
## The urchin only glows once the bird's twinkle has landed on it
var _target_lit: bool = false
var _spot_time: float = 0.0
var _twinkle: Array[Polygon2D] = []
## The urchin the bird caught, on its way out of the level with it
var _carried_urchin: SeaUrchin = null
## The viewport-following layer over the HUD that the bird sprite lives on
var _bird_layer: CanvasLayer = null
## The bird sprite's place relative to this node (its position in the scene)
var _bird_offset: Vector2 = Vector2.ZERO

var _ui: CanvasLayer = null
var _countdown_label: Label = null
var _hint_button_label: Label = null

@onready var _bird: Sprite2D = $Bird

const SCENE_PATH: String = "res://entities/npcs/puffin/puffin_launcher.tscn"
const BIRD_TEXTURE = preload("res://entities/npcs/puffin/puffin.png")
const _SFX_LAUNCH = preload("res://assets/sounds/sfx/puffin launch.ogg")
const _SFX_GETS_URCHIN = preload("res://assets/sounds/sfx/puffin gets urchin.ogg")
## Frames side by side on BIRD_TEXTURE
const BIRD_FRAMES: int = 2

## Whether the level scene at `level_path` has a launcher placed in it — for
## the cut scene before it, which shows the bird heading off to make the
## catch. Reads the packed scene; nothing is instanced.
static func level_has_launcher(level_path: String) -> bool:
	if level_path.is_empty() or not ResourceLoader.exists(level_path):
		return false
	var packed := load(level_path) as PackedScene
	if packed == null:
		return false
	var state := packed.get_state()
	for i in state.get_node_count():
		var instance := state.get_node_instance(i)
		if instance and instance.resource_path == SCENE_PATH:
			return true
	return false

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
		push_warning("PuffinLauncher: no turtle to hold")
		return
	_state = State.HOLDING
	visible = true
	_lift_bird_above_hud()
	_build_halo()
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

## A soft white glow behind the bird and turtle until they plunge, so the pair
## stand out from whatever in the level happens to sit behind them.
func _build_halo() -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	fade.colors = PackedColorArray([Color(halo_color, halo_color.a), Color(halo_color, halo_color.a * 0.75), Color(halo_color, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = fade
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(halo_radius * 2.0)
	texture.height = int(halo_radius * 2.0)
	_halo = Sprite2D.new()
	_halo.texture = texture
	_halo.position = _HALO_OFFSET
	# Just under the turtle's sprite (absolute z 15), over the level around it
	_halo.z_as_relative = false
	_halo.z_index = _HALO_Z_INDEX
	add_child(_halo)

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
	_remaining = countdown_seconds
	_build_ui()
	_hide_hud_tech_names(true)
	if is_instance_valid(_target):
		_state = State.SPOTTING
		_spot_time = 0.0
		_build_twinkle()
	else:
		_start_aiming()

func _start_aiming() -> void:
	_state = State.AIMING
	_begin_msec = Time.get_ticks_msec()

# ---------------------------------------------------------------------------
# STATES
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_draw_time += delta
	match _state:
		State.HOLDING:
			_carry_turtle()
		State.SPOTTING:
			_carry_turtle()
			_spot_tick(delta)
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
	if _halo and _state >= State.PLUNGING:
		# Gone in a blink once they go
		_halo.modulate.a = maxf(0.0, _halo.modulate.a - delta / _HALO_FADE_SECONDS)
	_update_bird()
	_throb_target()
	queue_redraw()

## The bird spots its urchin: after a beat for the screen to be seen, a
## twinkle flies from its eye to the urchin, bursts there and lights it up.
## Then the countdown starts.
func _spot_tick(delta: float) -> void:
	_spot_time += delta
	var flight: float = clampf((_spot_time - _SPOT_DELAY) / _SPOT_FLIGHT_SECONDS, 0.0, 1.0)
	var burst: float = clampf((_spot_time - _SPOT_DELAY - _SPOT_FLIGHT_SECONDS) / _SPOT_BURST_SECONDS, 0.0, 1.0)
	if not is_instance_valid(_target) or burst >= 1.0:
		_target_lit = true
		for star in _twinkle:
			star.queue_free()
		_twinkle.clear()
		_start_aiming()
		return
	_target_lit = flight >= 1.0
	var eye: Vector2 = _bird.global_position + Vector2(_EYE_OFFSET.x * _facing, _EYE_OFFSET.y)
	for i in _twinkle.size():
		# Each star after the first trails a little behind it
		var t: float = clampf(flight - i * 0.08, 0.0, 1.0)
		var star: Polygon2D = _twinkle[i]
		star.visible = _spot_time >= _SPOT_DELAY and (i == 0 or burst <= 0.0)
		star.global_position = eye.lerp(_target.global_position, smoothstep(0.0, 1.0, t))
		star.rotation = _spot_time * 9.0
		star.scale = Vector2.ONE * ((1.0 - i * 0.25) * (1.0 + sin(_spot_time * 30.0) * 0.15) + burst * 2.5)
		star.modulate.a = (1.0 - i * 0.3) * (1.0 - burst)

## The twinkle: a four-pointed yellow star and two fainter ones trailing it,
## on the bird's layer so it starts over the HUD like the bird does.
func _build_twinkle() -> void:
	var points := PackedVector2Array()
	for i in 8:
		points.append(Vector2.from_angle(i * TAU / 8.0) * (7.0 if i % 2 == 0 else 2.0))
	for i in 3:
		var star := Polygon2D.new()
		star.polygon = points
		star.color = target_glow_color
		star.visible = false
		_bird_layer.add_child(star)
		_twinkle.append(star)

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
	# The button name blinks the way the HUD's alien tech key prompts do
	_hint_button_label.text = "A" if GameSettings.using_gamepad else "Z"
	var blink_on: bool = int(Time.get_ticks_msec() / _HINT_BLINK_PERIOD_MSEC) % 2 == 0
	_hint_button_label.add_theme_color_override("font_color", Color.WHITE if blink_on else _HINT_BLINK_COLOR)

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
	# A child of this node, so it plays while the level is still paused
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _SFX_LAUNCH
	sfx.finished.connect(sfx.queue_free)
	add_child(sfx)
	sfx.play()
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

## Takes the alien tech names off the HUD for the countdown and plunge (the
## text beside the bird sits over them), and brings them back when the level
## starts.
func _hide_hud_tech_names(hidden: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_tech_names_hidden"):
		hud.set_tech_names_hidden(hidden)

## The plunge has stopped: eat the urchin if it's in reach, hand the turtle
## back to the physics world and start the level.
func _finish() -> void:
	var ate: bool = is_instance_valid(_target) and global_position.distance_to(_target.global_position) <= eat_radius
	if is_instance_valid(_target) and _target.sprite:
		_target.sprite.scale = Vector2.ONE
	if ate:
		GameManager.record_puffin_skill_shot()
		# And a trash bag drifts in, a few seconds on so its sound doesn't
		# land on the catch sound. The timer calls the HUD directly (this node
		# is gone by then) and waits while the game is paused.
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("spawn_bonus_trash_cluster"):
			get_tree().create_timer(trash_bag_delay, false).timeout.connect(hud.spawn_bonus_trash_cluster)
		_eat(_target)
	_target = null

	if is_instance_valid(_turtle):
		_carry_turtle()
		_turtle.linear_velocity = _velocity
		_turtle.call("grant_grace_iframes", landing_grace_seconds)
	_turtle = null

	_hide_hud_tech_names(false)
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
	# On the level rather than this node, which frees itself once the bird has
	# flown off — the sound plays out regardless
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _SFX_GETS_URCHIN
	sfx.finished.connect(sfx.queue_free)
	get_parent().add_child(sfx)
	sfx.play()
	_carried_urchin = urchin
	# Onto the bird's layer, behind the bird, so the pair cross the HUD together
	if _bird_layer:
		urchin.reparent(_bird_layer)
		_bird_layer.move_child(urchin, 0)
	if urchin.sprite:
		urchin.sprite.position = Vector2.ZERO
	urchin.rotation = 0.0
	_show_yum()
	_eat_tween = create_tween()
	_eat_tween.tween_property(urchin, "global_position", global_position + _TURTLE_OFFSET, _EAT_SECONDS)

## "Yum!" beside the bird, on whichever side has more screen, riding out with
## it (placed every frame by _update_bird()).
func _show_yum() -> void:
	if _bird_layer == null:
		return
	_yum_label = Label.new()
	_yum_label.text = _YUM_TEXT
	_yum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_yum_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_yum_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_yum_label.size = _YUM_SIZE
	_yum_label.add_theme_font_size_override("font_size", 16)
	_yum_label.add_theme_color_override("font_color", target_glow_color)
	_yum_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_yum_label.add_theme_constant_override("outline_size", 4)
	_bird_layer.add_child(_yum_label)
	var on_screen_x: float = get_global_transform_with_canvas().origin.x
	_yum_side = -1.0 if on_screen_x > get_viewport_rect().size.x * 0.5 else 1.0

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
	if not _target_lit or _state == State.LEAVING or not is_instance_valid(_target) or _target.sprite == null:
		return
	_target.sprite.scale = Vector2.ONE * (1.0 + target_throb * _pulse())

func _pulse() -> float:
	return 0.5 + 0.5 * sin(_draw_time * 6.0)

func _update_bird() -> void:
	_bird.global_position = global_position + _bird_offset
	_bird.modulate.a = modulate.a
	_bird.flip_h = _facing < 0.0
	if _yum_label:
		_yum_label.position = _bird.global_position + Vector2(_yum_side * _YUM_DISTANCE, 0.0) - _YUM_SIZE * 0.5
		_yum_label.modulate.a = modulate.a
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
	# Everything on one line with the bird: the urchin text ending just left
	# of it, and right of the power gauge the countdown, a dash, then the
	# controls hint.
	var here: Vector2 = get_global_transform_with_canvas().origin
	var line_y: float = here.y + _bird_offset.y + _TEXT_LINE_DROP
	if is_instance_valid(_target):
		var target_box := _make_text_box()
		_ui.add_child(target_box)
		var target_label := _make_label(16)
		target_label.text = _TARGET_TEXT
		target_label.reparent(target_box)
		# Sized to its text, its right edge just short of the bird
		target_box.size = target_box.get_combined_minimum_size()
		target_box.position = Vector2(here.x - _TARGET_TEXT_GAP - target_box.size.x, line_y - target_box.size.y * 0.5)
	# Separate labels in a row, so only the button name blinks
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	row.position = Vector2(here.x + _POWER_METER.end.x + _GAUGE_GAP, line_y - _COUNTDOWN_SIZE.y * 0.5)
	row.size = Vector2(0.0, _COUNTDOWN_SIZE.y)
	_ui.add_child(row)
	_countdown_label = _make_label(32)
	_countdown_label.text = str(ceili(countdown_seconds))
	# Wide enough for "10", so the hint doesn't shift when it drops to one
	# digit; right-aligned so the number always sits the same distance from
	# the dash as the hint does
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown_label.custom_minimum_size = _COUNTDOWN_SIZE
	_countdown_label.reparent(row)
	var dash := _make_label(16)
	dash.text = " - "
	dash.reparent(row)
	# The hint in its own box (the countdown and dash stay bare), as separate
	# labels so only the button name blinks
	var hint_box := _make_text_box()
	hint_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint_box)
	var hint_row := HBoxContainer.new()
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_theme_constant_override("separation", 0)
	hint_box.add_child(hint_row)
	for text in [_HINT_TEXT[0], "A" if GameSettings.using_gamepad else "Z", _HINT_TEXT[1]]:
		var part := _make_label(16)
		part.text = text
		part.reparent(hint_row)
	_hint_button_label = hint_row.get_child(1) as Label

## A solid box behind a line of text, so it reads over the HUD beneath it.
func _make_text_box() -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = text_box_color
	style.content_margin_left = _TEXT_BOX_PADDING.x
	style.content_margin_right = _TEXT_BOX_PADDING.x
	style.content_margin_top = _TEXT_BOX_PADDING.y
	style.content_margin_bottom = _TEXT_BOX_PADDING.y
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", style)
	return box

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
	# The Picky Puffin's urchin
	if _target_lit and _state != State.LEAVING and is_instance_valid(_target):
		var at: Vector2 = to_local(_target.global_position)
		var pulse: float = _pulse()
		for i in 3:
			draw_circle(at, 9.0 + i * 4.0 + pulse * 3.0, Color(target_glow_color, 0.24 - i * 0.07))
		draw_arc(at, 13.0 + pulse * 4.0, 0.0, TAU, 24, Color(target_glow_color, 0.9), 1.0)
	if _state != State.AIMING:
		return
	_draw_power_meter()
	# Aim: blinking dots down the plunge line — drawn after the gauge, so they
	# stay visible when the aim swings across it
	var dir := _aim_direction()
	for i in 5:
		var blink: float = 0.45 + 0.55 * absf(sin(_draw_time * 6.0 - i * 0.9))
		draw_circle(_TURTLE_OFFSET + dir * (16.0 + i * 9.0), 2.0 - i * 0.25, Color(aim_color, blink))
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
