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
##                    player work the left and right flippers, then tells them
##                    to launch themselves down to the part, before A dismisses
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
##
## Typewriter: every prompt types its text out a letter at a time (see
## _tick_typing()). A prompt is a list of pages (_pages) — each a Callable that
## lays out that page's labels and returns them in typing order. Long lessons
## (energy, flippers) are split into several pages; the dismiss key (A / Space)
## first finishes the text that's still typing, then turns to the next page,
## and only dismisses the lesson once the final page is fully shown (see
## _tick_prompt()).

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
const INTRO_HINT := "Swim with the Left Stick (or W A S D)"

## Reference copy of the wording — built as rich text in _show_energy_prompt()
## instead (same pattern as INTRO_TEXT/_show_intro()) so the icon/bar images
## can sit inline.
const ENERGY_TEXT := "Tired? Swimming uses energy, which is tracked by a small bar above you. [turtle+bar icon]\nA large version is at the top right [icon+bar]\n\nYou recover energy slowly when not swimming.\n\nBUT- you can recover it QUICKLY [sparkle] as well.\n\n\nGo to the surface. (larger font)\n\nYou will see (and hear) the yellow sparkles [sparkle] of QUICK energy recovery."

## Reference copy — built from FlipperFastRow + FlipperBody in
## _show_flipper_prompt() instead, so the sparkle can land on "QUICKLY" here too.
const FLIPPER_TEXT := "You also recover energy QUICKLY [sparkle] while TOUCHING pinball walls and flippers. THIS IS KEY!!\n\nPlus, flippers are a great way to get around — life is much easier when you use them.\n\nYou flip flippers with the LT / RT triggers (or Left Shift / Right Shift).\n\n[after trying both flippers:] Now try launching yourself deep into the ocean with the flippers to reach the UFO part."
## The same wording as FLIPPER_TEXT, one entry per page — FlipperBody is
## retyped for each. Page 0 also shows FlipperFastRow's "You also recover
## energy QUICKLY" as its opening line, so its entry picks up mid-sentence.
const FLIPPER_BODY_PAGES: Array[String] = [
	"while TOUCHING pinball walls and flippers. THIS IS KEY!!",
	"Plus, flippers are a great way to get around — life is much easier when you use them.",
	"You flip flippers with the LT / RT triggers (or Left Shift / Right Shift).",
]
## Not one of the pages above: it's only typed once the player has actually
## worked both flippers (see Step.FLIPPER_PAUSED and _show_flipper_launch_page()).
const FLIPPER_LAUNCH_TEXT := "Now try launching yourself deep into the ocean with the flippers to reach the UFO part."
const FLIPPER_HINT_LEFT := "Try the LEFT flipper: LT (or Left Shift)"
const FLIPPER_HINT_RIGHT := "Now the RIGHT flipper: RT (or Right Shift)"
## GameSettings.mouse_mode variants of the lines above/below that name keys.
const FLIPPER_HOWTO_MOUSE := "You flip flippers with the LT / RT triggers (or the Left / Right mouse buttons)."
const FLIPPER_HINT_LEFT_MOUSE := "Try the LEFT flipper: LT (or Left Click)"
const FLIPPER_HINT_RIGHT_MOUSE := "Now the RIGHT flipper: RT (or Right Click)"

## %s = GameSettings.drop_key_label()
const DROP_NOW_TEXT := "UFO parts are heavy. You can drop them if you need to with X (or %s).\n\nDrop the part now (and then go pick it up!)."
const DROP_NOW_HINT := "Push X (or %s) to drop the part"

const MEANIES_TEXT := "Look out for meanies! You can shoot most of them with your turtle spit.\nAim with the Right Stick (or I J K L)."

const SHOOT_TEXT := "Try shooting turtle spit now."
const SHOOT_HINT := "Use the Right Stick to shoot turtle spit in any direction"
const MEANIES_TEXT_MOUSE := "Look out for meanies! You can shoot most of them with your turtle spit.\nAim with the Right Stick (or the mouse - it spits on its own. Tab turns it off and on)."
const SHOOT_HINT_MOUSE := "Use the Right Stick (or point the mouse) to spit in any direction"

