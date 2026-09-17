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
##   DROP_PAUSED    - paused lesson: parts are heavy, actually drop it with X —
##                    X both performs the drop and unpauses
##   MEANIES_DELAY  - beat, then...
##   MEANIES_PAUSED - paused lesson: shoot enemies — aim with the Right Stick
##   SHOOT_PAUSED   - paused lesson: test-fire the Right Stick as much as
##                    they want (like the flipper lesson) before A dismisses
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
	MEANIES_DELAY, MEANIES_PAUSED, SHOOT_PAUSED, FIGHT,
	TRASH_PAUSED, TRASH_WATCH,
	FINAL_PAUSED, DONE,
}

const PIRANHA_SCENE := preload("res://entities/enemies/piranha/piranha.tscn")
const TRASH_SEQUENCE_SCENE := preload("res://systems/trash_cleanup/trash_sequence.tscn")
const TRASH_CLUSTER_SCENE := preload("res://entities/collectibles/trash_cluster/trash_cluster.tscn")

const INTRO_TEXT := "You are Flip, UFO Repair Turtle.\n\nYour goal is to pick up UFO parts and bring them to your UFO Workshop.\n\nGive it a try!"
const INTRO_HINT := "\n▶  Swim with the Left Stick (or W A S D)"

## Reference copy of the wording — built as rich text in _show_energy_prompt()
## instead (same pattern as INTRO_TEXT/_show_intro()) so the icon/bar images
## can sit inline.
const ENERGY_TEXT := "Tired? Swimming uses energy, which is tracked by a small bar above you. [turtle+bar icon]\nA large version is at the top right [icon+bar]\n\nYou recover energy slowly when not swimming.\n\nBUT- you can recover it QUICKLY [sparkle] as well.\n\n\nGo to the surface. (larger font)\n\nYou will see the yellow sparkles [sparkle] of QUICK energy recovery."

## Reference copy — built from FlipperFastRow + FlipperBody in
## _show_flipper_prompt() instead, so the sparkle can land on "QUICKLY" here too.
const FLIPPER_TEXT := "You also recover energy QUICKLY [sparkle] while TOUCHING pinball walls and flippers. THIS IS KEY!!\n\nPlus, flippers are a great way to get around — life is much easier when you use them. Try launching yourself deep into the ocean to reach the UFO part.\n\nFlip with the LT / RT triggers (or Left Shift / Right Shift)."
const FLIPPER_HINT_LEFT := "\n▶  Try the LEFT flipper: LT (or Left Shift)"
const FLIPPER_HINT_RIGHT := "\n▶  Now the RIGHT flipper: RT (or Right Shift)"

const DROP_NOW_TEXT := "UFO parts are heavy. You can drop them if you need to with X (or Space).\n\nDrop the part now (and then go pick it up!)."
const DROP_NOW_HINT := "\n▶  Push X (or Space) to drop the part"

const MEANIES_TEXT := "Look out for meanies! You can shoot most of them with your turtle spit.\nAim with the Right Stick (or I J K L)."

const SHOOT_TEXT := "Try shooting turtle spit now."
const SHOOT_HINT := "\n▶  Use the Right Stick to shoot turtle spit in any direction"

const TRASH_TEXT := "You can also shoot trash you find floating by. Get it all and you'll get rewarded..."

const FINAL_TEXT := "You're ready!\nDeliver UFO parts to complete each level.\n\nOh yeah... just don't forget to breathe!"

const CONTINUE_HINT := "\n▶  Press A / Enter to continue"
const FINISH_HINT := "\n▶  Press A / Enter to finish"

