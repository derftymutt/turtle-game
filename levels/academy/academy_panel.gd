# academy_panel.gd
extends CanvasLayer
class_name AcademyPanel

## The Academy's dedicated info zone: a menu panel filling the left third of the
## screen, from just under the HUD to the bottom edge, ending where the ocean's
## left wall begins. Shows the agenda (one checkbox per lesson), the active
## lesson title, and the instructor's dialogue, typed out a letter at a time.
##
## The panel's top edge tracks the bottom of the HUD's top bar (which grows when
## alien tech slots appear), so the two never overlap.
##
## Dialogue: say() types one or more chunks of text. Each chunk is split into
## as many pages as it needs to fit the body area (whole sentences per page),
## and every page waits for the continue input — Enter or gamepad A. Space is
## deliberately not used: it drops a piece in keyboard-only mode and is a tech
## slot in mouse mode. Runs with PROCESS_MODE_ALWAYS, since the director
## pauses the play area while the panel talks.

signal _continued

## Screen-space x where the play area starts (the left ocean wall's outer edge).
## Must match the OceanWallLeft / BoundaryLeft position in academy.tscn.
const PLAY_AREA_LEFT_X: float = 208.0
const GUTTER: float = 4.0

const TYPE_CHARS_PER_SECOND := 45.0
const TYPE_SENTENCE_PAUSE := 0.25
const TYPE_CLAUSE_PAUSE := 0.12
const TYPE_START_DELAY := 0.2
## The continue press can't land until a page has been fully shown this long,
## so a press meant to skip the typing doesn't also turn the page.
const CONTINUE_ARM_SECONDS := 0.25

const CONTINUE_HINT := "Enter / A  →"
const AGENDA_BOTTOM_SPACE := 10.0
const HINT_BLINK_PERIOD_MSEC: int = 300
const HINT_BLINK_LOW_ALPHA: float = 0.35
## Experiment: the task hint is also shown, bigger, dead centre of the play
## area — across it horizontally, and midway between the ocean surface and the
## sea floor (world y). Set PLAY_AREA_HINT_ENABLED false to go back to the
## panel line only.
const PLAY_AREA_HINT_ENABLED := true
const PLAY_AREA_HINT_FONT_SIZE := 16
const PLAY_AREA_HINT_SURFACE_Y := -126.0
const PLAY_AREA_HINT_FLOOR_Y := 164.0
const PLAY_AREA_HINT_SIDE_MARGIN := 12.0
const PLAY_AREA_HINT_HEIGHT := 60.0

const _DONE_COLOR := Color(0.4, 1.0, 0.45, 1.0)
const _CURRENT_COLOR := Color(1.0, 0.85, 0.0, 1.0)
const _TODO_COLOR := Color(1, 1, 1, 0.7)
const _AGENDA_FONT_SIZE := 12

## The instructor sprite (Instructor, under the divider) is a horizontal strip
## of this many frames. Frame 0 is the resting pose; while dialogue is typing
## the frames cycle at INSTRUCTOR_TALK_FPS so the instructor looks like they're
## talking.
const INSTRUCTOR_FRAMES := 2
## The instructor's voice: one long babble, looped, picked up at a random
## point every time they start talking and stopped when the typing ends —
## in step with the talking animation. Short fades hide the cut points.
const INSTRUCTOR_VOICE_PATH := "res://assets/sounds/sfx/instructor_vox.ogg"
const INSTRUCTOR_VOICE_DB := -4.0
const INSTRUCTOR_VOICE_FADE_SECONDS := 0.08
const INSTRUCTOR_TALK_FPS := 6.0

