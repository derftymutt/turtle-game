extends Area2D
class_name PartyPuffin

## One puffin of the Puffin Party bonus (see PuffinParty, which builds and
## configures these in code). It flies in straight lines, bouncing off the
## edges of the party, catches the turtle on
## touch, carries it in its feet for a few seconds while the player aims, and
## launches it — after which it is "used" and flies off for good.
##
## Life cycle:
##   FLYING  — bouncing around the party; catches a free turtle on touch.
##   HOLDING — still moving, turtle pinned under it. The move stick aims, the
##             launch button fires, and the pie under it drains: at empty it
##             launches on its own. The turtle can shoot the whole time.
##   LEAVING — used: flies up and away, then frees itself.

enum State { FLYING, HOLDING, LEAVING }

const _TEXTURE = preload("res://entities/npcs/puffin/puffin.png")
const _FRAMES: int = 2
const _SFX_LAUNCH = preload("res://assets/sounds/sfx/puffin launch.ogg")
## The turtle hangs from the feet, this far under the puffin's centre
const TURTLE_OFFSET := Vector2(0.0, 22.0)
const _CATCH_RADIUS: float = 15.0
## Shaft length of the aim arrow — shorter than the level-start plunger's
const _ARROW_SHAFT: float = 18.0
## The pie sits under the turtle
const _PIE_OFFSET := Vector2(0.0, 42.0)
const _PIE_RADIUS: float = 7.0
const _LEAVE_SPEED := Vector2(80.0, -250.0)
const _LEAVE_SECONDS: float = 1.8
## Launch presses are ignored this soon after a catch (the button may still be
## down from the launch that got the turtle here)
const _LAUNCH_GRACE: float = 0.15
const _FLAP_FPS: float = 8.0
const _STICK_DEADZONE: float = 0.3
## Layer bit of the player's body (layer 6)
const _PLAYER_MASK: int = 32

var party: PuffinParty = null
var state: State = State.FLYING

## Pixels per second; reflected off the edges of the party
var velocity: Vector2 = Vector2.ZERO
## Launch direction, radians (starts straight up)
var _aim: float = -PI * 0.5
var _hold_left: float = 0.0
var _hold_time: float = 0.0
var _leave_time: float = 0.0
var _facing: float = 1.0
var _draw_time: float = 0.0
var _sprite: Sprite2D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = _PLAYER_MASK
	z_index = 70  # over the bags (60)
	_sprite = Sprite2D.new()
	_sprite.texture = _TEXTURE
	_sprite.hframes = _FRAMES
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _CATCH_RADIUS
	shape.shape = circle
	# A little low, so the catch is at the feet
	shape.position = Vector2(0.0, 8.0)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_draw_time = randf() * 10.0

func _physics_process(delta: float) -> void:
	match state:
		State.FLYING:
			_move(delta)
		State.HOLDING:
			_move(delta)
			_hold_tick(delta)
		State.LEAVING:
			_leave_time += delta
			global_position += Vector2(_LEAVE_SPEED.x * _facing, _LEAVE_SPEED.y) * delta
			modulate.a = clampf((_LEAVE_SECONDS - _leave_time) / 0.4, 0.0, 1.0)
			if _leave_time >= _LEAVE_SECONDS:
				queue_free()

func _process(delta: float) -> void:
	_draw_time += delta
	_sprite.flip_h = _facing < 0.0
	_sprite.frame = int(_draw_time * _FLAP_FPS * (2.0 if state == State.LEAVING else 1.0)) % _FRAMES
	queue_redraw()

# ---------------------------------------------------------------------------
# MOVEMENT
# ---------------------------------------------------------------------------