const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
## Generous: the turtle bobs ~0-20px around the waterline while resting there.
const SURFACE_DEPTH := 24.0
## Fixed delay from the moment the turtle first reaches the surface to the
## flipper prompt interrupting them — runs regardless of what they do in the
## meantime (dive back down, swim off, whatever), rather than requiring them
## to stay put at the surface. A flat 1s gives them a moment to actually see
## the fast-recharge sparkle before being pulled into the next beat, while
## still short enough that a normal surface-and-dive can't slip past it.
const SURFACE_WATCH_SECONDS := 1.5
const DISMISS_ARM_DELAY := 0.45
## Energy fraction that counts as "into the red". A fraction rather than
## HUD.can_thrust() (energy < 15) because aggressive recovery means the hard
## floor is rarely reached in normal swimming.
const ENERGY_LOW_FRACTION := 0.22
## Same flat-delay idea as SURFACE_WATCH_SECONDS: once energy first dips into
## the red, wait this long before interrupting with the lesson, so the player
## actually feels being low on energy for a beat (sluggish, can't thrust much)
## instead of getting yanked into a menu the instant it happens.
const ENERGY_DEPLETED_WATCH_SECONDS := 2.0

## Same blinking-gold treatment as the alien tech selection / pause menu
## input hints, so a control prompt reads the same everywhere in the game.
const HINT_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const HINT_BLINK_PERIOD_MSEC: int = 300
const HINT_BLINK_LOW_ALPHA: float = 0.35

const PICKUP_DELAY_SECONDS := 3.0
## A little more breathing room than PICKUP_DELAY_SECONDS — this beat follows
## right on the heels of the drop lesson, so it gives the player a moment to
## actually go pick the part back up before the next pause interrupts them.
const MEANIES_DELAY_SECONDS := 3.0
const PIRANHA_COUNT := 4
## Safety caps so a stuck player never dead-ends the tutorial.
const FIGHT_SAFETY_SECONDS := 60.0
const TRASH_SAFETY_SECONDS := 34.0

@onready var _prompt: Panel = $Prompt
@onready var _message: Label = $Prompt/Margin/VBox/Message
@onready var _message_rich: RichTextLabel = $Prompt/Margin/VBox/MessageRich
@onready var _energy_fast_row:     HBoxContainer = $Prompt/Margin/VBox/EnergyFastRow
@onready var _energy_fast_word:    Label         = $Prompt/Margin/VBox/EnergyFastRow/Inner/WordRow/Word
@onready var _energy_sparkle_row:  HBoxContainer = $Prompt/Margin/VBox/EnergySparkleRow
@onready var _energy_sparkle_word: Label         = $Prompt/Margin/VBox/EnergySparkleRow/Inner/WordRow/Word
@onready var _flipper_fast_row:    HBoxContainer = $Prompt/Margin/VBox/FlipperFastRow
@onready var _flipper_fast_word:   Label         = $Prompt/Margin/VBox/FlipperFastRow/Word
@onready var _flipper_body:        Label         = $Prompt/Margin/VBox/FlipperBody
@onready var _hint: Label = $Prompt/Margin/VBox/Hint

# Inline icons for the intro prompt (first frame of each sprite sheet).
const PART_ICON := preload("res://entities/collectibles/ufo_piece/sprites/ufo_piece_grey.png")
const PART_ICON_REGION := Rect2(0, 0, 12, 12)
const WORKSHOP_ICON := preload("res://entities/environment/ufo_workshop/sprites/ufo_workshop2.png")
const WORKSHOP_ICON_REGION := Rect2(0, 0, 24, 24)

# Same assets the real HUD energy meter uses (see hud.tscn's EnergyContainer),
# so the energy lesson can show the player exactly what to look for. The fill
# texture already includes its own segment art, so dropping it in unclipped
# reads perfectly fine as "a full bar" without needing the bg layered under it.
const ENERGY_ICON := preload("res://ui/hud/sprites/energy_meter_icon.png")
const ENERGY_BAR_FILL := preload("res://ui/hud/sprites/energy_meter_fill.png")
const ENERGY_ICON_SIZE := Vector2i(18, 17)
const ENERGY_BAR_SIZE := Vector2i(175, 17)

