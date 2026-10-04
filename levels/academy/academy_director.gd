# academy_director.gd
extends Node
class_name AcademyDirector

## Runs the UFO Repair Turtle Academy course: the intro, four lessons and the
## exam, written top to bottom as one coroutine (_run()). Dialogue goes through
## AcademyPanel.say(); gameplay tasks are polled with _wait_until().
##
## The play area is paused whenever the instructor is talking, so the player
## reads instead of swimming around: _say() pauses the tree, and setting a
## task hint (_set_task()) un-pauses it — every challenge and "try it" step
## sets one. This node and the AcademyPanel run with PROCESS_MODE_ALWAYS.
##
## Challenges with enemies restart if the turtle dies: AcademyController
## respawns the turtle and emits player_respawned, which _wait_until() reports
## as Outcome.DIED. Waits resume on _ticked (emitted from _process, skipped
## while the pause menu is open), so the whole course holds still under the
## pause menu, and simply stops if the scene is freed mid-wait.

signal _ticked

enum Outcome { DONE, DIED, SWAM }  # SWAM: held a swim direction past SWIM_HOLD_LIMIT_SECONDS

const LESSONS: Array[String] = [
	"Deep Ocean, Deep Space",
	"The Ancients",
	"The Haters",
	"Trash",
	"The Exam",
]
## The exam isn't listed on the agenda (or numbered as a lesson) — the course
## just rolls into it after the last lesson.
const AGENDA_LESSON_COUNT := 4

const PIRANHA_SCENE := preload("res://entities/enemies/piranha/piranha.tscn")
const CROCODILE_SCENE := preload("res://entities/enemies/crocodile/crocodile.tscn")
const SEA_URCHIN_SCENE := preload("res://entities/enemies/sea_urchin/sea_urchin.tscn")
const WORKSHOP_SCENE := preload("res://entities/environment/ufo_workshop/ufo_workshop.tscn")
const UFO_PIECE_SCENE := preload("res://entities/collectibles/ufo_piece/ufo_piece.tscn")
const HEALTH_PLANT_SPAWNER_SCENE := preload("res://entities/collectibles/health_plant/health_plant_spawner.tscn")
const TRASH_SEQUENCE_SCENE := preload("res://systems/trash_cleanup/trash_sequence.tscn")
const PIRANHA_SPAWNER_SCENE := preload("res://entities/enemies/piranha/piranha_spawner.tscn")
const AIR_BUBBLE_SPAWNER_SCENE := preload("res://entities/collectibles/air_bubble/air_bubble_spawner.tscn")
const AIR_BUBBLE_SCENE := preload("res://entities/collectibles/air_bubble/air_bubble.tscn")

# ── Layout (world space; play area is x -104..312 — centre x 104 — surface y -126, floor y 164) ──
# The level root sits at the origin, so spawns set `position` before
# add_child() — some scenes (sea urchins) record their spot in _ready().
const WORKSHOP_POS := Vector2(40, -138)
const PIECE_SPOTS: Array[Vector2] = [Vector2(-60, 150), Vector2(104, 150), Vector2(268, 150)]
## Lesson 2's flipper challenge: a little in from the walls, and deliberately
## not mirrored, so the left and right flippers each need a different angle.
const FLIPPER_PIECE_SPOTS: Array[Vector2] = [Vector2(-10, 150), Vector2(210, 150)]
const PIRANHA_SPOTS: Array[Vector2] = [Vector2(0, -30), Vector2(210, -30), Vector2(0, 110), Vector2(210, 110)]
const SUPER_SPEED_PIRANHA_SPOT := Vector2(104, 10)
# const MIXED_PIRANHA_SPOTS: Array[Vector2] = [Vector2(20, 110), Vector2(200, 110)]
const CROC_POS := Vector2(220, -126)
## The Academy croc is a slow croc — a lesson, not a boss fight (defaults:
## patrol 80, chase 150). Its chase is only a touch faster than its patrol;
## the croc's own close-range slowdown (chase_slowdown_range) still applies
## on top.
const CROC_PATROL_SPEED := 60.0
const CROC_CHASE_SPEED := 85.0
const URCHIN_SPOTS: Array[Vector2] = [Vector2(-22, -5), Vector2(230, -5)]

const SWIM_PRACTICE_SECONDS := 4.5
## After the first surface sparkle, the lesson waits this long before moving on
## so the player actually sees (and hears) it. A flat delay, since energy
## refills too fast at the surface to require sparkling for a while.
const SURFACE_WATCH_SECONDS := 1.5
const SURFACE_DEPTH := 24.0
const SPIT_PRACTICE_COUNT := 10
const PIRANHA_CHALLENGE_COUNT := 4
const HEALTH_PLANT_COUNT := 6
## Exam health plants: this many to start, then one more every
## EXAM_PLANT_INTERVAL seconds while fewer than EXAM_MAX_PLANTS are out — so
## they don't all wilt at once.
const EXAM_START_PLANTS := 2
const EXAM_MAX_PLANTS := 4
const EXAM_PLANT_INTERVAL := 15.0
## Exam trash: a fresh line this long after the last one (and its power-up)
## has left the play area.
const EXAM_TRASH_INTERVAL := 8.0
const EXAM_PIECES := 3
const EXAM_DELIVERIES := 2
## The turtle's floating energy bar grows and shrinks between 1x and this
## scale while Lesson 1 points it out.
const BAR_PULSE_MAX_SCALE := 2.0
const BAR_PULSE_SPEED := 7.0
## The HUD's big energy meter pulses the same way (gentler — it's much bigger)
## while the "supersized" line is up.
const HUD_METER_PULSE_MAX_SCALE := 1.25
## Energy fraction that counts as tired — the turtle's own bar turns red here.
const TIRED_ENERGY_FRACTION := 0.2
## Free play after grabbing the trash reward, before the lesson moves on.
const REWARD_PLAY_SECONDS := 8.0
const TRASH_TASK := "Shoot a group of trash to reveal a power-up"
const TRASH_COLLECT_TASK := "Collect the power-up"
## Lesson 2's pinball practice: launches off flippers and bounces off bumpers
## needed, the minimum time it runs even once they're done, and how long each
## of the two attempts gets before the nudge / the stubborn ending.
const PINBALL_PRACTICE_COUNT := 2
## Lesson 2's cradle challenge: rest in a held flipper's nook for this long,
## in one go. A turtle moving faster than CRADLE_MAX_SPEED isn't resting.
const CRADLE_SECONDS := 2.0
const CRADLE_MAX_SPEED := 50.0
## The swim-hold limit: holding a swim direction longer than this, in one go,
## fails Lesson 2's nudge challenge (_nudge_challenge()) and the exam's second
## delivery. The pie timer by the turtle drains over exactly this long.
## ← tune here
const SWIM_HOLD_LIMIT_SECONDS := 1.3
const SWIM_PIE_OFFSET := Vector2(15, -15)  # from the turtle, world px
## Multiplied into the flipper's colours: red and blue cut right down, green
## pushed past 1 so it glows.
const NUDGE_DONE_FLIPPER_TINT := Color(0.15, 1.9, 0.15)
const PINBALL_PRACTICE_MIN_SECONDS := 15.0
const PINBALL_PRACTICE_TIMEOUT := 45.0
## Play keeps going this long after a challenge or task ends before the level
## pauses for the next line — see _pause_after_play().
const RESULT_PLAYOUT_SECONDS := 1.2
## A piece only counts as "grabbed off a flipper hit" this soon after the
## flipper launch (real ms — GameManager.last_flipper_launch_msec).
const FLIPPER_PICKUP_WINDOW_MSEC := 3000
const FLASH_HINT_SECONDS := 2.0
## Gap before a missed trash line is replaced by a fresh one.
const TRASH_RESPAWN_DELAY := 1.5
const TRASH_ITEMS := 4
const TRASH_DRIFT_SPEED := 35.0
const TRASH_REWARDS: Array[int] = [
	Powerup.PowerupType.SHIELD,
	Powerup.PowerupType.ENERGY_ENDLESS,
	Powerup.PowerupType.RAPID_FIRE,
]

