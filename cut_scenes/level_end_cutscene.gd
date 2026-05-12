# level_end_cutscene.gd
# In-level cut scene: assembled UFO shakes at the workshop then launches off-screen.
# Owned by LevelBase. LevelManager.complete_level() calls play() and awaits it.
extends Node2D

signal finished

var ufo_sprite: Sprite2D = null
var thruster: CPUParticles2D = null
var _thruster_y_offset: float = 19.0  # bottom of 32-px UFO + small gap
var _playing: bool = false

func _ready() -> void:
	add_to_group("level_end_cutscene")

	ufo_sprite = Sprite2D.new()
	ufo_sprite.texture = load("res://cut_scenes/sprites/ufo_assembled.png")
	ufo_sprite.visible = false
	ufo_sprite.z_index = 100
	add_child(ufo_sprite)

	_setup_thruster()
	if ufo_sprite.texture:
		_thruster_y_offset = ufo_sprite.texture.get_height() * 0.5 + 3.0

func _setup_thruster() -> void:
	thruster = CPUParticles2D.new()
	thruster.emitting = false
	thruster.amount = 18
	thruster.lifetime = 0.4
	thruster.explosiveness = 0.0
	thruster.randomness = 0.45
	thruster.direction = Vector2(0.0, 1.0)   # downward exhaust
	thruster.spread = 22.0
	thruster.gravity = Vector2(0.0, 0.0)
	thruster.initial_velocity_min = 55.0
	thruster.initial_velocity_max = 120.0
	thruster.scale_amount_min = 2.0
	thruster.scale_amount_max = 5.0
	thruster.z_index = 99

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.2, 1.0))   # bright yellow
	grad.set_color(1, Color(1.0, 0.38, 0.0, 0.0))    # orange → transparent
	thruster.color_ramp = grad

	add_child(thruster)

func _process(_delta: float) -> void:
	# Keep thruster anchored below the UFO sprite regardless of how the UFO moves.
	if thruster and ufo_sprite and ufo_sprite.visible:
		thruster.global_position = ufo_sprite.global_position + Vector2(0.0, _thruster_y_offset)

func play(workshop_position: Vector2) -> void:
	if _playing:
		return
	_playing = true

	ufo_sprite.global_position = workshop_position
	ufo_sprite.visible = true
	thruster.emitting = true

	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

	await _shake()
	await _launch()

	finished.emit()

func _shake() -> void:
	var origin: Vector2 = ufo_sprite.global_position
	var tween := create_tween()
	for i in 10:
		tween.tween_property(ufo_sprite, "global_position",
			origin + Vector2(randf_range(-7.0, 7.0), randf_range(-4.0, 4.0)), 0.06)
	tween.tween_property(ufo_sprite, "global_position", origin, 0.04)
	await tween.finished

func _launch() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera:
		camera.set_process(false)

	var sky_y: float = -300.0
	if camera and camera.get("sky_locked_y") != null:
		sky_y = float(camera.get("sky_locked_y"))

	var start_y: float = ufo_sprite.global_position.y

	# Camera pans independently — reveals a full screen of sky above the ocean.
	if camera:
		var cam_tween := create_tween()
		cam_tween.tween_property(camera, "global_position:y", sky_y, 1.2)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 1 (0.3s): tiny initial hover — engine igniting, UFO strains upward.
	# Phase 2 (0.85s): TRANS_EXPO EASE_IN — barely moves for ~0.6s then rockets away.
	var ufo_tween := create_tween()
	ufo_tween.tween_property(ufo_sprite, "global_position:y", start_y - 18.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ufo_tween.tween_property(ufo_sprite, "global_position:y", start_y - 500.0, 0.85)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	# Cartoon squish → stretch: coils up during hover, elongates during blast.
	var scale_tween := create_tween()
	scale_tween.tween_property(ufo_sprite, "scale", Vector2(1.15, 0.82), 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(ufo_sprite, "scale", Vector2(0.65, 1.9), 0.85)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await ufo_tween.finished
