# tutorial_director.gd
extends CanvasLayer

## Scripted tutorial sequence. Lives on a process_mode = ALWAYS CanvasLayer so
## its prompts and dismiss-input keep working while the rest of the scene is
## paused for a lesson.
##
## Beats:
##   INTRO          - goal text, dismissed by moving
##   TO_ENERGY      - wait until the player first runs low on energy
##   ENERGY_PAUSED  - paused lesson: energy bars + surface recovery
##   TO_SURFACE / SURFACE_WATCH - reach the surface, see the fast-recharge sparkle
##   FLIPPER_PAUSED - paused lesson: reveals the pinball field, then makes the
##                    player work the left and right flippers before A dismisses
##   TO_PICKUP      - wait until the player is carrying a UFO part
##   PICKUP_DELAY   - beat, then...
##   DROP_PAUSED    - paused lesson: parts are heavy, you can drop them
##   MEANIES_DELAY  - beat, then...
##   MEANIES_PAUSED - paused lesson: shoot enemies; spawns 4 piranha on dismiss
##   FIGHT          - wait until the piranha are dead or the part is delivered
##   TRASH_PAUSED   - paused lesson: shoot trash for a reward; spawns trash on dismiss
##   TRASH_WATCH    - wait until the trash is cleared or has drifted off
##   FINAL_PAUSED   - "you're ready" — dismiss returns to the title screen
##
## Note: while the SceneTree is paused, Input.is_action_just_pressed() and
## _input() do not fire reliably, but Input.is_action_pressed() (level state)
## does. So dismiss detection polls the level state and finds the edge itself.

enum Step {
	INTRO,
	TO_ENERGY, ENERGY_PAUSED,
	TO_SURFACE, SURFACE_WATCH, FLIPPER_PAUSED,
	TO_PICKUP, PICKUP_DELAY, DROP_PAUSED,
	MEANIES_DELAY, MEANIES_PAUSED, FIGHT,
	TRASH_PAUSED, TRASH_WATCH,
	FINAL_PAUSED, DONE,
}

const PIRANHA_SCENE := preload("res://entities/enemies/piranha/piranha.tscn")
const TRASH_SEQUENCE_SCENE := preload("res://systems/trash_cleanup/trash_sequence.tscn")
const TRASH_CLUSTER_SCENE := preload("res://entities/collectibles/trash_cluster/trash_cluster.tscn")

const INTRO_TEXT := "You are Flip, UFO Repair Turtle. Your goal is to pick up UFO parts from the ocean floor and bring them to your UFO Workshop. Give it a try!"
const INTRO_HINT := "▶  Move with the Left Stick   (or W A S D)"

const ENERGY_TEXT := "Swimming uses energy. Energy is shown as a bar above the turtle, with a larger version at the top-right of the screen.\n\nYou recover energy by not swimming — and MUCH faster at the surface.\n\nGo to the surface and watch for the yellow sparkle around you. That shows when you are recovering energy fast."

const FLIPPER_TEXT := "You also recover energy FAST while TOUCHING pinball walls and flippers.\n\nFlippers are a great way to get around — you won't get far without them! Try launching yourself deep into the ocean to reach a UFO part.\n\nFlip with the  L2 / R2  triggers   (or Left Shift / Right Shift)."
const FLIPPER_HINT_LEFT := "▶  Try the LEFT flipper:  L2   (or Left Shift)"
const FLIPPER_HINT_RIGHT := "▶  Now the RIGHT flipper:  R2   (or Right Shift)"

const DROP_TEXT := "UFO parts are heavy to carry. You can drop the one you're holding with  X   (or Space)."

const MEANIES_TEXT := "Look out for meanies! You can shoot most of them with your turtle spit — aim with the Right Stick   (or  I J K L)."

const TRASH_TEXT := "You can also shoot trash you find floating by. Get it all and you'll get rewarded..."

const FINAL_TEXT := "You're ready!\n\nDeliver UFO parts to complete each level.\n\nOh yeah... just don't forget to breathe!"

const CONTINUE_HINT := "▶  Press  A  to continue"
const FINISH_HINT := "▶  Press  A  to finish"