## Prefilled on the graduation name prompt the first time (and used if they
## submit it blank) — gamepad players can't type, so they can accept this.
const DEFAULT_PLAYER_NAME := "Turtle"
const RETRY_TEXT := "Ah dang- Give it another go! You'll get it!"

## Dev aid for tuning: start the course at this lesson (0 = the intro, 1-5 =
## that lesson), with everything the earlier lessons would have added already
## in the level. Leave at 0 for the real course.
@export_range(0, 5) var start_lesson: int = 0

@onready var _level: AcademyController = get_parent()
@onready var _panel: AcademyPanel = $"../AcademyPanel"
@onready var _pinball: Node2D = $"../PinballElements"

# Untyped on purpose: TurtlePlayer/HUD members are reached duck-typed.
var _turtle = null
var _hud = null
var _ocean = null

var _died := false
var _deliveries := 0
var _spits := 0
var _powerup_got := -1
var _narrating := false
## Driven from _process() (this node runs while the tree is paused, the turtle
## doesn't), not a looping tween — see _set_bar_pulse().
var _bar_pulse := false
var _bar_pulse_time := 0.0
var _hud_meter_pulse := false
## Every DeadWall shows its charge animation (and the charge sound plays)
## while Lesson 2 explains wall recharging — see _set_wall_charge_demo().
var _wall_charge_demo := false
var _hud_meter_pulse_time := 0.0

var _workshop: Node2D = null
var _pieces: Array = []
var _challenge_enemies: Array[Node] = []
var _fixtures: Array[Node] = []  # crocodile + sea urchins, kept from Lesson 3 on
var _plant_spawner: HealthPlantSpawner = null
var _trash_seq: TrashSequence = null
var _exam_spawner: Node2D = null
var _swim_pie: SwimPie = null
var _swim_held := 0.0  # seconds the current swim hold has lasted (see _swim_hold_tick())
var _exam_plant_timer := 0.0
var _exam_trash_timer := 0.0

var _task_hint := ""
var _flash_token := 0
var _any_input := false


## The nudge challenge's pie timer: a full disc that drains clockwise as
## `remaining` goes 1 → 0, turning from gold to red on the way.
class SwimPie extends Node2D:
	const RADIUS := 7.0
	var remaining := 1.0:
		set(value):
			remaining = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, RADIUS + 1.5, Color(0, 0, 0, 0.75))
		if remaining <= 0.0:
			return
		var color := Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.85, 0.2), remaining)
		if remaining >= 0.999:
			draw_circle(Vector2.ZERO, RADIUS, color)
			return
		# The wedge still left, from 12 o'clock round to where it has drained to.
		var points := PackedVector2Array([Vector2.ZERO])
		var steps := 24
		for i in steps + 1:
			var angle := -PI * 0.5 - TAU * remaining * float(i) / float(steps)
			points.append(Vector2(cos(angle), sin(angle)) * RADIUS)
		draw_colored_polygon(points, color)


func _ready() -> void:
	_level.player_respawned.connect(func() -> void: _died = true)
	LevelManager.piece_delivered.connect(_on_piece_delivered)
	# Pinball arrives in Lesson 2. Disabled rather than just hidden, so the
	# flippers don't flip (or click) on input and nothing collides.
	_pinball.visible = false
	_pinball.process_mode = Node.PROCESS_MODE_DISABLED
	_panel.set_agenda(LESSONS.slice(0, AGENDA_LESSON_COUNT))
	_run.call_deferred()


func _process(delta: float) -> void:
	if AcademyPanel.pause_menu_open(get_tree()):
		return
	# The pause menu restores the paused state it found, but anything else that
	# unpauses the tree mid-narration is put right here.
	if _narrating and not get_tree().paused:
		get_tree().paused = true
	if _bar_pulse and _turtle:
		_bar_pulse_time += delta
		_turtle.set_float_energy_bar_scale(lerpf(1.0, BAR_PULSE_MAX_SCALE, _pulse_wave(_bar_pulse_time)))
	if _wall_charge_demo:
		for wall in get_tree().get_nodes_in_group("dead_walls"):
			wall.step_charge_demo(delta)
		if _hud.sfx_energy_charge and not _hud.sfx_energy_charge.playing:
			_hud.sfx_energy_charge.play()
	if _hud_meter_pulse and _hud and _hud.energy_container:
		_hud_meter_pulse_time += delta
		var meter: Control = _hud.energy_container
		meter.pivot_offset = meter.size * 0.5
		var k := lerpf(1.0, HUD_METER_PULSE_MAX_SCALE, _pulse_wave(_hud_meter_pulse_time))
		meter.scale = Vector2(k, k)
	if is_instance_valid(_exam_spawner) and not get_tree().paused:
		_exam_tick(delta)
	_ticked.emit()


## 0 → 1 → 0 ease, starting at 0, for the attention pulses above.
func _pulse_wave(time: float) -> float:
	return (1.0 - cos(time * BAR_PULSE_SPEED)) * 0.5


func _input(event: InputEvent) -> void:
	if AcademyPanel.pause_menu_open(get_tree()) or event.is_action("pause"):
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
			and event.is_pressed() and not event.is_echo():
		_any_input = true


## LevelManager.start_level() also emits this with 0 to reset the HUD counter.
func _on_piece_delivered(collected: int, _needed: int) -> void:
	if collected > 0:
		_deliveries += 1


# ── The course ───────────────────────────────────────────────────────────

func _run() -> void:
	_turtle = get_tree().get_first_node_in_group("player")
	_hud = get_tree().get_first_node_in_group("hud")
	_ocean = get_tree().get_first_node_in_group("ocean")
	if _turtle == null or _hud == null:
		push_error("AcademyDirector: no turtle or HUD in the scene")
		return
	_turtle.spit_fired.connect(func() -> void: _spits += 1)
	_turtle.powerup_applied.connect(func(t: int) -> void: _powerup_got = t)
	# Mouse-mode auto-fire stays off until spitting is taught (Lesson 3).
	_turtle.mouse_fire_enabled = false
	_hide_hud_piece_counter()

	_set_world_paused(true)
	await _panel.play_banner("WELCOME TO THE", "UFO Repair Academy!", _start_prompt())
	await _panel.reveal_header()
	await _panel.wait_for_continue()  # let the agenda sink in before any words
	_skip_ahead(start_lesson)
	if start_lesson <= 0:
		await _intro()
	if start_lesson <= 1:
		if not await _lesson_1():
			return  # training ended early (back to the main menu)
	if start_lesson <= 2:
		if not await _lesson_2():
			return  # training ended early (back to the main menu)
	if start_lesson <= 3:
		await _lesson_3()
	if start_lesson <= 4:
		await _lesson_4()
	await _lesson_5()