const TRASH_TEXT := "You can also shoot trash you find floating by. Get it all and you'll get rewarded..."

const FINAL_TEXT := "You're ready!\nDeliver UFO parts to complete each level.\n\nOh yeah... just don't forget to breathe!"

const CONTINUE_HINT := "Press A / Space to continue"
const FINISH_HINT := "Press A / Space to finish"

## Typewriter pacing. Layout is fixed up front (see _configure_typed_labels()),
## so a slower/faster speed never reflows the text — only how quickly it appears.
const TYPE_CHARS_PER_SECOND := 50.0
## Extra beats after punctuation so sentences land instead of streaming past.
const TYPE_SENTENCE_PAUSE := 0.25
const TYPE_CLAUSE_PAUSE := 0.12
## Held back at the start of every page — covers the prompt's fade-in and gives
## a page turn a small "new text is coming" beat.
const TYPE_START_DELAY := 0.25
## The intro is dismissed by swimming, which the player is likely already doing
## as it types. Movement only counts this long after the text has finished, so
## they get a moment with the full goal on screen.
const INTRO_LINGER_SECONDS := 0.8

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
@onready var _energy_fast_before:  Label         = $Prompt/Margin/VBox/EnergyFastRow/Inner/Before
@onready var _energy_fast_lead:    Label         = $Prompt/Margin/VBox/EnergyFastRow/Inner/WordRow/Lead
@onready var _energy_fast_word:    Label         = $Prompt/Margin/VBox/EnergyFastRow/Inner/WordRow/Word
@onready var _energy_fast_after:   Label         = $Prompt/Margin/VBox/EnergyFastRow/Inner/WordRow/After
@onready var _energy_sparkle_row:  HBoxContainer = $Prompt/Margin/VBox/EnergySparkleRow
@onready var _energy_sparkle_before: Label       = $Prompt/Margin/VBox/EnergySparkleRow/Inner/Before
@onready var _energy_sparkle_lead: Label         = $Prompt/Margin/VBox/EnergySparkleRow/Inner/WordRow/Lead
@onready var _energy_sparkle_word: Label         = $Prompt/Margin/VBox/EnergySparkleRow/Inner/WordRow/Word
@onready var _energy_sparkle_after: Label        = $Prompt/Margin/VBox/EnergySparkleRow/Inner/WordRow/After
@onready var _flipper_fast_row:    HBoxContainer = $Prompt/Margin/VBox/FlipperFastRow
@onready var _flipper_fast_before: Label         = $Prompt/Margin/VBox/FlipperFastRow/Before
@onready var _flipper_fast_word:   Label         = $Prompt/Margin/VBox/FlipperFastRow/Word
@onready var _flipper_body:        Label         = $Prompt/Margin/VBox/FlipperBody
@onready var _hint: Label = $Prompt/Margin/VBox/HintRow/Hint
## The turtle-icon+text row as a whole — blinked together (see _process()) so
## the icon reads as part of the same "this line is actionable" prompt
## instead of just sitting there while the text pulses on its own.
@onready var _hint_row: HBoxContainer = $Prompt/Margin/VBox/HintRow

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
## False until the shooting lesson — see _resolve_refs().
var _auto_fire_unlocked: bool = false
var _ocean: Node = null
var _pinball: Node2D = null
var _surface_time := 0.0
var _energy_depleted_time := 0.0
var _arm_timer := 0.0
var _dismiss_down_last := false
## True while a paused lesson is waiting on the dismiss key (set by
## _arm_dismiss(), cleared by _unpause()). The intro isn't one — it's cleared
## by swimming, not a key press.
var _dismiss_active := false
## Set by _tick_prompt() on the frame the dismiss key is pressed with nothing
## left to skip or turn — i.e. the press that should actually end the lesson.
var _dismiss_pressed := false