const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
## Generous: the turtle bobs ~0-20px around the waterline while resting there.
const SURFACE_DEPTH := 24.0
const SURFACE_WATCH_SECONDS := 1.6
const DISMISS_ARM_DELAY := 0.45
## Energy fraction that counts as "into the red". A fraction rather than
## HUD.can_thrust() (energy < 15) because aggressive recovery means the hard
## floor is rarely reached in normal swimming.
const ENERGY_LOW_FRACTION := 0.22

const PICKUP_DELAY_SECONDS := 3.0
const MEANIES_DELAY_SECONDS := 1.5
const PIRANHA_COUNT := 4
## Safety caps so a stuck player never dead-ends the tutorial.
const FIGHT_SAFETY_SECONDS := 60.0
const TRASH_SAFETY_SECONDS := 34.0

@onready var _prompt: Panel = $Prompt
@onready var _message: Label = $Prompt/Margin/VBox/Message
@onready var _hint: Label = $Prompt/Margin/VBox/Hint

var _step: int = Step.INTRO
var _hud: Node = null
var _turtle: Node2D = null
var _ocean: Node = null
var _pinball: Node2D = null
var _surface_time := 0.0
var _arm_timer := 0.0
var _dismiss_down_last := false
var _dismiss_held_at_pause := false

var _beat_timer := 0.0
var _fight_timer := 0.0
var _trash_timer := 0.0
var _flipped_left := false
var _flipped_right := false
var _piranha: Array[Node] = []
var _trash_bag: Node = null
var _trash_seq: Node = null
var _sequence_done := false
var _prompt_tween: Tween
var _prompt_wanted := false


func _ready() -> void:
	_resolve_refs()
	if _pinball:
		_pinball.visible = false
		_pinball.modulate.a = 0.0
		_set_pinball_collisions(false)
	_show_prompt(INTRO_TEXT, INTRO_HINT)


func _process(delta: float) -> void:
	if _hud == null or _turtle == null:
		_resolve_refs()
		return

	match _step:
		Step.INTRO:
			if _any_pressed(MOVE_ACTIONS):
				_hide_prompt()
				_step = Step.TO_ENERGY

		Step.TO_ENERGY:
			if _energy_depleted():
				_step = Step.ENERGY_PAUSED
				_pause_with_prompt(ENERGY_TEXT, CONTINUE_HINT)

		Step.ENERGY_PAUSED:
			if _dismiss_ready(delta):
				_unpause()
				_hide_prompt()
				_step = Step.TO_SURFACE

		Step.TO_SURFACE:
			if _depth() <= SURFACE_DEPTH:
				_surface_time = 0.0
				_step = Step.SURFACE_WATCH

		Step.SURFACE_WATCH:
			# Accumulate time near the surface; a brief bob below the threshold
			# nibbles the timer back rather than resetting it.
			if _depth() <= SURFACE_DEPTH:
				_surface_time += delta
			else:
				_surface_time = maxf(0.0, _surface_time - delta * 2.0)
			if _surface_time >= SURFACE_WATCH_SECONDS:
				_step = Step.FLIPPER_PAUSED
				_flipped_left = false
				_flipped_right = false
				_reveal_pinball()
				_pause_with_prompt(FLIPPER_TEXT, FLIPPER_HINT_LEFT)

		Step.FLIPPER_PAUSED:
			# Make them work each flipper (and watch it move) before "A" unlocks.
			if not _flipped_left:
				if Input.is_action_pressed(&"flipper_left"):
					_flipped_left = true
					_set_hint(FLIPPER_HINT_RIGHT)
			elif not _flipped_right:
				if Input.is_action_pressed(&"flipper_right"):
					_flipped_right = true
					_set_hint(CONTINUE_HINT)
					_arm_timer = 0.25
			elif _dismiss_ready(delta):
				_unpause()
				_hide_prompt()
				_step = Step.TO_PICKUP

		Step.TO_PICKUP:
			if _is_carrying():
				_beat_timer = PICKUP_DELAY_SECONDS
				_step = Step.PICKUP_DELAY
			elif _piece_delivered():
				# Delivered without pausing to hold it — the "drop" lesson is moot.
				_beat_timer = MEANIES_DELAY_SECONDS
				_step = Step.MEANIES_DELAY

		Step.PICKUP_DELAY:
			_beat_timer -= delta
			if _beat_timer <= 0.0:
				if _is_carrying():
					_step = Step.DROP_PAUSED
					_pause_with_prompt(DROP_TEXT, CONTINUE_HINT)
				else:
					# No longer holding it (dropped or delivered) — skip the drop lesson.
					_beat_timer = MEANIES_DELAY_SECONDS
					_step = Step.MEANIES_DELAY

		Step.DROP_PAUSED:
			if _dismiss_ready(delta):
				_unpause()
				_hide_prompt()
				_beat_timer = MEANIES_DELAY_SECONDS
				_step = Step.MEANIES_DELAY

		Step.MEANIES_DELAY:
			_beat_timer -= delta
			if _beat_timer <= 0.0:
				_step = Step.MEANIES_PAUSED
				_pause_with_prompt(MEANIES_TEXT, CONTINUE_HINT)

		Step.MEANIES_PAUSED:
			if _dismiss_ready(delta):
				_unpause()
				_hide_prompt()
				_spawn_piranha(PIRANHA_COUNT)
				_fight_timer = FIGHT_SAFETY_SECONDS
				_step = Step.FIGHT

		Step.FIGHT:
			_fight_timer -= delta
			# Any survivors stay in the water — the meanies don't just vanish.
			if _all_piranha_dead() or _piece_delivered() or _fight_timer <= 0.0:
				_step = Step.TRASH_PAUSED
				_pause_with_prompt(TRASH_TEXT, CONTINUE_HINT)

		Step.TRASH_PAUSED:
			if _dismiss_ready(delta):
				_unpause()
				_hide_prompt()
				_spawn_trash()
				_trash_timer = TRASH_SAFETY_SECONDS
				_step = Step.TRASH_WATCH

		Step.TRASH_WATCH:
			_trash_timer -= delta
			if _trash_all_gone() or _trash_timer <= 0.0:
				_step = Step.FINAL_PAUSED
				_pause_with_prompt(FINAL_TEXT, FINISH_HINT)

		Step.FINAL_PAUSED:
			if _dismiss_ready(delta):
				_unpause()
				_step = Step.DONE
				GameManager.load_main_menu()

		Step.DONE:
			set_process(false)


