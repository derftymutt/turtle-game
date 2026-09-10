extends CanvasLayer
class_name WaterRippleOverlay

## Purely cosmetic "wave passing the fish tank" effect.
##
## Every interval_min..interval_max seconds a soft horizontal band sweeps from
## above the water surface down past the ocean floor, refracting whatever the
## screen shows beneath this layer (the ocean and everything in it). The HUD
## sits on a higher CanvasLayer, so it is never touched. No gameplay impact.

@export var enabled: bool = true

@export_group("Timing")
@export var interval_min: float = 5.0
@export var interval_max: float = 10.0
@export var sweep_duration: float = 2.4       ## seconds for one top-to-bottom pass
@export var first_delay: float = 4.0          ## grace period after the level loads

@export_group("Look")
@export var amp_pixels: float = 2.5           ## peak horizontal displacement (game px)
@export var band_width: float = 1.0          ## vertical thickness of the band (screen fraction)
@export var travel_from: float = -0.30        ## band centre start (screen-V, off the top)
@export var travel_to: float = 1.30           ## band centre end (screen-V, off the bottom)

## Static shader look — pushed to the material once in _ready(), so a second
## instance can be a gentler/faster companion without needing its own material.
@export_group("Shader Look")
@export var wobble_freq: float = 18.0         ## undulations top-to-bottom
@export var wobble_speed: float = 2.4         ## how fast the undulation crawls
@export var lens_strength: float = 0.30       ## vertical "bulge" through the band
@export var glint: float = 0.04               ## brightness lift on the crest
@export_range(0.0, 1.0) var chroma: float = 1.0  ## amount of RGB colour split

@onready var _rect: ColorRect = $Ripple

var _mat: ShaderMaterial
var _ocean: Ocean
var _time_until_next: float = 0.0
var _sweeping: bool = false
var _sweep_t: float = 0.0
var _cur_amp_pixels: float = 3.5
var _cur_band_width: float = 0.16


func _ready() -> void:
	# The material is a shared sub-resource of the packed scene, so every
	# instance would otherwise write shader params to the SAME material and
	# stomp each other. Give this instance its own copy.
	var base_mat := _rect.material as ShaderMaterial
	if base_mat:
		_mat = base_mat.duplicate() as ShaderMaterial
		_rect.material = _mat
	_time_until_next = first_delay
	_cur_amp_pixels = amp_pixels
	_cur_band_width = band_width

	var oceans := get_tree().get_nodes_in_group("ocean")
	if not oceans.is_empty():
		_ocean = oceans[0] as Ocean

	if _mat:
		_mat.set_shader_parameter("amplitude", 0.0)
		_mat.set_shader_parameter("progress", travel_from)
		_mat.set_shader_parameter("band_width", band_width)
		_mat.set_shader_parameter("wobble_freq", wobble_freq)
		_mat.set_shader_parameter("wobble_speed", wobble_speed)
		_mat.set_shader_parameter("lens_strength", lens_strength)
		_mat.set_shader_parameter("glint", glint)
		_mat.set_shader_parameter("chroma", chroma)


func _process(delta: float) -> void:
	if not enabled or _mat == null:
		return

	_mat.set_shader_parameter("shimmer_time", Time.get_ticks_msec() / 1000.0)
	_mat.set_shader_parameter("surface_v", _compute_surface_v())

	if _sweeping:
		_sweep_t += delta / maxf(sweep_duration, 0.01)
		if _sweep_t >= 1.0:
			_end_sweep()
		else:
			var center := lerpf(travel_from, travel_to, _sweep_t)
			# Fade the wave in and out so it enters and leaves gently.
			var envelope := sin(_sweep_t * PI)
			envelope *= envelope
			_mat.set_shader_parameter("progress", center)
			_mat.set_shader_parameter("amplitude", envelope)
			_mat.set_shader_parameter("amp_pixels", _cur_amp_pixels)
			_mat.set_shader_parameter("band_width", _cur_band_width)
	else:
		_time_until_next -= delta
		if _time_until_next <= 0.0:
			_start_sweep()


func _start_sweep() -> void:
	_sweeping = true
	_sweep_t = 0.0
	# Vary each pass so it never feels metronomic.
	_cur_amp_pixels = amp_pixels * randf_range(0.7, 1.25)
	_cur_band_width = band_width * randf_range(0.85, 1.2)
	if _mat:
		_mat.set_shader_parameter("progress", travel_from)


func _end_sweep() -> void:
	_sweeping = false
	_time_until_next = randf_range(interval_min, interval_max)
	if _mat:
		_mat.set_shader_parameter("amplitude", 0.0)


## Screen-V (0..1) of the ocean surface, so the shader leaves the sky alone.
func _compute_surface_v() -> float:
	if _ocean == null:
		return 0.12
	var xform := get_viewport().get_canvas_transform()
	var screen_y := (xform * Vector2(0.0, _ocean.surface_y)).y
	var h := float(get_viewport().get_visible_rect().size.y)
	if h <= 0.0:
		return 0.12
	return clampf(screen_y / h, 0.0, 1.0)


## Fire a sweep immediately (e.g. hook this to an event for a themed beat).
func trigger_now() -> void:
	if not _sweeping:
		_start_sweep()