## Static "turtle with its small floating energy bar" reference picture for
## the "A small bar directly above you" line — a plain composited PNG (the
## idle_s turtle frame + a mock of the bar TurtlePlayer itself draws above
## itself, see _setup_float_energy_bar() in turtle_player.gd) rather than a
## live scene, since a RichTextLabel inline image needs one flat texture.
const TURTLE_ENERGY_BAR_ICON := preload("res://ui/hud/sprites/energy_bar_turtle_icon.png")
const TURTLE_ENERGY_BAR_ICON_SIZE := Vector2i(24, 29)

var _step: int = Step.INTRO
var _hud: Node = null
var _turtle: Node2D = null
var _ocean: Node = null
var _pinball: Node2D = null
var _surface_time := 0.0
var _energy_depleted_time := 0.0
var _arm_timer := 0.0
var _dismiss_down_last := false
var _dismiss_held_at_pause := false

var _beat_timer := 0.0
var _fight_timer := 0.0
var _trash_timer := 0.0
var _flipped_left := false
var _flipped_right := false
var _shot_once := false
var _shoot_test_cooldown := 0.0
## Edge-detected by hand rather than Input.is_action_just_pressed(), which
## (per the note above) isn't reliable while the tree is paused.
var _drop_down_last := false
var _piranha: Array[Node] = []
var _trash_bag: Node = null
var _trash_seq: Node = null
var _sequence_done := false
var _prompt_tween: Tween
var _prompt_wanted := false

## The same "resting on a wall / at the surface" yellow sparkle TurtlePlayer
## shows for fast energy recovery (see _setup_rest_particles() there), reused
## here so specific words across the tutorial visibly wear it too. Keyed by
## an arbitrary id string since several can be on screen at once (the energy
## lesson alone has two) — see _get_or_make_sparkle()/_show_sparkle_on().
var _sparkles: Dictionary = {}


func _ready() -> void:
	_hint.add_theme_color_override("font_color", HINT_COLOR)
	_resolve_refs()
	if _pinball:
		_pinball.visible = false
		_pinball.modulate.a = 0.0
		_set_pinball_collisions(false)
	_show_intro()