# ── Lesson banner (play_banner()) ──
const _BANNER_SFX := preload("res://assets/sounds/sfx/deliver ufo piece.ogg")
## Lesson banners (play_banner(..., lesson_sound = true)) play this instead;
## loaded at runtime, so a missing file just falls back to _BANNER_SFX.
const _LESSON_BANNER_SFX_PATH := "res://assets/sounds/sfx/lesson_banner.ogg"
## Banners get their own CanvasLayer this high, above the panel, HUD and pause
## menu (8), so nothing in the level draws over them.
const BANNER_LAYER := 20
const _BANNER_HEIGHT := 70.0
## Gap between the banner and each side of the screen — it's a long, narrow
## panel inside the screen, not a band running off both edges.
const _BANNER_SIDE_INSET := 32.0
## The banner's own pixel-art opaque panel (ui/panel_base_banner_opaque.png).
const _BANNER_PANEL_STYLE := &"PanelBaseBannerOpaque"
const _BANNER_EDGE_COLOR := Color(1.0, 0.85, 0.0, 1.0)
const _BANNER_TITLE_COLOR := Color(0.6, 0.8980392, 0.3137255, 1.0)

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/VBox/Title
@onready var _agenda_header: Label = $Panel/VBox/AgendaHeader
@onready var _agenda: VBoxContainer = $Panel/VBox/Agenda
@onready var _separator: Control = $Panel/VBox/Separator
@onready var _instructor: TextureRect = $Panel/VBox/Separator/Instructor
@onready var _lesson_title: Label = $Panel/VBox/LessonTitle
@onready var _body: RichTextLabel = $Panel/VBox/Body
@onready var _hint: Label = $Panel/VBox/Hint

var _hud_bar: Control = null
var _agenda_rows: Array = []  # [{check: AgendaCheck, label: Label}]

var _typing := false
var _type_budget := 0.0
var _type_cost := 0.0
var _type_text := ""
var _waiting_continue := false
var _continue_arm := 0.0
var _task_hint := ""
var _instructor_frames: AtlasTexture = null
var _instructor_frame := 0
var _voice: AudioStreamPlayer = null
var _voice_gain := 0.0  # 0..1, eased towards 1 while typing
var _talk_time := 0.0
var _reveal_active := false
var _click_continues := false
var _reveal_skip := false
var _banner_active := false
var _banner_skip := false
var _banner_hint: Label = null  # the banner's blinking "Enter / A" prompt
var _play_hint: Label = null  # the task hint again, over the play area


## Pixel-art checkbox for an agenda row: an outlined square, filled with a
## green check mark once the lesson is done.
class AgendaCheck extends Control:
	var checked := false:
		set(value):
			checked = value
			queue_redraw()
	var color := Color.WHITE:
		set(value):
			color = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(9, 9)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_rect(Rect2(0.5, 0.5, 8, 8), color, false, 1.0)
		if checked:
			draw_polyline(PackedVector2Array([Vector2(2, 4), Vector2(4, 6.5), Vector2(8, 1)]), _DONE_COLOR, 1.5)


func _ready() -> void:
	_panel.offset_left = GUTTER
	_panel.offset_right = PLAY_AREA_LEFT_X - GUTTER
	_panel.offset_bottom = -GUTTER
	_body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_body.text = ""
	_hint.text = ""
	if PLAY_AREA_HINT_ENABLED:
		_play_hint = Label.new()
		_play_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_play_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_play_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_play_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_play_hint.add_theme_font_size_override("font_size", PLAY_AREA_HINT_FONT_SIZE)
		_play_hint.add_theme_color_override("font_color", _hint.get_theme_color("font_color"))
		_play_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		_play_hint.add_theme_constant_override("outline_size", 4)
		add_child(_play_hint)
	# The header starts hidden — reveal_header() types it out when the
	# Academy opens, rather than everything appearing at once.
	for label: Label in [_title, _agenda_header]:
		label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		label.visible_characters = 0
	_separator.modulate.a = 0.0
	_setup_instructor()
	_setup_voice()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		_hud_bar = hud.get_node_or_null("MarginContainer")
	if _hud_bar:
		_hud_bar.resized.connect(_fit_under_hud)
	# HUD layout settles a frame after _ready.
	_fit_under_hud.call_deferred()


## Shows the sheet one frame at a time through an AtlasTexture window.
func _setup_instructor() -> void:
	var sheet := _instructor.texture
	if sheet == null:
		return
	var frame_size := Vector2(sheet.get_width() / float(INSTRUCTOR_FRAMES), sheet.get_height())
	_instructor_frames = AtlasTexture.new()
	_instructor_frames.atlas = sheet
	_instructor_frames.region = Rect2(Vector2.ZERO, frame_size)
	_instructor.texture = _instructor_frames


