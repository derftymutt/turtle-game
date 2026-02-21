# camera_2d.gd
extends Camera2D

## Game camera with cinematic sky-entry transition.
##
## STATES:
##   OCEAN  — normal zoom, follows turtle vertically + horizontally
##   SKY_CINEMATIC — one-shot dramatic zoom-out for drama, then zooms back in
##   SKY_LOCKED — full zoom, camera panned up so sky fills the screen,
##                no vertical follow (stays fixed until turtle falls back down)
##   RETURNING — smooth pan back down when turtle re-enters the ocean

# ── Target ────────────────────────────────────────────────────────────────
@export var follow_target: Node2D  # Assign the TurtlePlayer in the Inspector

# ── World Boundaries ──────────────────────────────────────────────────────
@export var ocean_surface_y: float = -126.0  # Y where ocean surface sits
@export var ocean_floor_y:   float =  180.0  # Y of ocean floor
## How far above the surface the turtle must be to trigger the sky state.
## A small buffer prevents flickering when the turtle is right at the surface.
@export var sky_entry_threshold: float = 40.0
## How far below the surface the turtle must be to fully leave the sky state.
## Slightly larger than sky_entry_threshold to create hysteresis (no flicker).
@export var sky_exit_threshold: float = 20.0

# ── Sky Camera Position ───────────────────────────────────────────────────
## The Y position the camera locks to when in sky mode.
## This should frame the sky nicely — typically somewhere between the
## ocean surface and the top of your sky play area.
## Tune this in the Inspector to match your level layout.
@export var sky_locked_y: float = -300.0

# ── Zoom Values ───────────────────────────────────────────────────────────
@export var normal_zoom:     Vector2 = Vector2(1.0, 1.0)
## Maximum zoom-out during the cinematic beat.
## 0.5 = "zoomed out 2×", giving a wide dramatic view.
@export var cinematic_zoom:  Vector2 = Vector2(0.5, 0.5)
## Zoom when locked in the sky. 1.0 = normal, which fills the screen with sky.
@export var sky_locked_zoom: Vector2 = Vector2(1.0, 1.0)

# ── Timing ────────────────────────────────────────────────────────────────
@export_group("Cinematic Timing")
## How long it takes to zoom OUT during the cinematic beat (seconds).
@export var zoom_out_duration:  float = 0.35
## How long we HOLD the wide shot before zooming back in (seconds).
@export var hold_duration:      float = 0.0 #0.25
## How long it takes to zoom back IN and pan up to sky_locked_y (seconds).
@export var zoom_in_duration:   float = 0.35
## How fast the camera pans back to ocean Y when the turtle falls back down.
@export var return_pan_speed:   float = 4.0

# ── Horizontal Follow ─────────────────────────────────────────────────────
@export_group("Horizontal Follow")
@export var horizontal_follow_enabled: bool = true
@export var horizontal_smoothing:      float = 5.0
@export var horizontal_deadzone:       float = 50.0
@export var horizontal_offset:         float = 100.0
@export var min_camera_x:              float = -1000.0
@export var max_camera_x:              float =  5000.0

# ── State Machine ─────────────────────────────────────────────────────────
enum CameraState {
	OCEAN,          # Normal play in the ocean
	SKY_CINEMATIC,  # One-shot dramatic zoom-out sequence (Tween handles it)
	SKY_LOCKED,     # Fixed sky view, no vertical follow
	RETURNING,      # Smooth pan back down after turtle falls
}

var state: CameraState = CameraState.OCEAN

# Whether the cinematic has already fired this sky-visit
# (so flying back and forth doesn't replay it repeatedly)
var cinematic_played: bool = false

# Tracks the target X position for horizontal follow
var target_x: float = 0.0


# ── Init ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	zoom     = normal_zoom
	target_x = global_position.x
	if follow_target:
		target_x = follow_target.global_position.x


# ── Main Loop ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not follow_target:
		return

	var turtle_y := follow_target.global_position.y

	match state:

		CameraState.OCEAN:
			_follow_ocean(delta, turtle_y)
			# Detect sky entry
			if turtle_y < ocean_surface_y - sky_entry_threshold:
				_enter_sky()

		CameraState.SKY_CINEMATIC:
			# The Tween drives zoom & Y during the cinematic.
			# We still follow horizontally so the drama beat tracks the turtle.
			_follow_horizontal(delta)

		CameraState.SKY_LOCKED:
			# Y is fixed. Only follow horizontally.
			_follow_horizontal(delta)
			# Detect return to ocean
			if turtle_y > ocean_surface_y - sky_exit_threshold:
				_leave_sky()

		CameraState.RETURNING:
			_pan_to_ocean(delta)
			# Once close enough to ocean Y, snap back to OCEAN state
			if abs(global_position.y - 0.0) < 4.0:
				global_position.y = 0.0
				state = CameraState.OCEAN
				cinematic_played = false  # Allow cinematic again next sky visit