## Sets the level up as it would be at the start of `lesson` (see start_lesson).
func _skip_ahead(lesson: int) -> void:
	if lesson >= 2:
		_spawn_workshop()
		_top_up_pieces(PIECE_SPOTS.size() - 1)
		_reveal_pinball()
	if lesson >= 4:
		_turtle.mouse_fire_enabled = true
		_spawn_fixtures()
		_spawn_health_plants(HEALTH_PLANT_COUNT)
	if lesson >= 2:
		_panel.set_agenda_state(lesson - 1, lesson - 1)


func _intro() -> void:
	_panel.set_lesson_title("Hello!")
	await _say(["Welcome Turtles! Thanks for your interest. UFO Repair is a fascinating field. You just might meet an alien some day. Hopefully they're nice! Now let's get you certified!"])


func _lesson_1() -> bool:
	await _begin_lesson(0)
	await _say(["Good news first- The ocean is full of crashed UFOs. The bad news? The ocean is deep and UFOs sink. But you can swim at least!"])

	# The bar grows and shrinks for as long as it's being talked about and
	# practised with.
	_set_bar_pulse(true)
	await _say(["Swimming takes energy. See that yellow bar above your head? That's your energy meter. Swim and it empties, stop swimming and it refills. Try it out. Use %s to swim." % _swim_label()], false)
	_set_task("Swim with %s" % _swim_label())
	var swum := 0.0
	while swum < SWIM_PRACTICE_SECONDS:
		await _ticked
		if _any_pressed([&"move_up", &"move_down", &"move_left", &"move_right"]):
			swum += get_process_delta_time()
	_set_bar_pulse(false)
	_set_task("")

	_set_hud_meter_pulse(true)
	await _say(["The same meter is supersized on the top right for the turtles in the back."])
	_set_hud_meter_pulse(false)

	await _say(["As you probably noticed, it's tiring to swim, and slow to recover. But fresh air helps! At the surface you refill energy faster. You sparkle yellow, and there's a weird sound too. Swim until your energy is in the red and then go to the surface to see what I mean."])
	# Two steps, in order: actually get tired (swimming at the surface refills
	# about as fast as it drains, so the hint says to go deep), then recharge
	# at the surface. A sparkle on a nearly-full bar doesn't count. The bar is
	# refilled before they get control, so being in the red already when this
	# beat starts can't count — only swimming it down from full does.
	_refill_energy()
	_set_task("Swim deep until your energy bar turns red")
	while not _energy_tired():
		await _ticked
	_set_task("Now go to the surface!")
	while not _surface_sparkling():
		await _ticked
	await _wait_seconds(SURFACE_WATCH_SECONDS)
	_set_task("")

	await _say(["Great. Now about that bad news... heavy UFO pieces."])
	_spawn_workshop()
	_top_up_pieces(PIECE_SPOTS.size())
	await _say(["To repair a UFO, you gotta bring UFO pieces to your workshop. You should have just enough energy to dive straight down for one. Pick one up and drop it off in your workshop."], false)
	_refill_energy()
	_set_task("Bring a UFO piece to your workshop")
	await _wait_for_delivery()
	_set_task("")

	await _say(["Well done! They are heavy, so in a pinch, you can drop a piece you hold with %s. Try it. Dive down to grab another and practice dropping it." % _drop_label()], false)
	if not await _drop_practice():
		return false

	_complete_lesson(0)
	await _say(["Magnifique! You've completed lesson 1!"])
	return true


func _lesson_2() -> bool:
	await _begin_lesson(1)
	await _say(["We don't know who built pinball long ago. We can only purr in awe and gratitude that they did. It makes UFO repair a heck of a lot easier."])

	_reveal_pinball()
	await _say(["Behold! Thanks to pinball, you can collect UFO pieces without fainting from exhaustion! It's really quite simple. Use %s to flip leftward flippers, and %s to flip rightward ones. Try it!" % [_flipper_label(true), _flipper_label(false)]], false)
	# Flipper practice happens with the level still paused: only the flippers
	# themselves run, so the player watches them move without drifting off.
	_set_flippers_live(true)
	_set_task("Flip LEFT: %s" % _flipper_label(true), false)
	while not Input.is_action_pressed(&"flipper_left"):
		await _ticked
	_set_task("Now RIGHT: %s" % _flipper_label(false), false)
	while not Input.is_action_pressed(&"flipper_right"):
		await _ticked
	await _wait_seconds(0.5)
	_set_flippers_live(false)
	_set_task("")

	await _say(["Very nice. If there's one thing all academy graduates agree on, it's that pinball is essential. Without it, you just can't get this type of work done."])

	await _say(["But it takes practice! Go explore pinball, the ancients' gift. Try the flippers. Try the bumpers. Go use both at least twice."])
	if not await _pinball_practice():
		return false

	await _say(["There's one teaching of the Ancients all turtles need to know- Cradling. That's when you rest in the nook of a flipper while holding its flipper input down, so you can sit in the space between the flipper and the wall. Cradle for %d seconds." % int(CRADLE_SECONDS)])
	await _cradle_challenge()
	# Paused again after the cradle: every wall shows its charge animation
	# while the instructor explains what they just felt.
	_set_wall_charge_demo(true)
	await _say(["Cozy, right? And notice your energy. Touching pinball flippers and walls refills it fast, just like the surface does. A cradle is the best seat in the ocean."])
	_set_wall_charge_demo(false)

	await _say(["One more thing before your notes. Rookies swim, swim, swim until they pass out. Pros nudge. A little tap to line up, then let the ocean and the flippers do the work."])
	await _say(["So: launch off all four flippers. But see that little pie by your head? Hold %s too long and it runs out, and we start over. Short nudges only!" % _swim_label()])
	await _nudge_challenge()

	await _say(["Now use a flipper to pick up a UFO piece. I'm only gonna let you hold it if you get it from a flipper hit, no dives allowed! Bring it to your workshop once you've got it."])
	_place_flipper_challenge_pieces()
	_set_piece_filter(_flipper_pickup_only)
	_set_task("Flipper into a piece, then deliver it")
	await _wait_for_delivery()
	_set_piece_filter(Callable())
	_set_task("")

	_complete_lesson(1)
	await _say(["Excellent! One last thing for your notes. When you shoot off flippers and bumpers you launch at super speed. At that speed nothing can hurt you. In fact, it's you doing the hurting! More on that in the next lesson"])
	return true


