# academy_director.gd
extends Node
class_name AcademyDirector

## Runs the UFO Repair Turtle Academy course: the intro, five lessons and the
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

enum Outcome { DONE, DIED }

const LESSONS: Array[String] = [
	"Deep Ocean, meet Deep Space",
	"The Ancients",
	"The Haters",
	"Trash",
	"The Exam",
]

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
const FLIPPER_PIECE_SPOTS: Array[Vector2] = [Vector2(-18, 150), Vector2(222, 150)]
const PIRANHA_SPOTS: Array[Vector2] = [Vector2(0, -30), Vector2(210, -30), Vector2(0, 110), Vector2(210, 110)]
const SUPER_SPEED_PIRANHA_SPOT := Vector2(104, 10)
# const MIXED_PIRANHA_SPOTS: Array[Vector2] = [Vector2(20, 110), Vector2(200, 110)]
const CROC_POS := Vector2(220, -126)
## The Academy croc is the normal croc at ~75% speed — a lesson, not a boss
## fight. Both speeds scale together (defaults: patrol 80, chase 150) so the
## chase stays clearly faster than the patrol; the croc's own close-range
## slowdown (chase_slowdown_range) still applies on top.
const CROC_PATROL_SPEED := 60.0
const CROC_CHASE_SPEED := 115.0
const URCHIN_SPOTS: Array[Vector2] = [Vector2(-22, -5), Vector2(230, -5)]

const SWIM_PRACTICE_SECONDS := 5.0
## After the first surface sparkle, the lesson waits this long before moving on
## so the player actually sees (and hears) it. A flat delay, since energy
## refills too fast at the surface to require sparkling for a while.
const SURFACE_WATCH_SECONDS := 1.5
const SURFACE_DEPTH := 24.0
const SPIT_PRACTICE_COUNT := 10
const PIRANHA_CHALLENGE_COUNT := 4
const HEALTH_PLANT_COUNT := 6
const EXAM_HEALTH_PLANTS := 4
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
const TRASH_TASK := "Shoot a group of trash for a power-up!"
## Lesson 2's pinball practice: launches off flippers and bounces off bumpers
## needed, the minimum time it runs even once they're done, and how long each
## of the two attempts gets before the nudge / the stubborn ending.
const PINBALL_PRACTICE_COUNT := 2
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
## Exam: delivered pieces that were picked up off a flipper launch (see
## _record_pickup() / _on_piece_delivered()).
var _exam_flipper_pieces := 0
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

var _task_hint := ""
var _flash_token := 0
var _any_input := false


func _ready() -> void:
	_level.player_respawned.connect(func() -> void: _died = true)
	LevelManager.piece_delivered.connect(_on_piece_delivered)
	# Pinball arrives in Lesson 2. Disabled rather than just hidden, so the
	# flippers don't flip (or click) on input and nothing collides.
	_pinball.visible = false
	_pinball.process_mode = Node.PROCESS_MODE_DISABLED
	_panel.set_agenda(LESSONS)
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
		# Emitted from inside the workshop's delivery, before the piece leaves
		# carried_pieces — so the delivered piece is still in that list.
		for piece in GameManager.carried_pieces:
			if is_instance_valid(piece) and piece.get_meta(&"flipper_pickup", false):
				_exam_flipper_pieces += 1


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

	await _say(["Well done! They are damn heavy right?? I guess aliens haven't discovered titanium yet. In a pinch, drop a piece you hold with %s. Dive down to grab another and practice dropping it." % _drop_label()], false)
	if not await _drop_practice():
		return false

	_complete_lesson(0)
	await _say(["Magnifique! You've completed lesson 1!"])
	return true