func _resolve_refs() -> void:
	_hud = get_tree().get_first_node_in_group("hud")
	_turtle = get_tree().get_first_node_in_group("player")
	_ocean = get_tree().get_first_node_in_group("ocean")
	if _pinball == null:
		_pinball = get_node_or_null("../PinballElements")


func _energy_depleted() -> bool:
	if _hud == null or not bool(_hud.get("energy_enabled")):
		return false
	var cur: Variant = _hud.get("current_energy")
	var maxv: Variant = _hud.get("max_energy")
	if cur == null or maxv == null or float(maxv) <= 0.0:
		return false
	return float(cur) <= float(maxv) * ENERGY_LOW_FRACTION


func _depth() -> float:
	if _turtle == null:
		return 9999.0
	if _ocean and _ocean.has_method("get_depth"):
		return _ocean.get_depth(_turtle.global_position)
	var surface_y := -126.0
	var sy: Variant = _ocean.get("surface_y") if _ocean else null
	if sy != null:
		surface_y = float(sy)
	return _turtle.global_position.y - surface_y


func _is_carrying() -> bool:
	return bool(GameManager.is_carrying_piece)


func _piece_delivered() -> bool:
	return int(LevelManager.pieces_collected) >= 1


# ── Enemy / trash spawning ───────────────────────────────────────────────

