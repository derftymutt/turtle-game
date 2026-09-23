# game_over_screen.gd
extends CanvasLayer
class_name GameOverScreen

## Game Over screen with restart, main menu, and quit options

const _SFX_GAME_OVER   = preload("res://assets/sounds/sfx/game over_1.ogg")
const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.ogg")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.ogg")

var _sfx_game_over:   AudioStreamPlayer
var _sfx_nav:         AudioStreamPlayer
var _sfx_select:      AudioStreamPlayer

@onready var game_over_panel = $Control/CenterContainer/PanelContainer
@onready var vbox_container = $Control/CenterContainer/PanelContainer/VBoxContainer
@onready var options_column = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn
@onready var game_over_label = $Control/CenterContainer/PanelContainer/VBoxContainer/GameOverLabel
@onready var death_cause_label = $Control/CenterContainer/PanelContainer/VBoxContainer/DeathCauseLabel
@onready var hint_label = $Control/CenterContainer/PanelContainer/VBoxContainer/HintLabel
@onready var final_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var total_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/TotalScoreLabel
@onready var attempts_label = $Control/CenterContainer/PanelContainer/VBoxContainer/AttemptsLabel
@onready var continue_button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/ContinueButton
@onready var menu_button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/MenuButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/OptionsColumn/QuitButton
@onready var _control: Control = $Control

# Plain-text options marked by a sliding turtle indicator + green text
# shine, same look as the main menu (see ui/shared/turtle_option_list.gd).
var _option_list: TurtleOptionList

# Mouse mode puts the flippers on LMB/RMB, so a player mid-flip when this
# screen pops up would otherwise click whatever button is under the cursor.
const _CLICK_ARM_DELAY_MSEC: int = 500
var _shown_msec: int = 0

var final_score: int = 0

const HINTS: Array[String] = [
	"UFO Parts are heavy. Drop them if you need to.",
	"You won't keep holding a UFO part if you take damage",
	"Recover energy sparkly fast resting on pinball parts (and your workshop)",
	"Reincarnation only remembers your most recent alien tech",
	"Hold your breath longer with air bubble powerups",
	"Crocodiles just don't wanna die do they",
	"Clean up the ocean for points",
	"The ocean is so happy those plastic bottles are gone, she'll give you a powerup",
	"Alien tech encrusted in trash appear every 200 points",
	"A clean ocean allows health plants to grow",
	"Turtles eat apples",
	"Pinball flippers get the job done",
	"Nothing can stop you in super speed",
	"It's tiring to swim. Swim smart!",
	"What's in the sky?",
	"Crabs make babies if left alone",
	"Sea urchins can't be bothered",
	"Bumper pogo",
	"It's a dance",
	"Turtles never run out of saliva",
	"Relax and let the environment do the work",
	"Breathe",
	"Crocodiles love a good race",
	"You're the only turtle you know that can get from surface to sea floor in one full energy sprint",
	"You're the turtle, not the hare, after all",
	"Listen to your lungs!",
	"Why's the US military so uptight about aliens?",
	"Trying a variety of alien techs will gain you wisdom",
	"Ocean currents weeeeeeeee!",
	"Your name is Flip for a reason",
	"The surface is invigorating",
	"Don't we all sparkle yellow during a quick energy recharge?",
	"Alien tech's are unstable. They heat up and then fry.",
	"You never know what you'll find in the trash."
]

static var _shown_hint_indices: Array[int] = []

static func _pick_hint() -> String:
	if _shown_hint_indices.size() >= HINTS.size():
		_shown_hint_indices.clear()
	var remaining: Array[int] = []
	for i in range(HINTS.size()):
		if not _shown_hint_indices.has(i):
			remaining.append(i)
	var idx: int = remaining[randi() % remaining.size()]
	_shown_hint_indices.append(idx)
	return HINTS[idx]