func _lesson_2() -> bool:
	await _begin_lesson(1)
	await _say(["We don't know who built pinball long ago. We can only purr in awe and gratitude that they did. It makes the job of UFO repair a heck of a lot easier."])

	_reveal_pinball()
	await _say(["Behold! Thanks to pinball, turtles can repair UFOs without fainting from exhaustion! It's really quite simple. Use %s to flip leftward flippers, and %s to flip rightward ones. Try it!" % [_flipper_label(true), _flipper_label(false)]], false)
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

	await _say(["Now use a flipper to pick up a UFO piece. I'm only gonna let you hold it if you got it from a flipper hit, no dives allowed! Bring it to your workshop once you've got it."])
	_place_flipper_challenge_pieces()
	_set_piece_filter(_flipper_pickup_only)
	_set_task("Flipper into a piece, then deliver it")
	await _wait_for_delivery()
	_set_piece_filter(Callable())
	_set_task("")

	await _say(["Excellent! You probably noticed a few things while you were at it, but I'll go over them for your notes."])
	_set_wall_charge_demo(true)
	await _say(["Touching pinball flippers and walls ALSO refills energy fast, just like the surface does."])
	_set_wall_charge_demo(false)
	_complete_lesson(1)
	await _say(["When you shoot off flippers and bumpers you launch at super speed! At that speed nothing can hurt you. In fact, it's you doing the hurting! Which brings us to.. (oh you passed the lesson by the way)"])
	return true


func _lesson_3() -> void:
	await _begin_lesson(2)
	await _say(["Haters. It's really just fear. Fear of the unknown. Fear of different amounts of fingers. Who knows? But there's plenty of haters out there. They're not so bad though, besides the US governm.. uh.. never mind.. um.. yeah, So you have 2 weapons at your disposal. The first is your spit."])

	_turtle.mouse_fire_enabled = true
	await _say(["Spit your spit with %s. You can spit in any direction you like. Try it!" % _spit_label()], false)
	_set_task("Spit %d times" % SPIT_PRACTICE_COUNT)
	_spits = 0
	while _spits < SPIT_PRACTICE_COUNT:
		await _ticked
	_set_task("")

	# Enemy challenges wait for the continue press after their intro, so the
	# player isn't reading and fighting at the same time.
	await _say(["Got a hater piranha on your tail? Just spit! If they do get you, you'll lose a heart. You only have 7. But don't stress, practice. Spit all these piranhas goodnight."])
	await _enemy_challenge("Spit all %d piranhas goodnight" % PIRANHA_CHALLENGE_COUNT,
		func() -> void: _spawn_challenge_piranhas(PIRANHA_SPOTS.slice(0, PIRANHA_CHALLENGE_COUNT)))

	await _say(["Your other weapon? I already told you.. Super Speed! Kill this next piranha using only super speed from pinball flippers or bumpers. No spitting allowed!"])
	_turtle.shoot_locked = true
	await _enemy_challenge("Super speed only - no spitting!",
		func() -> void: _spawn_challenge_piranhas([SUPER_SPEED_PIRANHA_SPOT]))
	_turtle.shoot_locked = false

	await _say(["Well done. Now some more bad news. Not everything is vulnerable to spit or super speed. Crocodiles and sea urchins, for instance. Simply not bothered."])
	_spawn_fixtures()
	await _say(["See what I mean for yourself. Go take a damage from the crocodile and a sea urchin. But don't die. You still haven't paid."])
	await _hazard_hit_challenge()

	await _say(["Scary, right!? Sorry about that, but I had to for your own sake. Take a breath, then stroke your ego and kill a few more piranhas, it'll help you relax, I promise!"])
	await _enemy_challenge("Take out the 4 piranhas",
		func() -> void: _spawn_challenge_piranhas(PIRANHA_SPOTS))

	await _say(["You live! Well done. After taking a beating, its crucial to keep an eye out for plants."])
	_spawn_health_plants(HEALTH_PLANT_COUNT)
	await _say(["You eat them to gain health. Eat one now, but don't dilly dally too long, they don't live forever."])
	await _plant_challenge()
	_complete_lesson(2)
	await _say(["Delicious. Lesson 3 complete!"])