func _spawn_piranha(count: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var spots := [Vector2(-120, -30), Vector2(120, -30), Vector2(-120, 45), Vector2(120, 45)]
	for i in count:
		var p := PIRANHA_SCENE.instantiate()
		scene.add_child(p)
		p.global_position = spots[i % spots.size()]
		_piranha.append(p)


func _all_piranha_dead() -> bool:
	for p in _piranha:
		if is_instance_valid(p):
			return false
	return true


func _spawn_trash() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_sequence_done = false

	# A drifting line of trash items sweeping in from the left (rewards a powerup).
	_trash_seq = TRASH_SEQUENCE_SCENE.instantiate()
	_trash_seq.spawn_side = "left"
	scene.add_child(_trash_seq)
	_trash_seq.sequence_completed.connect(func(_pos): _sequence_done = true)
	_trash_seq.sequence_failed.connect(func(): _sequence_done = true)
	_trash_seq.trigger_sequence(TrashSequence.PatternType.WAVE, 4, Powerup.PowerupType.RANDOM)

	# A trash bag drifting in from the right.
	_trash_bag = TRASH_CLUSTER_SCENE.instantiate()
	_trash_bag.is_first_cluster = true
	_trash_bag.drift_speed = -42.0
	if _ocean:
		_trash_bag.min_y = float(_ocean.surface_y) + 12.0
	_trash_bag.max_y = 150.0
	scene.add_child(_trash_bag)
	_trash_bag.global_position = Vector2(330.0, 8.0)


## The trash beat ends on EITHER trigger: everything shot, or everything drifted
## off screen. So an item/bag counts as "gone" if it's freed OR off screen.
func _trash_all_gone() -> bool:
	# Wait until the sequence has actually finished spawning its items, so a
	# not-yet-spawned line isn't mistaken for a cleared one.
	var spawned_all := _sequence_done
	if is_instance_valid(_trash_seq):
		spawned_all = spawned_all or (int(_trash_seq.items_spawned) >= int(_trash_seq.items_in_sequence))
	if not spawned_all:
		return false

	if is_instance_valid(_trash_bag) and _trash_bag is Node2D and not _offscreen(_trash_bag):
		return false
	for item in get_tree().get_nodes_in_group("trash_items"):
		if is_instance_valid(item) and item is Node2D and not _offscreen(item):
			return false
	return true


## True when a node has drifted well outside the fixed 640x360 view.
func _offscreen(node: Node2D) -> bool:
	var p := node.global_position
	return absf(p.x) > 360.0 or p.y < -220.0 or p.y > 240.0


# ── Prompt + pause ───────────────────────────────────────────────────────

## Show the prompt and pause. The dismiss input (the A key, or the gamepad A /
## Enter) is ignored for the first DISMISS_ARM_DELAY seconds — ticked down in
## _process, which keeps running while paused — so the press that reached this
## beat can't skip it. A dedicated key rather than "any movement" so the player
## doesn't dismiss a lesson by accident while swimming.
func _pause_with_prompt(text: String, hint: String) -> void:
	_show_prompt(text, hint)
	_arm_timer = DISMISS_ARM_DELAY
	_dismiss_down_last = _dismiss_input_down()
	_dismiss_held_at_pause = _dismiss_down_last
	get_tree().paused = true


## True once the player has acknowledged a paused prompt: a fresh press of the
## dismiss key, or releasing it if it was already held when the pause began
## (e.g. they were swimming left, which is the A key).
func _dismiss_ready(delta: float) -> bool:
	var down := _dismiss_input_down()
	if _arm_timer > 0.0:
		_arm_timer -= delta
		_dismiss_down_last = down
		_dismiss_held_at_pause = _dismiss_held_at_pause and down
		return false
	if down and not _dismiss_down_last:
		_dismiss_down_last = down
		return true
	if _dismiss_held_at_pause and not down:
		return true
	_dismiss_down_last = down
	return false


func _dismiss_input_down() -> bool:
	return Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_accept")


func _unpause() -> void:
	get_tree().paused = false


func _show_prompt(text: String, hint: String = "") -> void:
	_prompt_wanted = true
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_message.text = text
	_hint.text = hint
	_hint.visible = hint != ""
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)


func _hide_prompt() -> void:
	_prompt_wanted = false
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 0.0, 0.25)
	# Guard against a re-show that lands mid-fade: only actually hide if nobody
	# has asked for the prompt again in the meantime.
	_prompt_tween.tween_callback(func() -> void:
		if not _prompt_wanted:
			_prompt.visible = false)


## Swap just the hint line without re-fading the whole prompt.
func _set_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""


# ── Pinball reveal ───────────────────────────────────────────────────────

func _reveal_pinball() -> void:
	if _pinball == null:
		return
	_set_pinball_collisions(true)
	# Keep processing while the tree is paused so the flippers still respond to
	# input during the paused flipper lesson (and the player can see them move).
	_pinball.process_mode = Node.PROCESS_MODE_ALWAYS
	_pinball.visible = true
	_pinball.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_pinball, "modulate:a", 1.0, 0.6)


func _set_pinball_collisions(enabled: bool) -> void:
	if _pinball:
		_walk_shapes(_pinball, enabled)


func _walk_shapes(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)
		_walk_shapes(child, enabled)


# ── Input helpers ────────────────────────────────────────────────────────

func _any_pressed(actions: Array[StringName]) -> bool:
	for a in actions:
		if Input.is_action_pressed(a):
			return true
	return false