func _lesson_3() -> void:
	await _begin_lesson(2)
	await _say(["There's plenty of haters out there. They're not so bad though. Well, besides, um, the croc, oh, and the US governm.. never mind.. yeah, So you have 2 weapons at your disposal. The first is your spit."])

	_turtle.mouse_fire_enabled = true
	await _say(["Shoot your spit with %s. You can spit in any direction you like. Try it!" % _spit_label()], false)
	_clear_pieces()
	_set_task("Spit %d times" % SPIT_PRACTICE_COUNT)
	_spits = 0
	while _spits < SPIT_PRACTICE_COUNT:
		await _ticked
	_set_task("")

	# Enemy challenges wait for the continue press after their intro, so the
	# player isn't reading and fighting at the same time.
	await _say(["Got a hater on your tail? Just spit! If they do get you, you'll lose a heart. You only have 7. But don't stress, you're here to practice. Spit all these piranhas goodnight."])
	await _enemy_challenge("Spit all %d piranhas goodnight" % PIRANHA_CHALLENGE_COUNT,
		func() -> void: _spawn_challenge_piranhas(PIRANHA_SPOTS.slice(0, PIRANHA_CHALLENGE_COUNT)))

	await _say(["Good! Your other weapon? I already told you- Super Speed! Kill this next piranha using only super speed from pinball flippers or bumpers. No spitting allowed!"])
	_turtle.shoot_locked = true
	await _enemy_challenge("Super speed only - no spitting!",
		func() -> void: _spawn_challenge_piranhas([SUPER_SPEED_PIRANHA_SPOT]))
	_turtle.shoot_locked = false

	await _say(["Well done! Now for more bad news. Not everything is vulnerable to spit or super speed. Crocodiles and sea urchins, for instance. They're simply not bothered."])
	_spawn_fixtures()
	await _say(["See what I mean for yourself. Try shooting them. They just shake. The croc is especially nasty. I hate to do this, but go say hello. It's part of the job. Just don't die. You haven't paid yet!"])
	await _hazard_hit_challenge()

	await _say(["Scary, right!? Sorry about that, but I had to for your own sake. UFO Repair is no reef walk, afterall. Now take a breath, and kill a few more piranhas. It'll help you relax, I promise!"])
	await _enemy_challenge("Take out the 4 piranhas",
		func() -> void: _spawn_challenge_piranhas(PIRANHA_SPOTS))

	await _say(["You live! Well done. After taking a beating, its crucial to keep an eye out for plants."])
	_spawn_health_plants(HEALTH_PLANT_COUNT)
	await _say(["You eat them to gain health. Eat one now, but don't dilly dally too long, they don't live forever."])
	await _plant_challenge()
	_complete_lesson(2)
	await _say(["Delicious. Lesson 3 complete!"])


func _lesson_4() -> void:
	_remove_croc()  # back for the exam (_setup_exam())
	_reset_health_plants(0)
	await _begin_lesson(3)
	await _say([" I don't know what's worse, haters or trash. Thankfully, turtle spit deals with both. You'll see clusters of trash floating by. Shoot them all and the ocean will thank you with a power-up."])
	await _say(["You get points for shooting trash too, and good things come from getting points, trust me. Try now to shoot a whole line of trash and collect the power-up."])
	var reward := await _trash_challenge()
	# Same wind-down as any finished challenge, then explain the power-up, then
	# let them actually enjoy it before the lesson carries on.
	await _say([_reward_explanation(reward)])
	_set_task("Enjoy your power-up!")
	await _wait_seconds(REWARD_PLAY_SECONDS)
	_set_task("")
	_complete_lesson(3)
	await _say(["Thrilling! FYI, there's also big trash bags. Those contain alien technologies, which are like super power-ups. But that's the advanced course. I'll let you learn that on your own. Lesson done! It's exam time!"])


func _lesson_5() -> void:
	await _begin_lesson(4)
	await _say(["Pass this exam and you'll be certified!"])
	await _say(["It's simple- You just gotta bring two UFO pieces from the ocean floor to the UFO workshop without dying. When you're ready, go ahead and start."], false)

	var first_attempt := true
	while true:
		_setup_exam()
		_set_task("Press any key to start the exam", false)
		_any_input = false
		while not _any_input:
			await _ticked
		_set_task("")
		if first_attempt:
			first_attempt = false
			await _say(["Oh! I forgot to talk about breathing. But you're a reptile, surely you know how that works! Carry on!"])
			_enable_air()

		_start_exam_spawner()
		var outcome := Outcome.DONE
		for delivered in EXAM_DELIVERIES:
			# The second piece has to be fetched on nudges: the swim-hold limit
			# (and its pie) from Lesson 2 comes back.
			var limit_swim := delivered == EXAM_DELIVERIES - 1
			if limit_swim:
				await _say(["One down! Now the pro part. For this last piece, short nudges only. Hold %s too long, the pie runs out, and the exam starts over." % _swim_label()])
				_swim_hold_start()
			var task := "Deliver %d pieces (%d/%d)" % [EXAM_DELIVERIES, delivered, EXAM_DELIVERIES]
			_set_task(task + " - short nudges only!" if limit_swim else task)
			outcome = await _wait_for_delivery(limit_swim)
			if outcome != Outcome.DONE:
				break
		_swim_hold_stop()
		_set_task("")
		_stop_exam_spawner()
		if outcome == Outcome.DONE:
			break
		_clear_challenge_enemies()
		if outcome == Outcome.SWAM:
			await _say(["Too much swimming! Nudge, flip, drift. Let's take the exam from the top."], false)
		else:
			await _say([RETRY_TEXT], false)

	await _pause_after_play()
	_complete_lesson(4)
	SaveManager.set_academy_certified()
	_panel.set_title("CERTIFIED!", Color(1.0, 0.85, 0.0))
	_panel.set_lesson_title("Graduation")
	_panel.clear_dialogue()
	_panel.set_hint("")
	# They sign their certificate: the name goes on the banner and is kept for
	# the scoreboard (SaveManager.get_player_name()).
	var saved_name := SaveManager.get_player_name()
	var player_name := await _panel.ask_name(saved_name if saved_name != "" else DEFAULT_PLAYER_NAME)
	SaveManager.set_player_name(player_name)
	await _panel.play_banner("CONGRATULATIONS!", "%s, Certified UFO Repair Turtle" % player_name)
	await _say(["Congratulations, %s! You are now a Certified UFO Repair Turtle! Go repair some UFOs!" % player_name])
	_set_world_paused(false)
	GameManager.load_main_menu()


# ── Dialogue + lesson bookkeeping ────────────────────────────────────────

## Pauses the play area for as long as the instructor is talking. The next
## task (_set_task()) un-pauses it.
func _say(chunks: Array, wait_last: bool = true) -> void:
	await _pause_after_play()
	await _panel.say(chunks, wait_last)


## Pauses the level and plays the big lesson banner over the play area
## before the lesson's first line.
func _begin_lesson(index: int) -> void:
	await _pause_after_play()
	_panel.clear_dialogue()
	_panel.set_hint("")
	_panel.set_agenda_state(index, index)
	if index >= AGENDA_LESSON_COUNT:
		_panel.set_lesson_title(LESSONS[index])
		await _panel.play_banner("LAST STOP",LESSONS[index])
		return
	_panel.set_lesson_title("Lesson %d: %s" % [index + 1, LESSONS[index]])
	await _panel.play_banner("LESSON %d" % (index + 1), LESSONS[index])


