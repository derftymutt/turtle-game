extends RigidBody2D

@export var lifetime: float = 0.7
@export var water_drag: float = 0.95

# "Out of phase" visual tuning — a hard, glitchy strobe between two colors, not a soft glow.
const PHASE_COLOR: Color = Color(0.3, 1.1, 1.3)      # blown-out cyan
const RIFT_COLOR: Color = Color(1.1, 0.2, 1.3)       # blown-out violet, the "other dimension" flash
const GHOST_COLOR_A: Color = Color(0.3, 0.9, 1.0, 0.8)
const GHOST_COLOR_B: Color = Color(0.85, 0.2, 1.0, 0.8)
const BASE_SCALE: float = 1.8          # sprite art is only 6px — scale it up so it reads as a real bolt
const STROBE_RATE: float = 16.0        # hard color/scale swaps per second
const POP_SCALE: float = 2.6           # scale spike on the violet "rift" flash
const DROPOUT_CHANCE: float = 0.12     # per-strobe chance of a near-invisible glitch flicker
const GHOST_INTERVAL: float = 0.018
const GHOST_FADE_TIME: float = 0.16
const GHOST_SCALE: float = 1.6
const JITTER_AMOUNT: float = 1.6

var velocity: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _ghost_timer: float = 0.0
var _strobe_index: int = -1
var _dropout: bool = false

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.1
	lock_rotation = true
	mass = 0.01
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	contact_monitor = true
	max_contacts_reported = 4

	add_to_group("bullets")
	modulate = PHASE_COLOR

	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.scale = Vector2.ONE * BASE_SCALE
		var glow := CanvasItemMaterial.new()
		glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = glow

	# NOTE: Collision layers MUST be set in Inspector (same as bullet.tscn):
	# - Collision Layer: 4 (bullets)
	# - Collision Mask: 1 + 3 (world + enemies)

	body_entered.connect(_on_body_entered)

	linear_velocity = velocity

	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel

func _physics_process(_delta):
	linear_velocity *= water_drag
	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func _process(delta: float) -> void:
	_time += delta

	# Hard strobe: snap between cyan and violet instead of smoothly fading — reads as a
	# genuine flicker between two out-of-phase states rather than a soft pulsing glow.
	var index: int = int(_time * STROBE_RATE)
	if index != _strobe_index:
		_strobe_index = index
		_dropout = randf() < DROPOUT_CHANCE

	var on_rift: bool = _strobe_index % 2 == 1
	var base_color: Color = RIFT_COLOR if on_rift else PHASE_COLOR
	modulate = Color(base_color.r, base_color.g, base_color.b, 0.1 if _dropout else 1.0)

	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		var scale_mult: float = POP_SCALE if on_rift else BASE_SCALE
		sprite.scale = Vector2.ONE * (scale_mult * (0.4 if _dropout else 1.0))
		# Unstable jitter so the bullet looks like it can't hold still in phase-space.
		sprite.position = Vector2(
			randf_range(-JITTER_AMOUNT, JITTER_AMOUNT),
			randf_range(-JITTER_AMOUNT, JITTER_AMOUNT)
		)

	# Dense, punchy afterimage trail that alternates color with the strobe.
	_ghost_timer += delta
	if _ghost_timer >= GHOST_INTERVAL:
		_ghost_timer = 0.0
		_spawn_ghost(on_rift)

func _spawn_ghost(on_rift: bool) -> void:
	var sprite := get_node_or_null("Sprite2D")
	if not sprite or not is_instance_valid(self):
		return

	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.global_position = global_position
	ghost.rotation = rotation
	ghost.scale = Vector2.ONE * GHOST_SCALE
	ghost.modulate = GHOST_COLOR_B if on_rift else GHOST_COLOR_A
	ghost.z_index = z_index - 1
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = glow

	var parent := get_parent()
	if not parent:
		return
	parent.add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, GHOST_FADE_TIME)
	tween.parallel().tween_property(ghost, "scale", Vector2.ONE * GHOST_SCALE * 0.4, GHOST_FADE_TIME)
	tween.tween_callback(ghost.queue_free)

func _on_body_entered(body):
	if body.is_in_group("player"):
		return

	# Phase enemies — including invincible ones
	if body.is_in_group("enemies"):
		if body.has_method("phase_shift"):
			body.phase_shift(5.0)
		queue_free()
		return

	# Phase 2: phase walls, bumpers, and flippers
	if body.is_in_group("dead_walls") or body.is_in_group("circular_bumpers") or body.is_in_group("flippers"):
		if body.has_method("phase_shift"):
			body.phase_shift(5.0)
		queue_free()
		return

	# Don't destroy ocean flora
	if body.is_in_group("ocean_flora"):
		queue_free()
		return

	# Everything else (other walls, flippers, etc.)
	queue_free()