# Typewriter / paging state (see the header note, _show_pages() and _tick_typing()).
var _pages: Array = []                ## Callables, one per page; each returns its labels in typing order
var _page_index := 0
var _final_hint := ""                 ## Hint shown once the LAST page is fully typed; earlier pages show CONTINUE_HINT
var _typing := false
var _type_nodes: Array = []           ## Label / RichTextLabel nodes on the current page, in typing order
var _type_node_i := 0
var _type_text := ""
var _type_pos := 0
var _type_budget := 0.0               ## Seconds banked toward the next letter (starts negative — see TYPE_START_DELAY)
var _type_cost := 0.0                 ## Seconds the next letter costs
var _type_sparkles: Dictionary = {}   ## Label -> sparkle id, started the moment that label finishes typing
var _intro_linger := 0.0

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
	_configure_typed_labels(_prompt)
	_resolve_refs()
	if _pinball:
		_pinball.visible = false
		_pinball.modulate.a = 0.0
		_set_pinball_collisions(false)
	_show_intro()


func _process(delta: float) -> void:
	# Ahead of the _hud/_turtle guard below: the intro types out before those exist.
	_tick_prompt(delta)

	if _hint_row.visible:
		# Kept in the layout but invisible while typing (rather than hidden) so
		# the text block doesn't jump when the hint appears afterwards.
		var blink_on := int(Time.get_ticks_msec() / HINT_BLINK_PERIOD_MSEC) % 2 == 0
		_hint_row.modulate.a = 0.0 if _typing else (1.0 if blink_on else HINT_BLINK_LOW_ALPHA)

	if _hud == null or _turtle == null:
		_resolve_refs()
		return

	match _step:
		Step.INTRO:
			if _typing:
				_intro_linger = INTRO_LINGER_SECONDS
			else:
				_intro_linger -= delta
				if _intro_linger <= 0.0 and _any_pressed(MOVE_ACTIONS):
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
			if _dismiss_ready():
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
			if not _text_complete():
				pass  # still reading — A skips/turns pages (see _tick_prompt()); flippers don't count yet
			elif not _flipped_left:
				if Input.is_action_pressed(&"flipper_left"):
					_flipped_left = true
					_set_hint(FLIPPER_HINT_RIGHT_MOUSE if GameSettings.mouse_mode else FLIPPER_HINT_RIGHT)
			elif not _flipped_right:
				if Input.is_action_pressed(&"flipper_right"):
					_flipped_right = true
					_show_flipper_launch_page()
					_arm_timer = 0.25
			elif _dismiss_ready():
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
					_pause_with_prompt(DROP_NOW_TEXT % GameSettings.drop_key_label(), DROP_NOW_HINT % GameSettings.drop_key_label())
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
			# Not until the text has finished typing, so the drop can't
			# unpause the lesson before they've read it.
			if drop_down and not _drop_down_last and _text_complete():
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
				_pause_with_prompt(MEANIES_TEXT_MOUSE if GameSettings.mouse_mode else MEANIES_TEXT, CONTINUE_HINT)

		Step.MEANIES_PAUSED:
			if _dismiss_ready():
				_shot_once = false
				_shoot_test_cooldown = 0.0
				_step = Step.SHOOT_PAUSED
				_unlock_auto_fire()
				_pause_with_prompt(SHOOT_TEXT, SHOOT_HINT_MOUSE if GameSettings.mouse_mode else SHOOT_HINT)

		Step.SHOOT_PAUSED:
			# Stays paused the whole time — same idea as the flipper lesson:
			# test-fire freely (a real bullet, driven by tutorial_director so it
			# still flies while the rest of the world is frozen) and only once
			# they've actually fired does "A" become available to move on.
			_shoot_test_cooldown = maxf(0.0, _shoot_test_cooldown - delta)
			var shoot_dir := _shoot_input()
			if shoot_dir != Vector2.ZERO and _shoot_test_cooldown <= 0.0:
				_tutorial_test_shoot(shoot_dir)
				_shoot_test_cooldown = 0.3
				if not _shot_once:
					_shot_once = true
					_set_hint(CONTINUE_HINT)
					_arm_timer = 0.25
			if _shot_once and _dismiss_ready():
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
			if _dismiss_ready():
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
			if _dismiss_ready():
				_unpause()
				_step = Step.DONE
				GameManager.load_main_menu()

		Step.DONE:
			set_process(false)