func _complete_lesson(index: int) -> void:
	_panel.set_agenda_state(index, index + 1)


## Shows what the player should do now. A task means they're playing, so it
## un-pauses the play area — pass play = false for one that waits on a key
## press instead (the exam's "press any key to start").
func _set_task(text: String, play: bool = true) -> void:
	_task_hint = text
	_flash_token += 1
	_panel.set_hint(text)
	if text != "" and play:
		_set_world_paused(false)


## Briefly swaps the hint line for a short message, then puts the task back.
func _flash_hint(text: String) -> void:
	_flash_token += 1
	var token := _flash_token
	_panel.set_hint(text)
	await _wait_seconds(FLASH_HINT_SECONDS)
	if token == _flash_token:
		_panel.set_hint(_task_hint)


# ── Waiting on the player ────────────────────────────────────────────────

func _wait_seconds(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await _ticked
		t += get_process_delta_time()


## Polls cond every frame. Returns DIED instead if the turtle dies (and is
## respawned) first.
func _wait_until(cond: Callable) -> Outcome:
	_died = false
	while true:
		await _ticked
		if _died:
			return Outcome.DIED
		if cond.call():
			return Outcome.DONE
	return Outcome.DONE


## Waits for the next delivery. With limit_swim, the swim-hold limit applies
## meanwhile (between _swim_hold_start() and _swim_hold_stop()) and running it
## out returns SWAM.
func _wait_for_delivery(limit_swim: bool = false) -> Outcome:
	var target := _deliveries + 1
	_died = false
	while _deliveries < target:
		await _ticked
		if _died:
			return Outcome.DIED
		if limit_swim and _swim_hold_tick():
			return Outcome.SWAM
	return Outcome.DONE


## Runs an enemy fight until every enemy it spawned is gone. On death the
## fight is cleared, the instructor cheers them on, and it starts over.
func _enemy_challenge(task: String, spawn: Callable) -> void:
	_clear_pieces()
	while true:
		spawn.call()
		_set_task(task)
		var outcome := await _wait_until(_challenge_enemies_gone)
		_set_task("")
		if outcome == Outcome.DONE:
			return
		_clear_challenge_enemies()
		await _say([RETRY_TEXT])


## Lesson 3: get hurt once by the crocodile, to feel that it can't be beaten.
## Dying before that starts it over.
func _hazard_hit_challenge() -> void:
	_clear_pieces()
	var hit := {"croc": false}
	var on_damaged := func(source: String) -> void:
		if source.ends_with(" a crocodile"):
			hit.croc = true
	_turtle.damaged.connect(on_damaged)
	while not hit.croc:
		_set_task("Meet the croc and take a hit from it")
		_died = false
		while not hit.croc and not _died:
			await _ticked
		if not hit.croc:
			_set_task("")
			await _say([RETRY_TEXT])
	_turtle.damaged.disconnect(on_damaged)
	_set_task("")


## Lesson 3: eat a health plant before they all wilt. Plants keep their
## normal lifetime here; if every one is gone uneaten, a fresh batch grows
## and the challenge starts over.
func _plant_challenge() -> void:
	_clear_pieces()
	var state := {"eaten": false}
	var on_eaten := func() -> void: state.eaten = true
	while true:
		for plant in get_tree().get_nodes_in_group("health_plants"):
			if not plant.eaten.is_connected(on_eaten):
				plant.eaten.connect(on_eaten)
		_set_task("Eat a health plant")
		while not state.eaten and _uneaten_plants() > 0:
			await _ticked
		_set_task("")
		if state.eaten:
			return
		await _say(["Too slow, they wilted! Here's a fresh batch. Go!"])
		_spawn_health_plants(HEALTH_PLANT_COUNT)


func _uneaten_plants() -> int:
	return get_tree().get_nodes_in_group("health_plants").filter(
		func(p: Node) -> bool: return not p.collected).size()


## Lesson 4: keeps sending lines of trash until the player shoots a whole line
## and collects its powerup. The hint is two beats: shoot the line, then (once
## the power-up is out) collect it — back to the first if it gets away. Dying
## clears the trash and starts over. Returns the powerup type collected.
func _trash_challenge() -> int:
	_clear_pieces()
	_powerup_got = -1
	_died = false
	var respawn_in := 0.0
	var shown := ""
	while _powerup_got < 0:
		var task := TRASH_COLLECT_TASK if _powerup_in_play() else TRASH_TASK
		if task != shown:
			shown = task
			_set_task(task)
		await _ticked
		if _died:
			_died = false
			_clear_trash()
			_set_task("")
			await _say([RETRY_TEXT])
			shown = ""
			respawn_in = 0.0
			continue
		if _trash_in_play():
			respawn_in = TRASH_RESPAWN_DELAY
		else:
			respawn_in -= get_process_delta_time()
			if respawn_in <= 0.0:
				_spawn_trash_line()
				respawn_in = TRASH_RESPAWN_DELAY
	_set_task("")
	return _powerup_got


func _powerup_in_play() -> bool:
	for p in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(p) and not p.is_queued_for_deletion() and _in_play_area(p as Node2D):
			return true
	return false


func _energy_tired() -> bool:
	return _hud.current_energy <= _hud.max_energy * TIRED_ENERGY_FRACTION


## Lesson 1's drop practice: pick up a piece, then let go of it with the drop
## input. Delivering it instead doesn't count — they're sent for another one.
## Lesson 1's drop practice: pick up a piece, then let go of it with the drop
## input. Delivering it instead doesn't count. If they deliver every piece
## lying around, one last piece appears with a warning; delivering that too
## ends their training (back to the main menu). Returns false in that case.
func _drop_practice() -> bool:
	_refill_energy()
	var last_chance := false
	while true:
		if _loose_pieces() == 0 and not GameManager.is_carrying_piece:
			if last_chance:
				await _expel_stubborn_turtle()
				return false
			last_chance = true
			_set_task("")
			_top_up_pieces(1)
			await _say(["Last chance- pick up the piece and drop it with %s." % _drop_label()])
		_set_task("Grab the piece" if last_chance else "Grab another UFO piece")
		while not GameManager.is_carrying_piece and _loose_pieces() > 0:
			await _ticked
		if not GameManager.is_carrying_piece:
			continue
		_set_task("Drop it with %s" % _drop_label())
		var delivered_before := _deliveries
		while GameManager.is_carrying_piece:
			await _ticked
		if _deliveries == delivered_before:
			break
	_set_task("")
	return true


## Lesson 2: free play on the pinball field until they've launched off a
## flipper and bounced off a bumper PINBALL_PRACTICE_COUNT times each — and
## for at least PINBALL_PRACTICE_MIN_SECONDS regardless. No UFO pieces are
## out meanwhile. Missing the counts in PINBALL_PRACTICE_TIMEOUT gets a nudge
## and a second go; missing again ends their training. Returns false then.
func _pinball_practice() -> bool:
	_clear_pieces()
	var counts := {"flip": 0, "bump": 0}
	var on_flip := func() -> void: counts.flip += 1
	var on_bump := func(_bumper: Node) -> void: counts.bump += 1
	GameManager.flipper_launched.connect(on_flip)
	var bumpers := get_tree().get_nodes_in_group("bumpers")
	for bumper in bumpers:
		bumper.player_bounced.connect(on_bump)

	var passed := false
	var played := 0.0
	for attempt in 2:
		if attempt == 1:
			_set_task("")
			await _say(["Launch twice from the flipper and bounce twice off the bumpers. You can do this!"])
		var attempt_time := 0.0
		var shown := ""
		while true:
			var done: bool = counts.flip >= PINBALL_PRACTICE_COUNT and counts.bump >= PINBALL_PRACTICE_COUNT
			if done and played >= PINBALL_PRACTICE_MIN_SECONDS:
				passed = true
				break
			if not done and attempt_time >= PINBALL_PRACTICE_TIMEOUT:
				break
			var task := "Nice! Keep playing..." if done else "Flipper launches %d/%d · Bumper bounces %d/%d" % [
				mini(counts.flip, PINBALL_PRACTICE_COUNT), PINBALL_PRACTICE_COUNT,
				mini(counts.bump, PINBALL_PRACTICE_COUNT), PINBALL_PRACTICE_COUNT]
			if task != shown:
				shown = task
				_set_task(task)
			await _ticked
			played += get_process_delta_time()
			attempt_time += get_process_delta_time()
		if passed:
			break

	GameManager.flipper_launched.disconnect(on_flip)
	for bumper in bumpers:
		if is_instance_valid(bumper):
			bumper.player_bounced.disconnect(on_bump)
	_set_task("")
	if not passed:
		await _expel_stubborn_turtle()
	return passed


## Challenges that don't involve UFO pieces start with none in the level —
## not lying around, and not in the turtle's flippers either.
## Lesson 2: cradle — sit still in the nook of a flipper that's being held up
## — for CRADLE_SECONDS straight. Drifting out, or letting the flipper go,
## starts the count again.
func _cradle_challenge() -> void:
	_clear_pieces()
	var flippers: Array = _pinball.find_children("*", "", true, false).filter(
		func(n: Node) -> bool: return n is FlipperBase)
	_set_task("Cradle for %d seconds: rest on a flipper and hold %s / %s" % [
		int(CRADLE_SECONDS), _flipper_label(true), _flipper_label(false)])
	var cradled := 0.0
	while cradled < CRADLE_SECONDS:
		await _ticked
		cradled = cradled + get_process_delta_time() if _is_cradling(flippers) else 0.0
	_set_task("")


## True while the turtle is resting against a flipper that's held in its
## flipped position (the same test the flipper uses for a cradle release).
func _is_cradling(flippers: Array) -> bool:
	if _turtle.linear_velocity.length() > CRADLE_MAX_SPEED:
		return false
	for flipper in flippers:
		if flipper.is_flipping and flipper.area and flipper.area.overlaps_body(_turtle):
			return true
	return false


## Lesson 2: launch off each of the pinball flippers once. Holding a swim
## direction for SWIM_HOLD_LIMIT_SECONDS straight fails it and wipes the
## progress — swimming is for nudges. A pie by the turtle (SwimPie) drains
## while a direction is held and refills the moment it's let go; flippers
## already done are tinted green.
func _nudge_challenge() -> void:
	_clear_pieces()
	var flippers: Array = _pinball.find_children("*", "", true, false).filter(
		func(n: Node) -> bool: return n is FlipperBase)
	var done := {}
	var on_flip := func() -> void:
		var flipper := GameManager.last_launch_flipper
		if is_instance_valid(flipper) and flipper in flippers:
			done[flipper] = true
			_tint_flipper(flipper, NUDGE_DONE_FLIPPER_TINT)
	GameManager.flipper_launched.connect(on_flip)
	_swim_hold_start()
	var shown := ""
	while done.size() < flippers.size():
		var task := "Launch off all %d flippers (%d/%d) - short nudges only!" % [flippers.size(), done.size(), flippers.size()]
		if task != shown:
			shown = task
			_set_task(task)
		await _ticked
		if _swim_hold_tick():
			_set_task("")
			await _say(["Too much swimming! Let go of %s and drift. Nudge, flip, nudge. From the top!" % _swim_label()])
			for flipper in done:
				_tint_flipper(flipper, Color.WHITE)
			done.clear()
			shown = ""

	GameManager.flipper_launched.disconnect(on_flip)
	_swim_hold_stop()
	for flipper in flippers:
		_tint_flipper(flipper, Color.WHITE)
	_set_task("")


## Puts the swim-hold pie (SwimPie) in the level, hidden until a swim
## direction is held. Poll _swim_hold_tick() every frame while it applies.
func _swim_hold_start() -> void:
	_swim_held = 0.0
	if is_instance_valid(_swim_pie):
		return
	_swim_pie = SwimPie.new()
	_swim_pie.z_index = 50
	_swim_pie.visible = false
	_level.add_child(_swim_pie)


## One frame of the swim-hold limit: the pie by the turtle drains while a swim
## direction is held and refills the moment it's let go. Returns true (and
## resets) when a single hold has lasted SWIM_HOLD_LIMIT_SECONDS.
func _swim_hold_tick() -> bool:
	var move_actions: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
	_swim_held = _swim_held + get_process_delta_time() if _any_pressed(move_actions) else 0.0
	var exhausted := _swim_held >= SWIM_HOLD_LIMIT_SECONDS
	if exhausted:
		_swim_held = 0.0
	_swim_pie.visible = _swim_held > 0.0
	_swim_pie.remaining = 1.0 - _swim_held / SWIM_HOLD_LIMIT_SECONDS
	_swim_pie.global_position = _turtle.global_position + SWIM_PIE_OFFSET
	return exhausted


func _swim_hold_stop() -> void:
	if is_instance_valid(_swim_pie):
		_swim_pie.queue_free()
	_swim_pie = null


## Tints a flipper without touching its alpha (flippers fade themselves).
func _tint_flipper(flipper: CanvasItem, tint: Color) -> void:
	if is_instance_valid(flipper):
		flipper.modulate = Color(tint.r, tint.g, tint.b, flipper.modulate.a)


func _clear_pieces() -> void:
	for p in get_tree().get_nodes_in_group("collectibles"):
		if p is UFOPiece:
			GameManager.remove_carried_piece(p)
			p.queue_free()
	_pieces.clear()


## Pieces lying in the level, free to pick up. A delivered piece lingers for
## its delivery animation but keeps `collected` set, so it doesn't count.
func _loose_pieces() -> int:
	return get_tree().get_nodes_in_group("collectibles").filter(
		func(n: Node) -> bool: return n is UFOPiece and not n.is_carried and not n.collected).size()


func _expel_stubborn_turtle() -> void:
	_set_task("")
	await _say(["You're a stubborn turtle aren't you, wasting everyone's time. Get out of here!"], false)
	await _panel.wait_for_continue(_end_prompt(), true)
	_set_world_paused(false)
	GameManager.load_main_menu()


func _surface_sparkling() -> bool:
	var particles = _turtle.get("rest_particles")
	if particles == null or not particles.emitting:
		return false
	var depth: float = _ocean.get_depth(_turtle.global_position) if _ocean else 0.0
	return depth <= SURFACE_DEPTH


func _flipper_pickup_only(_piece: Node, _collector: Node) -> bool:
	if Time.get_ticks_msec() - GameManager.last_flipper_launch_msec <= FLIPPER_PICKUP_WINDOW_MSEC:
		return true
	_flash_hint("No dives allowed! Flipper hits only.")
	return false


# ── World state ──────────────────────────────────────────────────────────

func _set_bar_pulse(on: bool) -> void:
	_bar_pulse = on
	_bar_pulse_time = 0.0
	if not on and _turtle:
		_turtle.set_float_energy_bar_scale(1.0)


## The HUD's charge sound normally pauses with the level, so it's switched to
## PROCESS_MODE_ALWAYS for the demo and handed back afterwards.
func _set_wall_charge_demo(on: bool) -> void:
	_wall_charge_demo = on
	var sfx: AudioStreamPlayer = _hud.sfx_energy_charge
	if sfx:
		sfx.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
		if not on:
			sfx.stop()
	if not on:
		for wall in get_tree().get_nodes_in_group("dead_walls"):
			wall.end_charge_demo()


## Lets just the flippers run (and respond to input) while the rest of the
## level stays paused.
func _set_flippers_live(on: bool) -> void:
	# find_children()'s type filter only knows built-in classes, not class_name.
	for flipper in _pinball.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is FlipperBase):
		flipper.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT


func _set_hud_meter_pulse(on: bool) -> void:
	_hud_meter_pulse = on
	_hud_meter_pulse_time = 0.0
	if not on and _hud and _hud.energy_container:
		_hud.energy_container.scale = Vector2.ONE


## Pauses the play area — but if the player was just playing (a challenge or
## task has ended), the game keeps running for RESULT_PLAYOUT_SECONDS first
## so they see the result land: the delivery sound and points, the last enemy
## fading out, and so on.
func _pause_after_play() -> void:
	if not _narrating:
		await _wait_seconds(RESULT_PLAYOUT_SECONDS)
	_set_world_paused(true)


func _set_world_paused(paused: bool) -> void:
	_narrating = paused
	get_tree().paused = paused


func _reveal_pinball() -> void:
	_pinball.process_mode = Node.PROCESS_MODE_INHERIT
	_pinball.visible = true
	_fade_in(_pinball)


func _fade_in(node: CanvasItem) -> void:
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 1.0, 0.6)


func _spawn_workshop() -> void:
	if is_instance_valid(_workshop):
		return
	_workshop = WORKSHOP_SCENE.instantiate()
	_workshop.position = WORKSHOP_POS
	_level.add_child(_workshop)
	_fade_in(_workshop)


## Makes sure at least `count` pieces are lying around (carried ones don't
## count), adding new ones at the free spots.
func _top_up_pieces(count: int) -> void:
	_pieces = _pieces.filter(func(p) -> bool: return is_instance_valid(p))
	var loose := _pieces.filter(func(p) -> bool: return not p.is_carried and not p.collected)
	var missing := count - loose.size()
	for spot in PIECE_SPOTS:
		if missing <= 0:
			break
		if _piece_near(spot):
			continue
		var piece: Node2D = UFO_PIECE_SCENE.instantiate()
		piece.position = spot
		_level.add_child(piece)
		_fade_in(piece)
		_pieces.append(piece)
		missing -= 1


