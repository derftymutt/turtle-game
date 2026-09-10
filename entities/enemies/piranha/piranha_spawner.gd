extends Node2D

signal frenzy_started

@export var piranha_scene: PackedScene
@export var super_piranha_scene: PackedScene

@export_group("Spawn Settings")
@export var spawn_interval: float = 5.0
@export var spawn_area_min: Vector2 = Vector2(-250, 40)
@export var spawn_area_max: Vector2 = Vector2(250, 140)

@export_group("Super Piranha")
@export var super_piranha_chance: float = 0.25  # 25% chance for super variant
@export var super_piranha_warning_color: Color = Color(1.0, 0.5, 0.0)  # Orange warning

## Stress mode — kicks in the instant the level timer runs out. Spawn rate jumps
## immediately, then keeps ramping every few seconds until the swarm is
## unsurvivable. There is no cap on the ramp; only the per-spawn interval floor.
@export_group("Timer Frenzy")
@export var frenzy_enabled: bool = true
@export var frenzy_initial_multiplier: float = 4.0   # rate ×N the moment time expires
@export var frenzy_ramp_step: float = 1.5            # extra rate multiplier added each ramp
@export var frenzy_ramp_interval: float = 5.0        # seconds between ramp increments
@export var frenzy_min_interval: float = 0.35        # hard floor on seconds between spawns

var _spawn_timer: Timer
var _base_interval: float = 5.0
var _frenzy_active: bool = false
var _frenzy_elapsed: float = 0.0

func _ready():
	add_to_group("spawners")
	# Validation check
	if not piranha_scene:
		push_error("PiranhaSpawner: piranha_scene not assigned!")
	if not super_piranha_scene:
		push_warning("PiranhaSpawner: super_piranha_scene not assigned - will only spawn regular piranhas")

	_base_interval = spawn_interval

	_spawn_timer = Timer.new()
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(spawn_with_animation)
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.start()

	# HUD registers its group in _ready(); defer so it exists regardless of tree order.
	_connect_to_hud.call_deferred()

func _process(delta: float) -> void:
	if not _frenzy_active:
		return
	_frenzy_elapsed += delta
	_apply_frenzy_interval()

func _connect_to_hud() -> void:
	if not frenzy_enabled:
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud or not hud.has_signal("time_expired"):
		return
	if not hud.time_expired.is_connected(_on_time_expired):
		hud.time_expired.connect(_on_time_expired)
	# In case the timer already lapsed before this spawner wired up.
	if "_timer_expired" in hud and hud._timer_expired:
		_on_time_expired()

func _on_time_expired() -> void:
	if _frenzy_active or not frenzy_enabled:
		return
	_frenzy_active = true
	_frenzy_elapsed = 0.0
	_apply_frenzy_interval()
	# Apply the first jump right now instead of waiting out the current cycle.
	_spawn_timer.start(_spawn_timer.wait_time)
	frenzy_started.emit()
	print("🦈🔥 Piranha frenzy: time's up — spawn rate escalating")

func _apply_frenzy_interval() -> void:
	var ramp := frenzy_ramp_step * (_frenzy_elapsed / maxf(0.001, frenzy_ramp_interval))
	var rate_multiplier := maxf(1.0, frenzy_initial_multiplier + ramp)
	_spawn_timer.wait_time = maxf(frenzy_min_interval, _base_interval / rate_multiplier)

func spawn_with_animation():
	var pos = Vector2(
		randf_range(spawn_area_min.x, spawn_area_max.x),
		randf_range(spawn_area_min.y, spawn_area_max.y)
	)

	# Decide if this is a super piranha (only if we have the scene!)
	var is_super = false
	if super_piranha_scene:
		is_super = randf() < super_piranha_chance

	var warning_color = super_piranha_warning_color if is_super else Color(1, 0.3, 0.3, 0.7)

	# === PHASE 1: Warning circles (ripples) ===
	for i in range(3):
		await get_tree().create_timer(0.2 * i).timeout
		create_warning_ripple(pos, i, warning_color)

	# === PHASE 2: Piranha silhouette grows ===
	await get_tree().create_timer(0.4).timeout

	# Choose which scene to spawn - with fallback logic
	var scene_to_spawn: PackedScene = null

	if is_super and super_piranha_scene:
		scene_to_spawn = super_piranha_scene
	elif piranha_scene:
		scene_to_spawn = piranha_scene
	else:
		push_error("No piranha scene available to spawn!")
		return

	# Create a temporary sprite that looks like the piranha
	var approach_sprite = Sprite2D.new()

	# Get piranha's sprite to copy it
	var temp_piranha = scene_to_spawn.instantiate()
	var piranha_sprite = temp_piranha.get_node_or_null("AnimatedSprite2D")
	if not piranha_sprite:
		piranha_sprite = temp_piranha.get_node_or_null("Sprite2D")

	if piranha_sprite:
		if piranha_sprite is AnimatedSprite2D:
			approach_sprite.texture = piranha_sprite.sprite_frames.get_frame_texture("default", 0)
		else:
			approach_sprite.texture = piranha_sprite.texture

	temp_piranha.queue_free()

	# Set up approach sprite
	get_parent().add_child(approach_sprite)
	approach_sprite.global_position = pos
	approach_sprite.scale = Vector2(0.1, 0.1)
	approach_sprite.modulate = Color(0.2, 0.2, 0.3, 0.5)

	# Add tint for super piranhas during approach
	if is_super:
		approach_sprite.modulate = Color(0.5, 0.2, 0.2, 0.5)  # Reddish tint

	approach_sprite.rotation = randf_range(-0.3, 0.3)

	# Animate: scale up + fade in + slight rotation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(approach_sprite, "scale", Vector2(1.2, 1.2), 0.6)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var final_color = Color(1.2, 0.5, 0.5, 1) if is_super else Color(1, 1, 1, 1)
	tween.tween_property(approach_sprite, "modulate", final_color, 0.6)
	tween.tween_property(approach_sprite, "rotation", 0.0, 0.6)

	await tween.finished

	# === PHASE 3: Pop effect and spawn real piranha ===
	var pop_tween = create_tween()
	pop_tween.tween_property(approach_sprite, "scale", Vector2(1.3, 1.3), 0.1)
	await pop_tween.finished

	# Abort if time is frozen — the coroutine outlived the freeze window
	if AlienTechManager.time_freeze_active:
		approach_sprite.queue_free()
		return

	# Spawn real piranha (normal or super)
	var piranha = scene_to_spawn.instantiate()
	get_parent().add_child(piranha)
	piranha.global_position = pos

	# Clean up approach sprite
	approach_sprite.queue_free()

func create_warning_ripple(pos: Vector2, delay_index: int, color: Color = Color(1, 0.3, 0.3, 0.7)):
	"""Create an expanding circle ripple effect"""
	var ripple = Node2D.new()
	get_parent().add_child(ripple)
	ripple.global_position = pos

	var circle = ColorRect.new()
	circle.color = color
	circle.size = Vector2(10, 10)
	circle.position = Vector2(-5, -5)
	ripple.add_child(circle)

	# Animate: expand and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(circle, "size", Vector2(60, 60), 1.0)
	tween.tween_property(circle, "position", Vector2(-30, -30), 1.0)
	tween.tween_property(circle, "color:a", 0.0, 1.0)

	tween.finished.connect(ripple.queue_free)