func _resolve_refs() -> void:
	_hud = get_tree().get_first_node_in_group("hud")
	_turtle = get_tree().get_first_node_in_group("player")
	# Mouse-mode auto-fire starts off, so a stream of spit isn't competing with
	# the swim/flipper lessons before shooting has even been explained — it's
	# switched on at Step.SHOOT_PAUSED (see _unlock_auto_fire()).
	if _turtle and not _auto_fire_unlocked:
		_turtle.set(&"mouse_fire_enabled", false)
	_ocean = get_tree().get_first_node_in_group("ocean")
	if _pinball == null:
		_pinball = get_node_or_null("../PinballElements")


func _unlock_auto_fire() -> void:
	_auto_fire_unlocked = true
	if _turtle:
		_turtle.set(&"mouse_fire_enabled", true)


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

## Show the prompt and pause. The dismiss input (the A key, the gamepad A, or
## ui_accept — Space/Enter) is ignored for the first DISMISS_ARM_DELAY seconds — ticked down in
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
	_dismiss_active = true
	get_tree().paused = true


## True on the frame the player has acknowledged a paused prompt whose text is
## all on screen: a fresh press of the dismiss key on the final page (earlier
## presses are spent skipping the typing / turning pages — see _tick_prompt()).
##
## This used to also accept RELEASING a key that was already held when the
## pause began (they were swimming left, which is the A key). With typed text
## that would skip straight past a prompt the moment they let go of the stick,
## so only a fresh press counts now.
func _dismiss_ready() -> bool:
	return _dismiss_pressed


func _dismiss_input_down() -> bool:
	return Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_accept")


func _unpause() -> void:
	_dismiss_active = false
	get_tree().paused = false


## Drives the current prompt every frame: types its text (_tick_typing()) and
## interprets the dismiss key. Each press does the first of — finish the text
## that's still typing; turn to the next page; otherwise flag a real dismiss
## for the step logic to pick up via _dismiss_ready().
func _tick_prompt(delta: float) -> void:
	_tick_typing(delta)
	_dismiss_pressed = false
	if not _dismiss_active:
		return
	var down := _dismiss_input_down()
	if _arm_timer > 0.0:
		_arm_timer -= delta
		_dismiss_down_last = down
		return
	var pressed := down and not _dismiss_down_last
	_dismiss_down_last = down
	if not pressed:
		return
	if _typing:
		_finish_typing()
	elif _page_index < _pages.size() - 1:
		_start_page(_page_index + 1)
	else:
		_dismiss_pressed = true


## True once every page of the current prompt has been fully typed out.
func _text_complete() -> bool:
	return not _typing and _page_index >= _pages.size() - 1


## Whole prompt as its list of pages (Callables — see _start_page()).
## final_hint is shown once the last page has finished typing; earlier pages
## show CONTINUE_HINT for turning to the next one.
func _show_pages(pages: Array, final_hint: String) -> void:
	_prompt_wanted = true
	if _prompt_tween and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_pages = pages
	_final_hint = final_hint
	_prompt.modulate.a = 0.0
	_prompt.visible = true
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt, "modulate:a", 1.0, 0.3)
	_start_page(0)


func _show_prompt(text: String, hint: String = "") -> void:
	_show_pages([_page_plain.bind(text)], hint)


## The intro isn't paused or dismissed by a key — swimming clears it.
func _show_intro() -> void:
	_show_pages([_page_intro], INTRO_HINT)


## Three pages: the energy bars, the slow-vs-QUICK recovery, then "go to the
## surface".
func _show_energy_prompt() -> void:
	_show_pages([_page_energy_bars, _page_energy_recover, _page_energy_surface], CONTINUE_HINT)


## One page per entry in FLIPPER_BODY_PAGES. The final page's hint walks the
## player through the flippers (see Step.FLIPPER_PAUSED).
func _show_flipper_prompt() -> void:
	var pages: Array = []
	for i in FLIPPER_BODY_PAGES.size():
		pages.append(_page_flipper.bind(i))
	_show_pages(pages, FLIPPER_HINT_LEFT_MOUSE if GameSettings.mouse_mode else FLIPPER_HINT_LEFT)


