extends Node2D
class_name CommunityUFOSpawner

# ============================================================
# SCHEDULING
# ============================================================
@export_group("Scheduling")
## Minimum seconds between Community UFO events
@export var min_event_interval: float = 45.0
## Maximum seconds between Community UFO events
@export var max_event_interval: float = 90.0
## Delay before the first event fires after the level starts
@export var initial_delay: float = 15.0
## Set to false to disable automatic spawning (use trigger_event() manually)
@export var auto_spawn: bool = true

# ============================================================
# DOLPHIN CONFIGURATION
# ============================================================
@export_group("Dolphin")
@export var dolphin_scene: PackedScene
@export var community_ufo_scene: PackedScene
## Swim depth (Y world position) for the dolphin
@export var dolphin_swim_y: float = 30.0
## Random variation in Y each event
@export var dolphin_y_variation: float = 20.0
## Dolphin swim speed (pixels/sec)
@export var dolphin_swim_speed: float = 90.0
## How far off-screen (in pixels) the dolphin spawns
@export var spawn_margin: float = 120.0

# ============================================================
# UFO DROP ZONE
# ============================================================
@export_group("UFO Drop Zone")
## Drop anywhere from (screen_center + drop_min_offset) to (screen_center + drop_max_offset)
## Use negative values for left-of-center, positive for right-of-center.
@export var drop_zone_min_x: float = -80.0
@export var drop_zone_max_x: float = 80.0

# ============================================================
# INTERNAL
# ============================================================

var _timer: Timer = null
var _active_dolphin: Node2D = null

signal event_triggered
signal event_complete

func _ready():
	if not dolphin_scene:
		push_error("CommunityUFOSpawner: dolphin_scene not assigned!")
	if not community_ufo_scene:
		push_error("CommunityUFOSpawner: community_ufo_scene not assigned!")

	if auto_spawn:
		_start_timer(initial_delay)

func _start_timer(wait_time: float):
	if _timer and is_instance_valid(_timer):
		_timer.stop()
		_timer.queue_free()

	_timer = Timer.new()
	add_child(_timer)
	_timer.one_shot = true
	_timer.wait_time = wait_time
	_timer.timeout.connect(_on_timer_timeout)
	_timer.start()

func _on_timer_timeout():
	trigger_event()
	if auto_spawn:
		_start_timer(randf_range(min_event_interval, max_event_interval))

## Call this directly to force a Community UFO event right now.
func trigger_event():
	if _active_dolphin and is_instance_valid(_active_dolphin):
		return  # Already running

	var camera = get_viewport().get_camera_2d()
	if not camera:
		push_warning("CommunityUFOSpawner: no Camera2D found, defaulting to origin")

	var cam_x = camera.global_position.x if camera else 0.0
	var half_w = get_viewport().get_visible_rect().size.x * 0.5 / (camera.zoom.x if camera else 1.0)

	# Randomise direction: 50/50 left→right or right→left
	var direction = 1 if randf() > 0.5 else -1
	var start_x: float
	if direction > 0:
		# Left → right: spawn off the left edge
		start_x = cam_x - half_w - spawn_margin
	else:
		# Right → left: spawn off the right edge
		start_x = cam_x + half_w + spawn_margin

	var exit_x = cam_x + (half_w + spawn_margin) * direction
	var drop_x = cam_x + randf_range(drop_zone_min_x, drop_zone_max_x)
	var swim_y = dolphin_swim_y + randf_range(-dolphin_y_variation, dolphin_y_variation)

	_spawn_dolphin(start_x, exit_x, drop_x, swim_y, direction)
	emit_signal("event_triggered")

func _spawn_dolphin(start_x: float, exit_x: float, drop_x: float, swim_y: float, direction: int):
	if not dolphin_scene:
		return

	var dolphin = dolphin_scene.instantiate()

	# Configure BEFORE add_child so _ready() sees the correct values
	dolphin.swim_direction = direction
	dolphin.swim_speed = dolphin_swim_speed
	dolphin.drop_x = drop_x
	dolphin.exit_x = exit_x
	dolphin.community_ufo_scene = community_ufo_scene

	get_parent().add_child(dolphin)
	dolphin.global_position = Vector2(start_x, swim_y)

	_active_dolphin = dolphin

	# Listen for when the dolphin is done
	dolphin.tree_exited.connect(func():
		_active_dolphin = null
		emit_signal("event_complete")
	)