## Talking (cycling frames) only while dialogue is typing; frame 0 otherwise.
## load(), not preload(): a missing or not-yet-imported file just means a
## silent instructor rather than a script that won't parse.
func _setup_voice() -> void:
	var stream := load(INSTRUCTOR_VOICE_PATH) as AudioStream
	if stream == null:
		push_warning("AcademyPanel: no instructor voice at %s" % INSTRUCTOR_VOICE_PATH)
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_voice = AudioStreamPlayer.new()
	_voice.stream = stream
	add_child(_voice)


## Fades the voice in from a random point when typing starts and out (then
## stops it) when typing ends.
func _update_voice(delta: float) -> void:
	if _voice == null:
		return
	_voice.stream_paused = false
	if _typing and not _voice.playing:
		_voice_gain = 0.0
		_voice.play(randf() * _voice.stream.get_length())
	var step := delta / INSTRUCTOR_VOICE_FADE_SECONDS
	_voice_gain = move_toward(_voice_gain, 1.0 if _typing else 0.0, step)
	if _voice.playing:
		if _voice_gain <= 0.0:
			_voice.stop()
		else:
			_voice.volume_db = INSTRUCTOR_VOICE_DB + linear_to_db(_voice_gain)


func _animate_instructor(delta: float) -> void:
	if _instructor_frames == null:
		return
	var frame := 0
	if _typing:
		_talk_time += delta
		frame = int(_talk_time * INSTRUCTOR_TALK_FPS) % INSTRUCTOR_FRAMES
	else:
		_talk_time = 0.0
	if frame != _instructor_frame:
		_instructor_frame = frame
		var region := _instructor_frames.region
		region.position.x = region.size.x * frame
		_instructor_frames.region = region


func _fit_under_hud() -> void:
	var top := 48.0
	if _hud_bar and _hud_bar.is_visible_in_tree():
		top = _hud_bar.get_global_rect().end.y
	_panel.offset_top = top


# ── Agenda ───────────────────────────────────────────────────────────────

func set_agenda(lesson_titles: Array) -> void:
	for child in _agenda.get_children():
		child.queue_free()
	_agenda_rows.clear()
	for i in lesson_titles.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var check := AgendaCheck.new()
		var label := Label.new()
		label.text = "%d. %s" % [i + 1, lesson_titles[i]]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", _AGENDA_FONT_SIZE)
		label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		label.visible_characters = 0  # typed in by reveal_header()
		check.modulate.a = 0.0
		row.add_child(check)
		row.add_child(label)
		_agenda.add_child(row)
		_agenda_rows.append({"check": check, "label": label})
	# Empty space under the last row: pushes the divider down so the
	# instructor, who stands on it beside the agenda, isn't squeezed.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, AGENDA_BOTTOM_SPACE)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_agenda.add_child(spacer)
	set_agenda_state(-1, 0)


## current: index of the lesson in progress (-1 = none); done_count: how many
## lessons (from the top) are complete.
func set_agenda_state(current: int, done_count: int) -> void:
	for i in _agenda_rows.size():
		var row: Dictionary = _agenda_rows[i]
		var done := i < done_count
		var color := _DONE_COLOR if done else (_CURRENT_COLOR if i == current else _TODO_COLOR)
		(row.check as AgendaCheck).checked = done
		(row.check as AgendaCheck).color = color
		(row.label as Label).add_theme_color_override("font_color", color)


## Opening reveal: types out the title, then "Our Agenda", then each lesson
## row in turn (its checkbox fading in as the row starts), then fades in the
## divider — easing the player in instead of showing the whole panel at once.
## The continue input shows everything immediately.
func reveal_header() -> void:
	_reveal_active = true
	_reveal_skip = false
	await _reveal_label(_title, 0.25)
	await _reveal_label(_agenda_header, 0.2)
	for row in _agenda_rows:
		if not _reveal_skip:
			create_tween().tween_property(row.check, "modulate:a", 1.0, 0.2)
		await _reveal_label(row.label, 0.12)
	if _reveal_skip:
		_finish_reveal()
	else:
		var tw := create_tween()
		tw.tween_property(_separator, "modulate:a", 1.0, 0.3)
		await tw.finished
	_reveal_active = false