func _process(delta: float) -> void:
	if _hint.visible:
		var blink_on := int(Time.get_ticks_msec() / HINT_BLINK_PERIOD_MSEC) % 2 == 0
		_hint.modulate.a = 1.0 if blink_on else HINT_BLINK_LOW_ALPHA

	if _hud == null or _turtle == null:
		_resolve_refs()
		return

	match _step:
		Step.INTRO:
			if _any_pressed(MOVE_ACTIONS):
				_hide_prompt()
				_step = Step.TO_ENERGY

		Step.TO_ENERGY:
			# Flat delay once energy first dips into the red (see
			# ENERGY_DEPLETED_WATCH_SECONDS) — same "keeps ticking regardless
			# of what they do next" idea as SURFACE_WATCH, so they get a beat
			# to actually feel low-energy swimming before the lesson interrupts.
			if _energy_depleted_time > 0.0 or _energy_depleted():
				_energy_depleted_time += delta
				if _energy_depleted_time >= ENERGY_DEPLETED_WATCH_SECONDS:
					_step = Step.ENERGY_PAUSED
					_pause_with_energy_prompt()

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
			# Flat countdown from the moment they touched the surface (see
			# SURFACE_WATCH_SECONDS) — keeps ticking no matter what they do
			# next, so diving straight back down can't dodge this beat the
			# way it used to.
			_surface_time += delta
			if _surface_time >= SURFACE_WATCH_SECONDS:
				_step = Step.FLIPPER_PAUSED
				_flipped_left = false
				_flipped_right = false
				_reveal_pinball()
				_pause_with_flipper_prompt()

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
					_drop_down_last = Input.is_action_pressed(&"drop_piece")
					_pause_with_prompt(DROP_NOW_TEXT, DROP_NOW_HINT)
				else:
					# No longer holding it (dropped or delivered) — skip the drop lesson.
					_beat_timer = MEANIES_DELAY_SECONDS
					_step = Step.MEANIES_DELAY

		Step.DROP_PAUSED:
			# X does double duty here: it performs the actual drop (so there's
			# really something to "go pick up again") and unpauses in the same
			# press, rather than a separate dismiss step. Hand-rolled edge
			# detection (see _drop_down_last) since is_action_just_pressed()
			# isn't reliable while paused.
			var drop_down := Input.is_action_pressed(&"drop_piece")
			if drop_down and not _drop_down_last:
				_perform_tutorial_drop()
				_unpause()
				_hide_prompt()
				_beat_timer = MEANIES_DELAY_SECONDS
				_step = Step.MEANIES_DELAY
			_drop_down_last = drop_down

		Step.MEANIES_DELAY:
			_beat_timer -= delta
			if _beat_timer <= 0.0:
				_step = Step.MEANIES_PAUSED
				_pause_with_prompt(MEANIES_TEXT, CONTINUE_HINT)

		Step.MEANIES_PAUSED:
			if _dismiss_ready(delta):
				_shot_once = false
				_shoot_test_cooldown = 0.0
				_step = Step.SHOOT_PAUSED
				_pause_with_prompt(SHOOT_TEXT, SHOOT_HINT)

		Step.SHOOT_PAUSED:
			# Stays paused the whole time — same idea as the flipper lesson:
			# test-fire freely (a real bullet, driven by tutorial_director so it
			# still flies while the rest of the world is frozen) and only once
			# they've actually fired does "A" become available to move on.
			_shoot_test_cooldown = maxf(0.0, _shoot_test_cooldown - delta)
			if _has_shoot_input() and _shoot_test_cooldown <= 0.0:
				var shoot_dir := Vector2(
					Input.get_axis("shoot_left", "shoot_right"),
					Input.get_axis("shoot_up", "shoot_down")
				).normalized()
				_tutorial_test_shoot(shoot_dir)
				_shoot_test_cooldown = 0.3
				if not _shot_once:
					_shot_once = true
					_set_hint(CONTINUE_HINT)
					_arm_timer = 0.25
			if _shot_once and _dismiss_ready(delta):
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
	# Slowed well below TrashSequence's own default (80px/s, tuned for normal
	# gameplay) — this is the tutorial, so a first-time player needs enough
	# time to actually track and shoot each item, not just watch it fly by.
	_trash_seq = TRASH_SEQUENCE_SCENE.instantiate()
	_trash_seq.spawn_side = "left"
	_trash_seq.drift_speed = 35.0
	scene.add_child(_trash_seq)
	_trash_seq.sequence_completed.connect(func(_pos): _sequence_done = true)
	_trash_seq.sequence_failed.connect(func(): _sequence_done = true)
	_trash_seq.trigger_sequence(TrashSequence.PatternType.WAVE, 4, Powerup.PowerupType.RANDOM)

	# A trash bag drifting in from the right — already fairly slow, nudged
	# down a bit further to match the sequence above.
	_trash_bag = TRASH_CLUSTER_SCENE.instantiate()
	_trash_bag.is_first_cluster = true
	_trash_bag.drift_speed = -35.0
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
	_arm_dismiss()


## Same as _pause_with_prompt(), but for the energy lesson's rich-text prompt
## (inline icon/bar images) instead of the plain-text one.
func _pause_with_energy_prompt() -> void:
	_show_energy_prompt()
	_arm_dismiss()


## Same idea, for the flipper lesson's sparkle-on-"FAST" prompt.
func _pause_with_flipper_prompt() -> void:
	_show_flipper_prompt()
	_arm_dismiss()


func _arm_dismiss() -> void:
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
	_message_rich.visible = false
	_hide_all_custom_prompt_nodes()
	_message.visible = true
	_message.text = text
	_hint.text = hint
	_hint.visible = hint != ""
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)