func _lesson_4() -> void:
	await _begin_lesson(3)
	await _say([" I don't know what's worse, haters or trash. Thankfully, turtle spit deals with both. You'll see clusters of trash floating by. Shoot them all and the ocean will thank you with a power-up."])
	await _say(["The ocean also grants you points when you clean up trash, and good things come from getting points, trust me. Give it a shot- Try to shoot a whole line of trash and collect the power-up."], false)
	var reward := await _trash_challenge()
	# Same wind-down as any finished challenge, then explain the power-up, then
	# let them actually enjoy it before the lesson carries on.
	await _say([_reward_explanation(reward)])
	_set_task("Enjoy your power-up!")
	await _wait_seconds(REWARD_PLAY_SECONDS)
	_set_task("")
	_complete_lesson(3)
	await _say(["Very good. FYI, there's also big trash bags.. these contain alien technologies, which are super strong power-ups. But that's the advanced course. I'll let you learn that on your own. Lesson done! It's exam time!"])


func _lesson_5() -> void:
	await _begin_lesson(4)
	await _say(["Pass this exam and you'll be certified!"])
	await _say(["It's simple- You just gotta bring two UFO pieces from the ocean floor to the UFO workshop without dying. Oh, you've gotta use the flippers to grab at least one of the UFO pieces, too. When you're ready, go ahead and start. No cheating!"], false)

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

		_exam_flipper_pieces = 0
		_set_piece_filter(_record_pickup)
		_start_exam_spawner()
		var outcome := Outcome.DONE
		for delivered in EXAM_DELIVERIES:
			_set_task("Deliver %d pieces (%d/%d) - one off a flipper!" % [EXAM_DELIVERIES, delivered, EXAM_DELIVERIES])
			outcome = await _wait_for_delivery()
			if outcome != Outcome.DONE:
				break
		_set_task("")
		_stop_exam_spawner()
		_set_piece_filter(Callable())
		if outcome == Outcome.DONE and _exam_flipper_pieces > 0:
			break
		_clear_challenge_enemies()
		if outcome == Outcome.DIED:
			await _say([RETRY_TEXT], false)
		else:
			await _say(["No cheating! At least one of those pieces had to come off a flipper launch. Let's try that again."], false)

	await _pause_after_play()
	_complete_lesson(4)
	SaveManager.set_academy_certified()
	_panel.set_title("CERTIFIED!", Color(1.0, 0.85, 0.0))
	_panel.set_lesson_title("Graduation")
	_panel.clear_dialogue()
	_panel.set_hint("")
	await _panel.play_banner("CERTIFIED!", "UFO Repair Turtle")
	await _say(["Congratulations! You are now a Certified UFO Repair Turtle!"])
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
	_panel.set_lesson_title("Lesson %d: %s" % [index + 1, LESSONS[index]])
	_panel.set_agenda_state(index, index)
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


func _wait_for_delivery() -> Outcome:
	var target := _deliveries + 1
	return await _wait_until(func() -> bool: return _deliveries >= target)


## Runs an enemy fight until every enemy it spawned is gone. On death the
## fight is cleared, the instructor cheers them on, and it starts over.
func _enemy_challenge(task: String, spawn: Callable) -> void:
	while true:
		spawn.call()
		_set_task(task)
		var outcome := await _wait_until(_challenge_enemies_gone)
		_set_task("")
		if outcome == Outcome.DONE:
			return
		_clear_challenge_enemies()
		await _say([RETRY_TEXT])


## Lesson 3: get hurt once by the crocodile and once by a sea urchin, to feel
## that they can't be beaten. The hint tracks which is still missing. Dying
## resets both and starts over.
func _hazard_hit_challenge() -> void:
	var hit := {"croc": false, "urchin": false}
	var on_damaged := func(source: String) -> void:
		if source.ends_with(" a crocodile"):
			hit.croc = true
		elif source.ends_with(" a sea urchin"):
			hit.urchin = true
	_turtle.damaged.connect(on_damaged)
	while not (hit.croc and hit.urchin):
		var shown := ""
		_died = false
		while not (hit.croc and hit.urchin):
			var task := "Take a hit from the croc and a sea urchin"
			if hit.croc:
				task = "Now take a hit from a sea urchin"
			elif hit.urchin:
				task = "Now take a hit from the croc"
			if task != shown:
				shown = task
				_set_task(task)
			await _ticked
			if _died:
				break
		if _died and not (hit.croc and hit.urchin):
			hit.croc = false
			hit.urchin = false
			_set_task("")
			await _say([RETRY_TEXT])
	_turtle.damaged.disconnect(on_damaged)
	_set_task("")