## Once both flippers have been worked, adds one more page onto the flipper
## prompt — the "now go launch yourself" line — and types it. It becomes the
## last page, so its hint is the plain continue prompt rather than the
## flipper-walkthrough one the earlier final page carried.
func _show_flipper_launch_page() -> void:
	_pages.append(_page_flipper_launch)
	_final_hint = CONTINUE_HINT
	_start_page(_pages.size() - 1)


## Lays out one page and starts typing it. Page callables show whatever labels
## they need, and return the ones to type, in order (setting up any sparkle
## words in _type_sparkles on the way).
func _start_page(index: int) -> void:
	_page_index = index
	_message.visible = false
	_message_rich.visible = false
	_hide_all_custom_prompt_nodes()
	_type_sparkles.clear()
	_type_nodes = _pages[index].call()
	# Blank every label on the page now, not as its turn comes up — the ones
	# still waiting would otherwise sit there fully visible from the start.
	for node: Control in _type_nodes:
		_set_visible_chars(node, 0)
	_set_hint(_final_hint if index >= _pages.size() - 1 else CONTINUE_HINT)
	_type_budget = -TYPE_START_DELAY
	_typing = not _type_nodes.is_empty()
	if _typing:
		_begin_node(0)


func _page_plain(text: String) -> Array:
	_message.visible = true
	_message.text = text
	return [_message]


## The intro prompt, built as rich text so the UFO part and workshop icons can
## sit inline right after their names (like the how-to-play screen).
func _page_intro() -> Array:
	_message_rich.visible = true
	_message_rich.clear()
	_message_rich.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	_message_rich.append_text("You are Flip, UFO Repair Turtle.\n\nYour goal is to pick up UFO parts ")
	_message_rich.add_image(PART_ICON, 14, 14, Color.WHITE, INLINE_ALIGNMENT_CENTER, PART_ICON_REGION)
	_message_rich.append_text(" and bring them to your UFO Workshop ")
	_message_rich.add_image(WORKSHOP_ICON, 17, 17, Color.WHITE, INLINE_ALIGNMENT_CENTER, WORKSHOP_ICON_REGION)
	_message_rich.append_text(".\n\nGive it a try!")
	_message_rich.pop()
	return [_message_rich]


## Energy lesson, page 1: the small bar above the turtle and the big one in the
## HUD. Rich text, for the inline icon/bar images.
func _page_energy_bars() -> Array:
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
	return [_message_rich]


## Energy lesson, pages 2 and 3: dedicated rows of plain Labels (text lives in
## the scene) for the two sparkle words ("QUICKLY", "yellow sparkles") — each
## needs to be its own node so the sparkle can be positioned exactly on top of
## it via get_global_rect(), which a substring inside a flowing RichTextLabel
## paragraph can't give us. The sparkle starts once its word has been typed.
func _page_energy_recover() -> Array:
	_energy_fast_row.visible = true
	_type_sparkles[_energy_fast_word] = "energy_fast"
	return [_energy_fast_before, _energy_fast_lead, _energy_fast_word, _energy_fast_after]


func _page_energy_surface() -> Array:
	_energy_sparkle_row.visible = true
	_type_sparkles[_energy_sparkle_word] = "energy_sparkle_word"
	return [_energy_sparkle_before, _energy_sparkle_lead, _energy_sparkle_word, _energy_sparkle_after]


## Flipper lesson, one page per entry in FLIPPER_BODY_PAGES. Page 0 opens with
## FlipperFastRow, split off the same way so the sparkle can land on its
## "QUICKLY" too; the rest of each page is FlipperBody, a plain autowrap Label.
func _page_flipper(index: int) -> Array:
	_flipper_body.visible = true
	_flipper_body.text = FLIPPER_BODY_PAGES[index]
	if GameSettings.mouse_mode and index == FLIPPER_BODY_PAGES.size() - 1:
		_flipper_body.text = FLIPPER_HOWTO_MOUSE
	if index == 0:
		_flipper_fast_row.visible = true
		_type_sparkles[_flipper_fast_word] = "flipper_fast"
		return [_flipper_fast_before, _flipper_fast_word, _flipper_body]
	return [_flipper_body]