## The intro prompt, built as rich text so the UFO part and workshop icons can
## sit inline right after their names (like the how-to-play screen).
func _show_intro() -> void:
	_prompt_wanted = true
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_message.visible = false
	_hide_all_custom_prompt_nodes()
	_message_rich.visible = true
	_message_rich.clear()
	_message_rich.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_message_rich.append_text("You are Flip, UFO Repair Turtle.\n\nYour goal is to pick up UFO parts ")
	_message_rich.add_image(PART_ICON, 14, 14, Color.WHITE, INLINE_ALIGNMENT_CENTER, PART_ICON_REGION)
	_message_rich.append_text(" and bring them to your UFO Workshop ")
	_message_rich.add_image(WORKSHOP_ICON, 17, 17, Color.WHITE, INLINE_ALIGNMENT_CENTER, WORKSHOP_ICON_REGION)
	_message_rich.append_text(".\n\nGive it a try!")
	_message_rich.pop()
	_hint.text = INTRO_HINT
	_hint.visible = true
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)


## The energy lesson. Built partly as rich text (for the inline icon/bar
## images) and partly as dedicated rows of plain Labels for the two sparkle
## words ("QUICKLY", "yellow sparkles") — each needs to be its own node so the
## sparkle can be positioned exactly on top of it via get_global_rect(),
## which a substring inside a flowing RichTextLabel paragraph can't give us.
func _show_energy_prompt() -> void:
	_prompt_wanted = true
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_hide_all_custom_prompt_nodes()
	_message.visible = false
	_message_rich.visible = true
	_message_rich.clear()
	_message_rich.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_message_rich.append_text("Tired? Swimming uses energy ")
	_message_rich.add_image(ENERGY_ICON, ENERGY_ICON_SIZE.x, ENERGY_ICON_SIZE.y)
	_message_rich.append_text(", which is tracked by a small bar above you. ")
	_message_rich.add_image(TURTLE_ENERGY_BAR_ICON, TURTLE_ENERGY_BAR_ICON_SIZE.x, TURTLE_ENERGY_BAR_ICON_SIZE.y)
	_message_rich.append_text("\nA large version is at the top right ")
	_message_rich.add_image(ENERGY_ICON, ENERGY_ICON_SIZE.x, ENERGY_ICON_SIZE.y)
	_message_rich.add_image(ENERGY_BAR_FILL, ENERGY_BAR_SIZE.x, ENERGY_BAR_SIZE.y)
	_message_rich.pop()
	_energy_fast_row.visible = true
	_energy_sparkle_row.visible = true
	_hint.text = CONTINUE_HINT
	_hint.visible = true
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)
	_show_sparkle_on("energy_fast", _energy_fast_word)
	_show_sparkle_on("energy_sparkle_word", _energy_sparkle_word)


## The flipper lesson's opening line, split the same way so the sparkle can
## land on its "QUICKLY" too. The rest of FLIPPER_TEXT (no sparkle needed)
## continues in FlipperBody, its own plain autowrap Label.
func _show_flipper_prompt() -> void:
	_prompt_wanted = true
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_hide_all_custom_prompt_nodes()
	_message.visible = false
	_message_rich.visible = false
	_flipper_fast_row.visible = true
	_flipper_body.visible = true
	_hint.text = FLIPPER_HINT_LEFT
	_hint.visible = true
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)
	_show_sparkle_on("flipper_fast", _flipper_fast_word)


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
			_prompt.visible = false
			_hide_all_custom_prompt_nodes())
	# Stop spawning new sparkles right away — no need to wait for the fade,
	# and existing ones still fade out naturally over their own lifetime.
	_hide_all_sparkles()


func _hide_all_custom_prompt_nodes() -> void:
	_energy_fast_row.visible = false
	_energy_sparkle_row.visible = false
	_flipper_fast_row.visible = false
	_flipper_body.visible = false
	_hide_all_sparkles()


# ── Sparkle overlay (see _sparkles) ───────────────────────────────────────

## Same particle settings as TurtlePlayer._setup_rest_particles() (see
## turtle_player.gd) — same visual, just parented here and aimed at a UI
## label's screen position instead of following the turtle.
func _make_sparkle_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.9
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 50.0
	p.gravity = Vector2(0.0, -20.0)
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 35.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(1.0, 1.0, 0.1, 0.9)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.2, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 0.0, 0.0))
	p.color_ramp = gradient
	p.z_as_relative = false
	p.z_index = 20
	return p