## Clears whatever pieces are lying around and puts fresh ones at
## FLIPPER_PIECE_SPOTS (the level is paused for narration while this happens).
func _place_flipper_challenge_pieces() -> void:
	for p in _pieces:
		if is_instance_valid(p) and not p.is_carried:
			p.queue_free()
	_pieces = _pieces.filter(func(p) -> bool: return is_instance_valid(p) and p.is_carried)
	for spot in FLIPPER_PIECE_SPOTS:
		var piece: Node2D = UFO_PIECE_SCENE.instantiate()
		piece.position = spot
		_level.add_child(piece)
		_fade_in(piece)
		_pieces.append(piece)


func _piece_near(spot: Vector2) -> bool:
	for p in _pieces:
		if is_instance_valid(p) and not p.is_carried and not p.collected and p.global_position.distance_to(spot) < 24.0:
			return true
	return false


func _set_piece_filter(filter: Callable) -> void:
	for p in get_tree().get_nodes_in_group("collectibles"):
		if p is UFOPiece:
			(p as UFOPiece).pickup_filter = filter


func _spawn_challenge_piranhas(spots: Array) -> void:
	for spot in spots:
		var p: Node2D = PIRANHA_SCENE.instantiate()
		p.position = spot
		_level.add_child(p)
		_challenge_enemies.append(p)


func _challenge_enemies_gone() -> bool:
	for e in _challenge_enemies:
		if is_instance_valid(e):
			return false
	_challenge_enemies.clear()
	return true


func _clear_challenge_enemies() -> void:
	for e in _challenge_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_challenge_enemies.clear()


## The crocodile and the two sea urchins: added in Lesson 3 (they can't be
## killed). The croc sits out the trash lesson (_remove_croc()); calling this
## again puts back whichever of them is missing.
func _spawn_fixtures() -> void:
	_fixtures = _fixtures.filter(
		func(n: Node) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion())
	var added: Array[Node] = []
	if not _fixtures.any(func(n: Node) -> bool: return n is Crocodile):
		var croc: Crocodile = CROCODILE_SCENE.instantiate()
		croc.patrol_min_x = -70.0
		croc.patrol_max_x = 290.0
		croc.patrol_speed = CROC_PATROL_SPEED
		croc.chase_speed = CROC_CHASE_SPEED
		croc.position = CROC_POS
		_level.add_child(croc)
		added.append(croc)
	if not _fixtures.any(func(n: Node) -> bool: return not (n is Crocodile)):
		for spot in URCHIN_SPOTS:
			var urchin: Node2D = SEA_URCHIN_SCENE.instantiate()
			urchin.position = spot  # before add_child: it anchors to where _ready() finds it
			_level.add_child(urchin)
			added.append(urchin)
	for f in added:
		_fade_in(f)
	_fixtures.append_array(added)


func _remove_croc() -> void:
	for f in _fixtures:
		if is_instance_valid(f) and f is Crocodile:
			f.queue_free()


## Plants grow one per DeadWall, so the layout's wall count caps how many
## actually appear. Tops up to `count` uneaten plants; they keep their normal
## lifetime and wilt as usual.
func _spawn_health_plants(count: int) -> void:
	if not is_instance_valid(_plant_spawner):
		_plant_spawner = HEALTH_PLANT_SPAWNER_SCENE.instantiate()
		_plant_spawner.spawn_thresholds = []
		_level.add_child(_plant_spawner)
	var have := _uneaten_plants()
	# The spawner's cap counts eaten plants still fading out; don't let those
	# block a top-up.
	_plant_spawner.max_simultaneous_plants = count + _plant_spawner.active_plants.size()
	for i in maxi(0, count - have):
		_plant_spawner.spawn_plant_now()


## Removes every health plant in the level and grows exactly `count` new ones.
func _reset_health_plants(count: int) -> void:
	for plant in get_tree().get_nodes_in_group("health_plants"):
		# Out of the group now: a queued plant would still count as uneaten.
		plant.remove_from_group("health_plants")
		plant.queue_free()
	if is_instance_valid(_plant_spawner):
		_plant_spawner.active_plants.clear()
	_spawn_health_plants(count)


