extends Node2D
class_name InkCloud

## Black ink a Squid leaves behind when it jets off. Stays where it formed
## for linger_time, then fades away. While it's there, the turtle touching it
## is inked (TurtlePlayer.apply_ink): it can't spit and pulses black for
## blind_duration — refreshed for as long as it stays inside. No damage.
## Its clock stops during Time Freeze.

@export var linger_time: float = 5.0
@export var fade_time: float = 1.0
@export var blind_duration: float = 3.5

var _age: float = 0.0
var _fading: bool = false

@onready var _area: Area2D = $Area2D
@onready var _cloud: CPUParticles2D = $Cloud
@onready var _burst: CPUParticles2D = $Burst

func _ready() -> void:
	add_to_group("ink_clouds")
	_burst.emitting = true
	_cloud.emitting = true
	# Squirts out and billows to full size
	scale = Vector2.ONE * 0.4
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	var frozen := AlienTechManager.time_freeze_active
	_cloud.speed_scale = 0.0 if frozen else 1.0
	_burst.speed_scale = _cloud.speed_scale
	if frozen or _fading:
		return

	for body in _area.get_overlapping_bodies():
		if body.has_method("apply_ink"):
			body.apply_ink(blind_duration)

	_age += delta
	if _age >= linger_time:
		_fade_out()

func _fade_out() -> void:
	_fading = true
	_cloud.emitting = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)
