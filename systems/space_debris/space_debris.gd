# space_debris.gd
extends RigidBody2D
class_name SpaceDebris

## An individual piece of space debris floating in the sky.
## Unlike ocean trash (which drifts through and despawns), space debris
## LIVES PERMANENTLY in the sky until the player shoots it.
##
## Each piece belongs to a SpaceDebrisGroup. When ALL pieces in a group
## are destroyed, the group spawns a powerup reward.
##
## VISUAL IDENTITY:
## Set debris_texture and/or debris_modulate in the Inspector on each
## instance. Give all three pieces in a group the same texture + color
## so the player can identify them as a set.

signal debris_destroyed(debris: SpaceDebris)

# ── Identity ─────────────────────────────────────────────────────────────
var group_owner: SpaceDebrisGroup = null

# ── Movement ──────────────────────────────────────────────────────────────
@export_group("Floating Movement")
@export var drift_speed: float = 18.0
@export var wander_strength: float = 12.0
@export var wander_interval: float = 3.5
@export var bob_amount: float = 5.0
@export var bob_speed: float = 1.4
@export var spin_speed: float = 0.4

# ── Visual ────────────────────────────────────────────────────────────────
@export_group("Visual")
@export var points: int = 10

## Texture to display for this debris piece.
## Set the same texture on all three pieces in a group so they're
## visually identifiable as belonging together.
## If left empty, the Sprite2D's existing texture is kept as-is.
@export var debris_texture: Texture2D = null:
	set(value):
		debris_texture = value
		_apply_texture()

## Animation to play if the visual child is an AnimatedSprite2D.
## Leave empty to use whatever the AnimatedSprite2D defaults to.
@export var debris_animation: StringName = &"":
	set(value):
		debris_animation = value
		_apply_animation()

## Tint color — another axis for differentiating groups.
## Leave at white for no tint. Combine with debris_texture for
## maximum variety (e.g. same shape, different color per group).
@export var debris_modulate: Color = Color.WHITE:
	set(value):
		debris_modulate = value
		_apply_modulate()

# ── Internal State ────────────────────────────────────────────────────────
var is_destroyed: bool = false
var bob_offset: float = 0.0
var wander_timer: float = 0.0
var current_wander: Vector2 = Vector2.ZERO
var visual_node: Node2D = null
var hud: HUD = null

func _ready() -> void:
	gravity_scale = 0.0
	linear_damp  = 2.5
	angular_damp = 3.0
	mass         = 0.3
	lock_rotation = true

	# NOTE: Set collision layers in Inspector:
	#   Collision Layer: 8  (space debris)
	#   Collision Mask:  4  (bullets only)
	# Area2D child:
	#   Collision Layer: 0
	#   Collision Mask:  4  (detects bullets)

	z_index = 60
	add_to_group("space_debris")

	bob_offset   = randf() * TAU
	wander_timer = randf_range(0.0, wander_interval)

	current_wander = Vector2(
		randf_range(-drift_speed, drift_speed),
		randf_range(-drift_speed * 0.4, drift_speed * 0.4)
	)
	linear_velocity = current_wander

	# Cache visual node FIRST, then apply exported visuals.
	# The property setters fire before _ready when the scene loads,
	# so visual_node is null at that point — we re-apply here to guarantee it.
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")

	_apply_texture()
	_apply_animation()
	_apply_modulate()

	hud = get_tree().get_first_node_in_group("hud")

	var area := get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("SpaceDebris '%s': No Area2D child found — bullets won't detect it!" % name)


# ── Visual Helpers ────────────────────────────────────────────────────────

func _apply_animation() -> void:
	if debris_animation == &"" or visual_node == null:
		return
	if visual_node is AnimatedSprite2D:
		(visual_node as AnimatedSprite2D).play(debris_animation)


func _apply_texture() -> void:
	if debris_texture == null or visual_node == null:
		return
	if visual_node is Sprite2D:
		(visual_node as Sprite2D).texture = debris_texture


func _apply_modulate() -> void:
	if visual_node == null:
		return
	visual_node.modulate = debris_modulate


# ── Physics Process ───────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_destroyed:
		return

	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = wander_interval + randf_range(-0.5, 0.5)
		current_wander = Vector2(
			randf_range(-drift_speed, drift_speed),
			randf_range(-drift_speed * 0.4, drift_speed * 0.4)
		)

	linear_velocity = linear_velocity.lerp(current_wander, delta * wander_strength * 0.1)

	bob_offset += bob_speed * delta
	if visual_node:
		visual_node.position.y = sin(bob_offset) * bob_amount
		visual_node.rotation += spin_speed * delta


# ── Bullet Detection ──────────────────────────────────────────────────────

func _on_area_body_entered(body: Node2D) -> void:
	if is_destroyed:
		return
	if body.is_in_group("bullets"):
		_get_shot()
		return
	if body.has_method("set_velocity") and body.collision_layer == 4:
		_get_shot()


func _get_shot() -> void:
	is_destroyed = true
	freeze = true
	if hud:
		hud.add_score(points)
	debris_destroyed.emit(self)
	_play_destruction_effect()


func _play_destruction_effect() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(self, "scale", Vector2.ONE * 1.6, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2)\
		.set_delay(0.15)

	# Flash using the group's own tint color so it feels cohesive
	if visual_node:
		tween.tween_property(visual_node, "modulate", debris_modulate * 2.5, 0.08)
		tween.tween_property(visual_node, "modulate:a", 0.0, 0.25).set_delay(0.08)

	tween.finished.connect(queue_free)