## Types one header label at TYPE_CHARS_PER_SECOND, then pauses `pause_after`.
func _reveal_label(label: Label, pause_after: float) -> void:
	var total := label.get_total_character_count()
	var shown := 0.0
	while shown < total and not _reveal_skip:
		await get_tree().process_frame
		if not pause_menu_open(get_tree()):
			shown += get_process_delta_time() * TYPE_CHARS_PER_SECOND
			label.visible_characters = mini(int(shown), total)
	label.visible_characters = -1
	var t := 0.0
	while t < pause_after and not _reveal_skip:
		await get_tree().process_frame
		t += get_process_delta_time()


func _finish_reveal() -> void:
	for label: Label in [_title, _agenda_header]:
		label.visible_characters = -1
	for row in _agenda_rows:
		row.label.visible_characters = -1
		row.check.modulate.a = 1.0
	_separator.modulate.a = 1.0


func set_lesson_title(text: String) -> void:
	_lesson_title.text = text


func set_title(text: String, color: Color) -> void:
	_title.text = text
	_title.add_theme_color_override("font_color", color)


# ── Hint line ────────────────────────────────────────────────────────────

## The blinking gold line under the dialogue: what to do right now. Hidden
## behind the continue prompt while a page is waiting to be turned.
func set_hint(text: String) -> void:
	_task_hint = text
	if not _waiting_continue:
		_hint.text = text


# ── Dialogue ─────────────────────────────────────────────────────────────

## Types out each chunk, paginated to fit, waiting for the continue input after
## every page. With wait_last = false the final page stays on screen without
## waiting — for a line that ends in an instruction ("Try it!"), whose task
## then runs underneath it.
func say(chunks: Array, wait_last: bool = true) -> void:
	# The body needs its final size before text can be measured into pages.
	await get_tree().process_frame
	var pages: Array[String] = []
	for chunk in chunks:
		pages.append_array(_paginate(str(chunk)))
	for i in pages.size():
		_start_page(pages[i])
		while _typing:
			await get_tree().process_frame
		if i < pages.size() - 1 or wait_last:
			_waiting_continue = true
			_continue_arm = CONTINUE_ARM_SECONDS
			_hint.text = CONTINUE_HINT
			await _continued
			_waiting_continue = false
			_hint.text = _task_hint
	_hint.text = _task_hint


## Shows the continue prompt on its own (no dialogue page) and waits for it.
## `prompt` replaces the usual "Enter / A" text; accept_click lets a left
## click answer it too (for prompts that say "Click…").
func wait_for_continue(prompt: String = CONTINUE_HINT, accept_click: bool = false) -> void:
	_waiting_continue = true
	_click_continues = accept_click
	_continue_arm = CONTINUE_ARM_SECONDS
	_hint.text = prompt
	await _continued
	_waiting_continue = false
	_click_continues = false
	_hint.text = _task_hint


func clear_dialogue() -> void:
	_typing = false
	_body.text = ""


## Splits text into pages of whole sentences that each fit the body area.
## Explicit "\n\n" paragraph breaks are kept inside a page when they fit.
func _paginate(text: String) -> Array[String]:
	var pages: Array[String] = []
	var available := _body.size.y
	var sentences := _split_sentences(text)
	var current := ""
	for sentence in sentences:
		var candidate := current + sentence
		if current != "" and _text_height(candidate.strip_edges()) > available:
			pages.append(current.strip_edges())
			current = sentence.lstrip(" \n")
		else:
			current = candidate
	if current.strip_edges() != "":
		pages.append(current.strip_edges())
	_body.text = ""
	return pages


func _text_height(text: String) -> float:
	_body.text = text
	return _body.get_content_height()