func _spawn_trash_line() -> void:
	if is_instance_valid(_trash_seq):
		_trash_seq.queue_free()
	_trash_seq = TRASH_SEQUENCE_SCENE.instantiate()
	_trash_seq.spawn_side = "right"
	_trash_seq.drift_speed = TRASH_DRIFT_SPEED
	_level.add_child(_trash_seq)
	_trash_seq.trigger_sequence(TrashSequence.PatternType.WAVE, TRASH_ITEMS, TRASH_REWARDS.pick_random())


## True while a line is still spawning or any of its trash (or its reward) is
## still in the play area.
func _trash_in_play() -> bool:
	if is_instance_valid(_trash_seq) and _trash_seq.is_active and _trash_seq.items_spawned < _trash_seq.items_in_sequence:
		return true
	for item in get_tree().get_nodes_in_group("trash_items"):
		if is_instance_valid(item) and _in_play_area(item as Node2D):
			return true
	for p in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(p) and _in_play_area(p as Node2D):
			return true
	return false


func _in_play_area(node: Node2D) -> bool:
	var pos := node.global_position
	return pos.x > -104.0 and pos.x < 360.0 and pos.y > -220.0 and pos.y < 200.0


func _clear_trash() -> void:
	if is_instance_valid(_trash_seq):
		_trash_seq.cleanup_trash()
		_trash_seq.queue_free()
	for p in get_tree().get_nodes_in_group("powerups"):
		p.queue_free()


func _setup_exam() -> void:
	_turtle.restore_hearts(99)
	_refill_energy()
	_spawn_fixtures()
	_reset_health_plants(EXAM_START_PLANTS)
	_top_up_pieces(EXAM_PIECES)


## The exam's piranha and air bubble spawners. Both add what they spawn (and
## the piranha spawner its warning ripples / approach sprites) to their own
## parent, so they share a container: freeing it clears the spawners and
## everything they made, even a spawn caught mid-animation.
func _start_exam_spawner() -> void:
	_exam_plant_timer = EXAM_PLANT_INTERVAL
	_exam_trash_timer = EXAM_TRASH_INTERVAL * 0.5
	_exam_spawner = Node2D.new()
	_exam_spawner.name = "ExamSpawns"
	_level.add_child(_exam_spawner)
	var piranhas := PIRANHA_SPAWNER_SCENE.instantiate()
	piranhas.spawn_interval = 7.0
	piranhas.spawn_area_min = Vector2(-70, -40)
	piranhas.spawn_area_max = Vector2(280, 130)
	piranhas.super_piranha_chance = 0.15
	piranhas.frenzy_enabled = false
	_exam_spawner.add_child(piranhas)
	# The first piranha shows up right away instead of a full interval in.
	piranhas.spawn_with_animation()
	var bubbles := AIR_BUBBLE_SPAWNER_SCENE.instantiate()
	bubbles.bubble_scene = AIR_BUBBLE_SCENE
	bubbles.spawn_interval = 10.0
	bubbles.spawn_count_max = 2
	bubbles.random_spawn_min_x = -80.0
	bubbles.random_spawn_max_x = 290.0
	_exam_spawner.add_child(bubbles)


func _stop_exam_spawner() -> void:
	if is_instance_valid(_exam_spawner):
		_exam_spawner.queue_free()
	_exam_spawner = null
	_clear_trash()


## Runs every frame of the exam (from _process()): a health plant every
## EXAM_PLANT_INTERVAL up to EXAM_MAX_PLANTS, and a new line of trash
## EXAM_TRASH_INTERVAL after the last one is gone.
func _exam_tick(delta: float) -> void:
	_exam_plant_timer -= delta
	if _exam_plant_timer <= 0.0:
		_exam_plant_timer = EXAM_PLANT_INTERVAL
		var plants := _uneaten_plants()
		if plants < EXAM_MAX_PLANTS:
			_spawn_health_plants(plants + 1)
	if _trash_in_play():
		_exam_trash_timer = EXAM_TRASH_INTERVAL
	else:
		_exam_trash_timer -= delta
		if _exam_trash_timer <= 0.0:
			_exam_trash_timer = EXAM_TRASH_INTERVAL
			_spawn_trash_line()


func _enable_air() -> void:
	_hud.air_enabled = true
	_hud.current_air = _hud.max_air
	_hud.update_air(_hud.max_air, _hud.max_air)
	if _hud.air_container:
		_hud.air_container.visible = true


func _refill_energy() -> void:
	_hud.current_energy = _hud.max_energy
	_hud.update_energy(_hud.max_energy, _hud.max_energy)


## The HUD's "pieces delivered / needed" counter counts toward a level goal the
## Academy doesn't have, so it's hidden here.
func _hide_hud_piece_counter() -> void:
	var label: Label = _hud.ufo_pieces_label
	if label and label.get_parent() is Control:
		(label.get_parent() as Control).visible = false


# ── Input labels ─────────────────────────────────────────────────────────

func _any_pressed(actions: Array[StringName]) -> bool:
	for a in actions:
		if Input.is_action_pressed(a):
			return true
	return false


## The stubborn-turtle ending's prompt, worded for the device in use.
func _end_prompt() -> String:
	if GameSettings.using_gamepad:
		return "Press A to end academy training"
	if GameSettings.mouse_mode:
		return "Click to end academy training"
	return "Press Enter to end academy training"


## Call to action on the opening banner, worded for the device in use.
func _start_prompt() -> String:
	if GameSettings.using_gamepad:
		return "Press A to start your training"
	if GameSettings.mouse_mode:
		return "Click to start your training"
	return "Press Enter to start your training"


func _swim_label() -> String:
	return "the Left Stick" if GameSettings.using_gamepad else "W A S D"


func _spit_label() -> String:
	if GameSettings.using_gamepad:
		return "the Right Stick"
	if GameSettings.mouse_mode:
		return "the mouse (it spits on its own - Tab turns that on and off)"
	return "I J K L"


func _drop_label() -> String:
	return "X" if GameSettings.using_gamepad else GameSettings.drop_key_label()


func _flipper_label(left: bool) -> String:
	if GameSettings.using_gamepad:
		return "LT" if left else "RT"
	if GameSettings.mouse_mode:
		return "Left Click" if left else "Right Click"
	return "Left Shift" if left else "Right Shift"


func _reward_explanation(reward: int) -> String:
	match reward:
		Powerup.PowerupType.SHIELD:
			return "That's Invincibility! While your hearts are blinking, nothing can hurt you. Be fearless!"
		Powerup.PowerupType.ENERGY_ENDLESS:
			return "That's an Energy Apple! While your energy bar is blinking, swimming is effortless. Dance!"
		Powerup.PowerupType.RAPID_FIRE:
			return "That's Rapid Fire! For a little while, you spit bananas! not literally!"
		Powerup.PowerupType.AIR_RESERVE:
			return "That's an Air Reserve! It fills your air and lets you hold your breath longer. More on breathing later..."
	return "Nice find! Powerups are always worth grabbing."