func _move(delta: float) -> void:
	var before: Vector2 = global_position
	var bounds: Rect2 = party.flight_bounds()
	global_position += velocity * delta
	if (global_position.x < bounds.position.x and velocity.x < 0.0) or (global_position.x > bounds.end.x and velocity.x > 0.0):
		velocity.x = -velocity.x
	if (global_position.y < bounds.position.y and velocity.y < 0.0) or (global_position.y > bounds.end.y and velocity.y > 0.0):
		velocity.y = -velocity.y
	var dx: float = global_position.x - before.x
	if absf(dx) > 0.2:
		_facing = signf(dx)

# ---------------------------------------------------------------------------
# CATCH, HOLD, LAUNCH
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if state == State.FLYING and party and body == party.turtle and party.turtle_is_loose():
		hold()

## Takes the turtle. Called on touch, and by the party for the puffin that
## starts with it.
func hold() -> void:
	state = State.HOLDING
	_hold_left = party.hold_seconds
	_hold_time = 0.0
	_aim = -PI * 0.5
	set_deferred("monitoring", false)
	party.on_puffin_caught(self)

func _hold_tick(delta: float) -> void:
	var turtle: RigidBody2D = party.turtle
	if not is_instance_valid(turtle):
		return
	turtle.global_position = global_position + TURTLE_OFFSET
	turtle.linear_velocity = Vector2.ZERO
	turtle.angular_velocity = 0.0
	# The move stick says where to point; the arrow swings round toward it at
	# a steady rate (so a tap is a nudge) and stays put when the stick is let go
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if stick.length() > _STICK_DEADZONE:
		var turn: float = angle_difference(_aim, stick.angle())
		var step: float = deg_to_rad(party.aim_turn_degrees) * delta
		_aim = wrapf(_aim + clampf(turn, -step, step), -PI, PI)
	_hold_time += delta
	_hold_left -= delta
	var pressed: bool = _hold_time >= _LAUNCH_GRACE and Input.is_action_just_pressed(party.launch_action)
	if pressed or _hold_left <= 0.0:
		launch()

## Fires the turtle along the aim. This puffin is now used: it flies off.
func launch() -> void:
	if state != State.HOLDING:
		return
	var direction := Vector2.from_angle(_aim)
	leave()
	party.on_puffin_launched(self, direction)
	var sfx := AudioStreamPlayer.new()
	sfx.stream = _SFX_LAUNCH
	sfx.finished.connect(sfx.queue_free)
	party.add_child(sfx)
	sfx.play()

## Flies off for good (used, or the party is over).
func leave() -> void:
	if state == State.LEAVING:
		return
	state = State.LEAVING
	_leave_time = 0.0
	set_deferred("monitoring", false)

# ---------------------------------------------------------------------------
# VISUALS
# ---------------------------------------------------------------------------

func _draw() -> void:
	if state != State.HOLDING:
		return
	var remaining: float = clampf(_hold_left / maxf(party.hold_seconds, 0.01), 0.0, 1.0)
	# Aim: the plunger's arrow, out from the turtle — always full and one
	# colour here, since every launch is the same speed (the pie is the timer)
	PuffinLauncher.draw_heat_arrow(self, TURTLE_OFFSET, _aim - PI * 0.5, 1.0, 0.0, _ARROW_SHAFT)
	# Pie timer (same look as the Academy's SwimPie): a full disc that drains
	# clockwise, gold to red
	draw_circle(_PIE_OFFSET, _PIE_RADIUS + 1.5, Color(0.0, 0.0, 0.0, 0.75))
	if remaining <= 0.0:
		return
	var color := Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.85, 0.2), remaining)
	if remaining >= 0.999:
		draw_circle(_PIE_OFFSET, _PIE_RADIUS, color)
		return
	var points := PackedVector2Array([_PIE_OFFSET])
	var steps: int = 24
	for i in steps + 1:
		var angle: float = -PI * 0.5 - TAU * remaining * float(i) / float(steps)
		points.append(_PIE_OFFSET + Vector2(cos(angle), sin(angle)) * _PIE_RADIUS)
	draw_colored_polygon(points, color)