## Sentence ends (". ", "! ", "? ", "... ", newlines) stay attached to the
## sentence before them, so pages keep their original spacing.
func _split_sentences(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("[^.!?\\n]*(?:[.!?]+[\"')]*)?[ \\n]*")
	for m in re.search_all(text):
		var s := m.get_string()
		if s != "":
			out.append(s)
	return out


func _start_page(text: String) -> void:
	_body.text = text
	_type_text = _body.get_parsed_text()
	_body.visible_characters = 0
	_type_budget = -TYPE_START_DELAY
	_type_cost = 1.0 / TYPE_CHARS_PER_SECOND
	_typing = not _type_text.is_empty()
	_hint.text = ""


## True while the pause menu (or the Options screen it opened) is up. The
## panel and the director run while the tree is paused, so they hold still
## themselves — no typing, no continue presses meant for the menu.
static func pause_menu_open(tree: SceneTree) -> bool:
	var menu := tree.get_first_node_in_group("pause_menu")
	return menu != null and menu.has_method("is_open") and menu.call(&"is_open")


func _process(delta: float) -> void:
	if pause_menu_open(get_tree()):
		if _voice:
			_voice.stream_paused = true  # hold the voice under the pause menu
		return
	_animate_instructor(delta)
	if _typing:
		_type_budget += delta
		while _typing and _type_budget >= _type_cost:
			_type_budget -= _type_cost
			_body.visible_characters += 1
			var shown := _body.visible_characters
			if shown >= _type_text.length():
				_finish_typing()
			else:
				_type_cost = _char_cost(shown - 1)
	elif _waiting_continue:
		_continue_arm -= delta

	_update_voice(delta)

	if is_instance_valid(_banner_hint):
		var banner_blink_on := int(Time.get_ticks_msec() / HINT_BLINK_PERIOD_MSEC) % 2 == 0
		_banner_hint.modulate.a = 1.0 if banner_blink_on else HINT_BLINK_LOW_ALPHA

	var blink_on := int(Time.get_ticks_msec() / HINT_BLINK_PERIOD_MSEC) % 2 == 0
	if _hint.text != "":
		_hint.modulate.a = 1.0 if blink_on else HINT_BLINK_LOW_ALPHA

	if _play_hint:
		_play_hint.text = _task_hint
		_play_hint.modulate.a = 1.0 if blink_on else HINT_BLINK_LOW_ALPHA
		# Placed from the camera each frame: across the play area, centred
		# midway between the surface and the sea floor.
		var middle_on_screen: Vector2 = get_viewport().get_canvas_transform() \
			* Vector2(0.0, (PLAY_AREA_HINT_SURFACE_Y + PLAY_AREA_HINT_FLOOR_Y) * 0.5)
		var left: float = PLAY_AREA_LEFT_X + PLAY_AREA_HINT_SIDE_MARGIN
		_play_hint.position = Vector2(left, middle_on_screen.y - PLAY_AREA_HINT_HEIGHT * 0.5)
		_play_hint.size = Vector2(get_viewport().get_visible_rect().size.x - PLAY_AREA_HINT_SIDE_MARGIN - left, PLAY_AREA_HINT_HEIGHT)


## Seconds to wait after revealing the letter at `index`. Sentence punctuation
## only pauses when it really ends the sentence, so "yeah.." pauses once.
func _char_cost(index: int) -> float:
	var cost := 1.0 / TYPE_CHARS_PER_SECOND
	var c: String = _type_text[index]
	var next: String = _type_text[index + 1] if index + 1 < _type_text.length() else ""
	if c in ".!?" and (next == "" or next == " " or next == "\n"):
		cost += TYPE_SENTENCE_PAUSE
	elif c in ",;:—-" and (next == " "):
		cost += TYPE_CLAUSE_PAUSE
	return cost


func _finish_typing() -> void:
	_typing = false
	_body.visible_characters = -1


func _input(event: InputEvent) -> void:
	# A left click also dismisses a banner. Safe even though LMB is a flipper in
	# mouse mode: the flippers are paused (or not in the level yet) while one
	# is up.
	if _banner_active and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not pause_menu_open(get_tree()):
		_banner_skip = true
		get_viewport().set_input_as_handled()
		return
	if _click_continues and _waiting_continue and _continue_arm <= 0.0 and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not pause_menu_open(get_tree()):
		get_viewport().set_input_as_handled()
		_continued.emit()
		return
	if not _is_continue_event(event) or pause_menu_open(get_tree()):
		return
	if _reveal_active:
		_reveal_skip = true
		get_viewport().set_input_as_handled()
	elif _banner_active:
		_banner_skip = true
		get_viewport().set_input_as_handled()
	elif _typing:
		_finish_typing()
		_continue_arm = CONTINUE_ARM_SECONDS
		get_viewport().set_input_as_handled()
	elif _waiting_continue and _continue_arm <= 0.0:
		get_viewport().set_input_as_handled()
		_continued.emit()


static func _is_continue_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		return pad.pressed and pad.button_index == JOY_BUTTON_A
	return false


# ── Lesson banner ────────────────────────────────────────────────────────

## The "new lesson" moment, centred on the whole screen: a white flash, a dark
## band snapping open with gold edges, the kicker ("LESSON 2") sliding in and
## the title punching in from big to normal size. It stays up until the
## continue input (Enter / A, prompted under the band), then sweeps off to the
## right. Built fresh each time on its own top CanvasLayer and freed after.
## Laid out with anchors, not measured pixel sizes, so it centres on whatever
## the screen really is (letterboxing, window size).
## `prompt` replaces the usual "Enter / A" line (the opening welcome banner
## uses a call to action).
func play_banner(kicker: String, title: String, prompt: String = CONTINUE_HINT, lesson_sound: bool = false) -> void:
	var layer := CanvasLayer.new()
	layer.layer = BANNER_LAYER
	add_child(layer)
	var area := _anchored(Control.new(), Control.PRESET_FULL_RECT)
	layer.add_child(area)

	var flash := _anchored(ColorRect.new(), Control.PRESET_FULL_RECT) as ColorRect
	flash.color = Color(1, 1, 1, 0.75)
	area.add_child(flash)

	# Long and narrow, vertically centred, inset from both sides of the screen.
	var band := _anchored(Control.new(), Control.PRESET_HCENTER_WIDE)
	band.offset_left = _BANNER_SIDE_INSET
	band.offset_right = -_BANNER_SIDE_INSET
	band.offset_top = -_BANNER_HEIGHT * 0.5
	band.offset_bottom = _BANNER_HEIGHT * 0.5
	band.pivot_offset = Vector2(0.0, _BANNER_HEIGHT * 0.5)
	band.scale = Vector2(1.0, 0.0)
	area.add_child(band)
	# The pixel-art panel frame/background (a childless PanelContainer just
	# draws its theme stylebox).
	var frame := _anchored(PanelContainer.new(), Control.PRESET_FULL_RECT)
	frame.theme_type_variation = _BANNER_PANEL_STYLE
	band.add_child(frame)

	var kicker_label := _banner_label(kicker, 14, _BANNER_EDGE_COLOR, 9.0)
	kicker_label.modulate.a = 0.0
	band.add_child(kicker_label)
	var title_label := _banner_label(title, 20, _BANNER_TITLE_COLOR, 29.0)
	title_label.modulate.a = 0.0
	band.add_child(title_label)
	# Bottom-right corner, inside the frame and clear of the centred title;
	# blinks in _process() once shown.
	var hint := _banner_label(prompt, 12, _BANNER_EDGE_COLOR, _BANNER_HEIGHT - 22.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.offset_right = -14.0
	hint.visible = false
	band.add_child(hint)

	var sfx := AudioStreamPlayer.new()
	# Lesson banners have their own sound; the welcome and graduation banners
	# keep the delivery jingle.
	var banner_sfx := load(_LESSON_BANNER_SFX_PATH) as AudioStream if lesson_sound else null
	sfx.stream = banner_sfx if banner_sfx else _BANNER_SFX
	sfx.volume_db = -6.0
	add_child(sfx)  # not under the banner, so the sound isn't cut off when it goes
	sfx.finished.connect(sfx.queue_free)
	sfx.play()

	_banner_active = true
	_banner_skip = false
	# One frame for the anchors to resolve, so the title can scale about its
	# real centre.
	await get_tree().process_frame
	title_label.pivot_offset = title_label.size * 0.5
	title_label.scale = Vector2(2.2, 2.2)
	var kicker_x := kicker_label.position.x
	kicker_label.position.x = kicker_x - 40.0

	var tw_in := create_tween()
	tw_in.tween_property(flash, "color:a", 0.0, 0.45)
	tw_in.parallel().tween_property(band, "scale:y", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(kicker_label, "position:x", kicker_x, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw_in.parallel().tween_property(kicker_label, "modulate:a", 1.0, 0.2)
	tw_in.tween_property(title_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.parallel().tween_property(title_label, "modulate:a", 1.0, 0.2)
	await tw_in.finished

	# Presses during the entrance don't count — wait for a fresh one.
	_banner_skip = false
	hint.visible = true
	_banner_hint = hint
	while not _banner_skip:
		await get_tree().process_frame
	_banner_hint = null
	hint.visible = false

	var tw_out := create_tween()
	tw_out.tween_property(band, "position:x", area.size.x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw_out.parallel().tween_property(band, "modulate:a", 0.0, 0.3)
	await tw_out.finished
	_banner_active = false
	layer.queue_free()


func _anchored(control: Control, preset: Control.LayoutPreset) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.set_anchors_and_offsets_preset(preset)
	return control


## A full-width, horizontally centred label `top` pixels down the band.
func _banner_label(text: String, font_size: int, color: Color, top: float) -> Label:
	var label := _anchored(Label.new(), Control.PRESET_TOP_WIDE) as Label
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.offset_top = top
	label.offset_bottom = top + font_size + 8
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


# ── Graduation name prompt ───────────────────────────────────────────────

## Asks the graduate to sign their certificate: a small opaque panel on the
## banner layer with a name field and a "Certify!" button, prefilled with
## `default_name`. Enter (in the field) or the button submits. While a gamepad
## is the active device a VirtualKeyboard replaces the button (its Done key
## submits) — it shows/hides live if the player switches device. Returns the
## trimmed name, or `default_name` if it was left blank.
func ask_name(default_name: String) -> String:
	var layer := CanvasLayer.new()
	layer.layer = BANNER_LAYER
	add_child(layer)
	var center := _anchored(CenterContainer.new(), Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(center)
	var box := PanelContainer.new()
	box.theme_type_variation = &"PanelBaseOpaque"
	center.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	var heading := Label.new()
	heading.text = "Sign your certificate!"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", _BANNER_TITLE_COLOR)
	column.add_child(heading)

	var field := LineEdit.new()
	field.text = default_name
	field.placeholder_text = "Your name"
	field.max_length = SaveManager.PLAYER_NAME_MAX_LENGTH
	field.custom_minimum_size = Vector2(180, 0)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 16)
	field.select_all_on_focus = true
	column.add_child(field)

	var button := Button.new()
	button.text = "Certify!"
	button.add_theme_font_size_override("font_size", 16)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(button)
	field.focus_neighbor_bottom = field.get_path_to(button)
	button.focus_neighbor_top = button.get_path_to(field)

	var keyboard := VirtualKeyboard.new()
	keyboard.target = field
	column.add_child(keyboard)

	var state := {"done": false}
	var submit := func(_text: String = "") -> void: state.done = true
	field.text_submitted.connect(submit)
	button.pressed.connect(submit)
	keyboard.done.connect(submit)
	# Gamepad: on-screen keyboard, focus on its keys. Keyboard/mouse: type in
	# the field, Certify! button.
	var use_device := func(gamepad: bool) -> void:
		keyboard.visible = gamepad
		button.visible = not gamepad
		if gamepad:
			keyboard.focus_first_key()
		else:
			field.grab_focus()
			field.caret_column = field.text.length()
	GameSettings.input_device_changed.connect(use_device)
	await get_tree().process_frame
	use_device.call(GameSettings.using_gamepad)
	while not state.done:
		await get_tree().process_frame
	GameSettings.input_device_changed.disconnect(use_device)

	var player_name := field.text.strip_edges()
	layer.queue_free()
	return player_name if player_name != "" else default_name