func _get_or_make_sparkle(id: String) -> CPUParticles2D:
	if not _sparkles.has(id):
		var p := _make_sparkle_particles()
		p.name = "Sparkle_%s" % id
		add_child(p)
		_sparkles[id] = p
	return _sparkles[id]


## Waits a few frames so the just-shown label has actually been laid out
## (a single frame isn't always enough when several sibling rows change
## visibility in the same call — the container can need another pass or two
## before get_global_rect() is trustworthy), then centers that id's sparkle
## on it and starts emitting.
func _show_sparkle_on(id: String, label: Label) -> void:
	var p := _get_or_make_sparkle(id)
	for i in 3:
		await get_tree().process_frame
	if not is_instance_valid(label) or not label.visible:
		return
	p.global_position = label.get_global_rect().get_center()
	p.emitting = true


func _hide_all_sparkles() -> void:
	for p in _sparkles.values():
		p.emitting = false


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


## Mirrors the exact threshold TurtlePlayer itself checks before firing
## (see turtle_player.gd), so "has shot" here means a real bullet actually
## spawned, not just a stick nudge.
func _has_shoot_input() -> bool:
	var shoot_input := Vector2(
		Input.get_axis("shoot_left", "shoot_right"),
		Input.get_axis("shoot_up", "shoot_down")
	)
	return shoot_input.length() > 0.1


# ── Paused mini-lessons (drop / shoot) ────────────────────────────────────
#
# Both of these perform the real gameplay action directly from script rather
# than routing through TurtlePlayer's own _physics_process (which is frozen
# while the tree is paused) — same trick as _reveal_pinball()'s ALWAYS
# process_mode, applied per-instance instead of to a whole subtree.

## Drops every carried piece, mirroring TurtlePlayer's own drop_piece()
## handling exactly, so it behaves identically to a normal in-game drop — it
## just has to be triggered here since TurtlePlayer's input handling doesn't
## run while paused.
func _perform_tutorial_drop() -> void:
	if not GameManager.is_carrying_piece:
		return
	for piece in GameManager.carried_pieces.duplicate():
		if is_instance_valid(piece) and piece.has_method("drop_piece"):
			piece.drop_piece(true)
			# The real 2s "don't instantly re-pickup" grace period reads as a
			# bug here, since the very next instruction is "go pick it up
			# again" — shorten it for this one tutorial-triggered drop only,
			# leaving normal gameplay drops untouched.
			if "_drop_grace_timer" in piece:
				piece._drop_grace_timer = 0.3
	if _turtle:
		var sfx := _turtle.get_node_or_null("SfxUfoDrop")
		if sfx:
			sfx.play()


## Fires one real bullet (the same scene/speed TurtlePlayer's shoot() uses)
## so the flipper-style "test it while paused" lesson has something to
## actually show. A paused RigidBody2D doesn't reliably keep integrating its
## own physics even with process_mode = ALWAYS (it just sat there), so its
## flight is driven by hand with a tween owned by this ALWAYS-mode CanvasLayer
## instead — the same trick already used for the prompt fade in/out.
func _tutorial_test_shoot(direction: Vector2) -> void:
	if _turtle == null:
		return
	var scene: PackedScene = _turtle.get("bullet_scene")
	var parent := _turtle.get_parent()
	if scene == null or parent == null:
		return
	var bullet := scene.instantiate()
	bullet.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(bullet)
	var start_pos: Vector2 = _turtle.global_position + direction * 20.0
	bullet.global_position = start_pos
	bullet.rotation = direction.angle()
	if "freeze" in bullet:
		bullet.freeze = true  # position is driven by the tween below, not physics
	var speed: float = _turtle.get("bullet_speed")
	var travel_time := 0.5
	var tw := create_tween()
	tw.tween_property(bullet, "global_position", start_pos + direction * speed * travel_time, travel_time)
	var sfx := _turtle.get_node_or_null("SfxShoot")
	if sfx:
		sfx.play()