func _ready():
	add_to_group("game_over_screen")
	visible = false

	_sfx_game_over = AudioStreamPlayer.new()
	_sfx_game_over.stream = _SFX_GAME_OVER
	_sfx_game_over.volume_db = 0.0
	add_child(_sfx_game_over)

	_sfx_nav = AudioStreamPlayer.new()
	_sfx_nav.stream = _SFX_MENU_NAV
	_sfx_nav.volume_db = 0.0
	add_child(_sfx_nav)

	_sfx_select = AudioStreamPlayer.new()
	_sfx_select.stream = _SFX_MENU_SELECT
	_sfx_select.volume_db = 0.0
	add_child(_sfx_select)

	_option_list = TurtleOptionList.new()
	add_child(_option_list)
	_option_list.attach(_control)

	if continue_button:
		continue_button.pressed.connect(_on_continue_button_pressed)
		continue_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(continue_button)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
		menu_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(menu_button)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(func(): _sfx_nav.play())
		_option_list.wire_option(quit_button)

func show_game_over(level_score: int, run_total: int, death_cause: String = ""):
	"""Display the game over screen with level score and cumulative run total"""
	final_score = level_score

	if game_over_label:
		game_over_label.text = "OUCH"

	if death_cause_label:
		if death_cause.is_empty():
			death_cause_label.visible = false
		else:
			death_cause_label.visible = true
			death_cause_label.text = "%s%s." % [death_cause[0].to_upper(), death_cause.substr(1)]

	if hint_label:
		hint_label.text = _pick_hint()

	if final_score_label:
		final_score_label.text = "Level Score: %s" % FormatUtil.comma_int(level_score)

	if total_score_label:
		total_score_label.text = "Run Total: %s" % FormatUtil.comma_int(run_total)
		total_score_label.visible = run_total > 0

	if attempts_label:
		var c := LevelManager.continue_count
		attempts_label.text = "Continues this run: %d" % c if c > 0 else ""

	var lost_tech := AlienTechManager.remove_oldest_tech()
	if not lost_tech.is_empty() and vbox_container and options_column:
		var tech_lost_label := Label.new()
		tech_lost_label.text = "%s alien tech lost" % lost_tech
		tech_lost_label.modulate = Color(1.0, 0.45, 0.2)
		tech_lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox_container.add_child(tech_lost_label)
		# OptionsColumn (not continue_button) is now the direct vbox_container
		# child that sits where the buttons used to — the buttons themselves
		# live one level deeper inside it.
		vbox_container.move_child(tech_lost_label, options_column.get_index())

	visible = true
	get_tree().paused = true
	_shown_msec = Time.get_ticks_msec()
	if _sfx_game_over:
		_sfx_game_over.play()

	# This CanvasLayer's Control subtree doesn't get a real layout pass while
	# visible=false, so a button's get_global_rect() is still stale for a
	# frame or two after it flips true — wait for layout to actually settle
	# before positioning the turtle indicator against it (same fix as
	# pause_menu.gd's _open()).
	await get_tree().process_frame
	await get_tree().process_frame
	if continue_button:
		continue_button.grab_focus()

func _show_save_prompt(action: Callable):
	# The tutorial isn't part of level progression — there's nothing to save.
	if LevelManager.is_tutorial:
		action.call()
		return
	var dialog := TurtleConfirmDialog.new()
	add_child(dialog)
	# A multi-line lambda nested inside an array/dict literal confuses
	# GDScript's indentation parser ("unindent doesn't match" at the dict's
	# closing brace) — define it as a plain local first instead.
	var do_save := func():
		SaveManager.save_game()
		action.call()
	dialog.show_dialog(
		"Save and resume at Level %d later?" % LevelManager.current_level_number,
		[
			{"text": "Save", "callback": do_save},
			{"text": "Don't Save", "callback": action},
			{"text": "Cancel", "is_cancel": true},
		],
		"Save Progress?"
	)

func _on_continue_button_pressed():
	if _sfx_select:
		_sfx_select.play()
	get_tree().paused = false
	LevelManager.restart_current_level()

func _on_menu_pressed():
	if _sfx_select:
		_sfx_select.play()
	_show_save_prompt(func():
		get_tree().paused = false
		GameManager.load_main_menu()
	)

func _on_quit_pressed():
	if _sfx_select:
		_sfx_select.play()
	_show_save_prompt(func():
		get_tree().quit()
	)

func _input(event):
	if not visible:
		return
	if event is InputEventMouseButton and Time.get_ticks_msec() - _shown_msec < _CLICK_ARM_DELAY_MSEC:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		if continue_button and continue_button.has_focus():
			_on_continue_button_pressed()
		elif menu_button and menu_button.has_focus():
			_on_menu_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()