# ── State Transitions ─────────────────────────────────────────────────────

func _enter_sky() -> void:
	"""Turtle has entered the sky. Fire the one-shot cinematic, then lock."""
	state = CameraState.SKY_CINEMATIC
	cinematic_played = true
	_play_cinematic()


func _leave_sky() -> void:
	"""Turtle has fallen back below the surface. Pan camera back down."""
	state = CameraState.RETURNING
	# Kill any lingering sky tweens so they don't fight the return pan
	# (the cinematic tween calls _on_cinematic_complete when done, which is fine
	#  to fire even if we're already returning — it just won't change state)


# ── Cinematic Sequence ────────────────────────────────────────────────────

func _play_cinematic() -> void:
	"""
	Three-beat camera drama:
	  1. Zoom OUT fast  (reveal the scale of the sky)
	  2. HOLD briefly   (let the player read the scene)
	  3. Zoom back IN + pan UP to sky_locked_y  (settle into sky gameplay)
	"""
	var tween := create_tween()
	tween.set_parallel(false)  # Steps run in sequence

	# ── Beat 1: Zoom OUT ──────────────────────────────────────────
	# Pan to a midpoint between turtle and the sky to frame the drama
	var dramatic_y: float = lerp(follow_target.global_position.y, sky_locked_y, 0.5)
	tween.tween_method(_set_zoom_and_y.bind(dramatic_y), 0.0, 1.0, zoom_out_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# ── Beat 2: HOLD ─────────────────────────────────────────────
	tween.tween_interval(hold_duration)

	# ── Beat 3: Zoom IN + pan to locked sky position ──────────────
	tween.tween_method(_zoom_in_to_sky.bind(dramatic_y), 0.0, 1.0, zoom_in_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tween.finished.connect(_on_cinematic_complete)


func _set_zoom_and_y(t: float, from_y: float) -> void:
	"""Interpolate zoom OUT and pan to the dramatic midpoint Y."""
	zoom                = normal_zoom.lerp(cinematic_zoom, t)
	global_position.y   = lerp(global_position.y, from_y, t)


func _zoom_in_to_sky(t: float, from_y: float) -> void:
	"""Interpolate zoom back IN and pan to the final sky-locked Y."""
	zoom                = cinematic_zoom.lerp(sky_locked_zoom, t)
	global_position.y   = lerp(from_y, sky_locked_y, t)


func _on_cinematic_complete() -> void:
	"""Called when the cinematic tween finishes. Lock the camera to the sky view."""
	# Only lock if we haven't already left the sky during the cinematic
	if state == CameraState.SKY_CINEMATIC:
		zoom                = sky_locked_zoom
		global_position.y   = sky_locked_y
		state               = CameraState.SKY_LOCKED


# ── Per-frame Camera Behaviors ────────────────────────────────────────────

func _follow_ocean(delta: float, turtle_y: float) -> void:
	"""Standard ocean following — smooth vertical + horizontal follow."""
	# Vertical: lock to a fixed reference near the ocean center
	var target_y := 0.0  # Your ocean camera anchor Y — tune if needed
	global_position.y = lerp(global_position.y, target_y, delta * 5.0)

	# Zoom: always normal zoom in ocean
	zoom = zoom.lerp(normal_zoom, delta * 5.0)

	_follow_horizontal(delta)


func _follow_horizontal(delta: float) -> void:
	"""Smooth horizontal follow with deadzone."""
	if not horizontal_follow_enabled or not follow_target:
		return

	var turtle_x := follow_target.global_position.x
	var cam_to_turtle := turtle_x - global_position.x

	if abs(cam_to_turtle) > horizontal_deadzone:
		target_x = turtle_x - (horizontal_offset * sign(cam_to_turtle))
		target_x = clamp(target_x, min_camera_x, max_camera_x)

	global_position.x = lerp(global_position.x, target_x, horizontal_smoothing * delta)


func _pan_to_ocean(delta: float) -> void:
	"""Smoothly pan camera Y back down to ocean position after turtle falls."""
	global_position.y = lerp(global_position.y, 0.0, return_pan_speed * delta)
	# Restore normal zoom during the return pan
	zoom = zoom.lerp(normal_zoom, delta * return_pan_speed)
	_follow_horizontal(delta)