func _page_flipper_launch() -> Array:
	_flipper_body.visible = true
	_flipper_body.text = FLIPPER_LAUNCH_TEXT
	return [_flipper_body]


# ── Typewriter ───────────────────────────────────────────────────────────

## Every prompt label reveals its text through visible_characters. The default
## behavior (VC_CHARS_BEFORE_SHAPING) re-wraps the text as letters are added, so
## words jump lines mid-type and the centered block shifts as it grows;
## AFTER_SHAPING lays the whole text out up front and only hides the glyphs not
## yet typed.
func _configure_typed_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			(child as Label).visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		elif child is RichTextLabel:
			(child as RichTextLabel).visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		_configure_typed_labels(child)


func _tick_typing(delta: float) -> void:
	if not _typing:
		return
	_type_budget += delta
	while _typing and _type_budget >= _type_cost:
		_type_budget -= _type_cost
		_type_pos += 1
		_set_visible_chars(_type_nodes[_type_node_i], _type_pos)
		_type_cost = _char_cost(_type_pos - 1)
		if _type_pos >= _type_text.length():
			_finish_current_node()


## Seconds to wait after revealing the letter at `index` of the current label.
## Sentence-ending punctuation only pauses when it actually ends the sentence
## (followed by a space, newline or the end), so "yeah..." pauses once, not
## three times.
func _char_cost(index: int) -> float:
	var cost := 1.0 / TYPE_CHARS_PER_SECOND
	var c: String = _type_text[index]
	var next: String = _type_text[index + 1] if index + 1 < _type_text.length() else ""
	if c in ".!?" and (next == "" or next == " " or next == "\n"):
		cost += TYPE_SENTENCE_PAUSE
	elif c in ",;:—" and (next == "" or next == " "):
		cost += TYPE_CLAUSE_PAUSE
	return cost


func _begin_node(index: int) -> void:
	_type_node_i = index
	var node: Control = _type_nodes[index]
	_type_text = _node_text(node)
	_type_pos = 0
	_type_cost = 1.0 / TYPE_CHARS_PER_SECOND
	_set_visible_chars(node, 0)
	if _type_text.is_empty():
		_finish_current_node()


## Shows the current label in full, starts its sparkle (if it has one), and
## moves on to the next label on the page — or ends typing.
func _finish_current_node() -> void:
	var node: Control = _type_nodes[_type_node_i]
	_set_visible_chars(node, -1)
	if _type_sparkles.has(node):
		_show_sparkle_on(_type_sparkles[node], node as Label)
	if _type_node_i + 1 < _type_nodes.size():
		_begin_node(_type_node_i + 1)
	else:
		_typing = false


## Dismiss key while text is still typing: reveal the rest of the page at once.
func _finish_typing() -> void:
	while _typing:
		_finish_current_node()


func _node_text(node: Control) -> String:
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	return (node as Label).text


## Label and RichTextLabel both expose visible_characters (-1 = everything).
func _set_visible_chars(node: Control, count: int) -> void:
	node.set("visible_characters", count)


func _hide_prompt() -> void:
	_prompt_wanted = false
	_typing = false
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
	# is_visible_in_tree(), not .visible: a page turn hides the label's whole row,
	# which leaves the label's own flag set.
	if not is_instance_valid(label) or not label.is_visible_in_tree():
		return
	p.global_position = label.get_global_rect().get_center()
	p.emitting = true


func _hide_all_sparkles() -> void:
	for p in _sparkles.values():
		p.emitting = false


## Swap just the hint line without re-fading the whole prompt.
func _set_hint(text: String) -> void:
	_hint.text = text
	_hint_row.visible = text != ""


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


## Delegates to TurtlePlayer.get_shoot_input() — the same check it uses
## before firing (stick threshold, mouse-mode aim/auto-fire), so "has shot"
## here means a real bullet would actually have spawned. ZERO = not shooting.
func _shoot_input() -> Vector2:
	if _turtle == null or not _turtle.has_method("get_shoot_input"):
		return Vector2.ZERO
	return _turtle.call(&"get_shoot_input")


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
