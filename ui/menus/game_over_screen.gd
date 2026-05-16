# game_over_screen.gd
extends CanvasLayer
class_name GameOverScreen

## Game Over screen with restart, main menu, and quit options

const _SFX_GAME_OVER   = preload("res://assets/sounds/sfx/game over_1.wav")
const _SFX_MENU_NAV    = preload("res://assets/sounds/sfx/menu nav_1.wav")
const _SFX_MENU_SELECT = preload("res://assets/sounds/sfx/menu select_1.wav")

var _sfx_game_over:   AudioStreamPlayer
var _sfx_nav:         AudioStreamPlayer
var _sfx_select:      AudioStreamPlayer

@onready var game_over_panel = $Control/CenterContainer/PanelContainer
@onready var vbox_container = $Control/CenterContainer/PanelContainer/VBoxContainer
@onready var hint_label = $Control/CenterContainer/PanelContainer/VBoxContainer/HintLabel
@onready var final_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/FinalScoreLabel
@onready var total_score_label = $Control/CenterContainer/PanelContainer/VBoxContainer/TotalScoreLabel
@onready var attempts_label = $Control/CenterContainer/PanelContainer/VBoxContainer/AttemptsLabel
@onready var continue_button = $Control/CenterContainer/PanelContainer/VBoxContainer/ContinueButton
@onready var menu_button = $Control/CenterContainer/PanelContainer/VBoxContainer/MenuButton
@onready var quit_button = $Control/CenterContainer/PanelContainer/VBoxContainer/QuitButton

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
	"Don't we all sparkle yellow during a quick energy recharge?"
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

	if continue_button:
		continue_button.pressed.connect(_on_continue_button_pressed)
		continue_button.focus_entered.connect(func(): _sfx_nav.play())
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
		menu_button.focus_entered.connect(func(): _sfx_nav.play())
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		quit_button.focus_entered.connect(func(): _sfx_nav.play())

func show_game_over(level_score: int, run_total: int):
	"""Display the game over screen with level score and cumulative run total"""
	final_score = level_score

	if hint_label:
		hint_label.text = _pick_hint()

	if final_score_label:
		final_score_label.text = "Level Score: %d" % level_score

	if total_score_label:
		total_score_label.text = "Run Total: %d" % run_total
		total_score_label.visible = run_total > 0

	if attempts_label:
		var c := LevelManager.continue_count
		attempts_label.text = "Continues this run: %d" % c if c > 0 else ""

	var lost_tech := AlienTechManager.remove_oldest_tech()
	if not lost_tech.is_empty() and vbox_container and continue_button:
		var tech_lost_label := Label.new()
		tech_lost_label.text = "%s alien tech lost" % lost_tech
		tech_lost_label.modulate = Color(1.0, 0.45, 0.2)
		tech_lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox_container.add_child(tech_lost_label)
		vbox_container.move_child(tech_lost_label, continue_button.get_index())

	visible = true
	get_tree().paused = true
	if _sfx_game_over:
		_sfx_game_over.play()

	if continue_button:
		continue_button.grab_focus()

func _show_save_prompt(action: Callable):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Save Progress?"
	dialog.dialog_text = "Save and resume at Level %d later?" % LevelManager.current_level_number
	dialog.ok_button_text = "Save"
	dialog.cancel_button_text = "Cancel"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	dialog.add_button("Don't Save", false, "no_save")
	dialog.confirmed.connect(func():
		SaveManager.save_game()
		dialog.queue_free()
		action.call()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(action_name: StringName):
		if action_name == "no_save":
			dialog.queue_free()
			action.call()
	)
	dialog.popup_centered()

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
	if event.is_action_pressed("ui_accept"):
		if continue_button and continue_button.has_focus():
			_on_continue_button_pressed()
		elif menu_button and menu_button.has_focus():
			_on_menu_pressed()
		elif quit_button and quit_button.has_focus():
			_on_quit_pressed()