## Lesson 3: eat a health plant before they all wilt. Plants keep their
## normal lifetime here; if every one is gone uneaten, a fresh batch grows
## and the challenge starts over.
func _plant_challenge() -> void:
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
## and collects its powerup. Dying clears the trash and starts over. Returns
## the powerup type collected.
func _trash_challenge() -> int:
	_powerup_got = -1
	_set_task(TRASH_TASK)
	_died = false
	var respawn_in := 0.0
	while _powerup_got < 0:
		await _ticked
		if _died:
			_died = false
			_clear_trash()
			_set_task("")
			await _say([RETRY_TEXT])
			_set_task(TRASH_TASK)
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
	_clear_loose_pieces()
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


func _clear_loose_pieces() -> void:
	for p in get_tree().get_nodes_in_group("collectibles"):
		if p is UFOPiece and not p.is_carried:
			p.queue_free()
	_pieces = _pieces.filter(func(p) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())


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


## Exam pickups: always allowed, but each pickup notes on the piece whether
## it came off a recent flipper launch (re-picking a dropped piece re-notes).
func _record_pickup(piece: Node, _collector: Node) -> bool:
	piece.set_meta(&"flipper_pickup", _flipper_launch_recent())
	return true


func _flipper_launch_recent() -> bool:
	return Time.get_ticks_msec() - GameManager.last_flipper_launch_msec <= FLIPPER_PICKUP_WINDOW_MSEC


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


## The crocodile and the two sea urchins: added in Lesson 3 and kept for the
## rest of the course (they can't be killed).
func _spawn_fixtures() -> void:
	_fixtures = _fixtures.filter(func(n: Node) -> bool: return is_instance_valid(n))
	if not _fixtures.is_empty():
		return
	var croc: Crocodile = CROCODILE_SCENE.instantiate()
	croc.patrol_min_x = -70.0
	croc.patrol_max_x = 290.0
	croc.patrol_speed = CROC_PATROL_SPEED
	croc.chase_speed = CROC_CHASE_SPEED
	croc.position = CROC_POS
	_level.add_child(croc)
	_fixtures.append(croc)
	for spot in URCHIN_SPOTS:
		var urchin: Node2D = SEA_URCHIN_SCENE.instantiate()
		urchin.position = spot  # before add_child: it anchors to where _ready() finds it
		_level.add_child(urchin)
		_fixtures.append(urchin)
	for f in _fixtures:
		_fade_in(f)


## Plants grow one per DeadWall, so the layout's wall count caps how many
## actually appear. Tops up to `count` uneaten plants; they keep their normal
## lifetime and wilt as usual.
func _spawn_health_plants(count: int) -> void:
	if not is_instance_valid(_plant_spawner):
		_plant_spawner = HEALTH_PLANT_SPAWNER_SCENE.instantiate()
		_plant_spawner.spawn_thresholds = []
		_level.add_child(_plant_spawner)
	_plant_spawner.max_simultaneous_plants = count
	var have := _uneaten_plants()
	for i in maxi(0, count - have):
		_plant_spawner.spawn_plant_now()


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
	_spawn_health_plants(maxi(EXAM_HEALTH_PLANTS, get_tree().get_nodes_in_group("health_plants").size()))
	_top_up_pieces(EXAM_PIECES)


## The exam's piranha and air bubble spawners. Both add what they spawn (and
## the piranha spawner its warning ripples / approach sprites) to their own
## parent, so they share a container: freeing it clears the spawners and
## everything they made, even a spawn caught mid-animation.
func _start_exam_spawner() -> void:
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
			return "That's Rapid Fire! For a little while you spit bananas, not literally!"
		Powerup.PowerupType.AIR_RESERVE:
			return "That's an Air Reserve! It lets you hold your breath longer. More on breathing later..."
	return "Nice find! Powerups are always worth grabbing."
