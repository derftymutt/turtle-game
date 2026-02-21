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
## Movement behavior: gentle, organic floating — like dandelion seeds or
## wisps of cotton. Uses a combination of slow drift + sine-wave bobbing
## + subtle random direction changes to feel alive.

signal debris_destroyed(debris: SpaceDebris)

# ── Identity ─────────────────────────────────────────────────────────────
## Set automatically by SpaceDebrisGroup when the group is initialized.
## Used to report back to the group when this piece is shot.
var group_owner: SpaceDebrisGroup = null

# ── Movement ──────────────────────────────────────────────────────────────
@export_group("Floating Movement")
## Base horizontal drift. A small non-zero value keeps pieces slowly
## wandering. Positive = right, negative = left.
@export var drift_speed: float = 18.0

## How much the drift direction randomly changes over time (wander behavior).
## Higher = more erratic, like a leaf in the wind.
@export var wander_strength: float = 12.0

## How often (in seconds) the wander direction changes.
@export var wander_interval: float = 3.5

## Vertical bob amplitude in pixels (visual sprite only, not physics position).
@export var bob_amount: float = 5.0

## How fast the bob oscillates (radians per second).
@export var bob_speed: float = 1.4

## Slow gentle rotation speed (radians per second).
@export var spin_speed: float = 0.4

# ── Visual Feedback ───────────────────────────────────────────────────────
@export_group("Visual")
## Score awarded when this piece is destroyed.
@export var points: int = 10

# ── Internal State ────────────────────────────────────────────────────────
var is_destroyed: bool = false
var bob_offset: float = 0.0
var wander_timer: float = 0.0
var current_wander: Vector2 = Vector2.ZERO
var visual_node: Node2D = null
var hud: HUD = null

func _ready():
	# ── Physics ──────────────────────────────────────────────────────────
	# No gravity — debris floats freely in the sky.
	gravity_scale = 0.0
	linear_damp  = 2.5   # Gentle resistance so it doesn't accelerate forever
	angular_damp = 3.0
	mass         = 0.3
	lock_rotation = true  # We'll handle visual rotation manually for smoothness

	# NOTE: Set collision layers in Inspector:
	#   Collision Layer: 8  (space debris — same layer as ocean trash)
	#   Collision Mask:  4  (bullets only — passes through everything else)
	#
	# Area2D child:
	#   Collision Layer: 0  (not on any layer)
	#   Collision Mask:  4  (detects bullets)

	z_index = 60  # Above sky background, below HUD

	add_to_group("space_debris")

	# Randomize offsets so all pieces don't move in sync
	bob_offset    = randf() * TAU
	wander_timer  = randf_range(0.0, wander_interval)

	# Start with a random gentle drift direction
	current_wander = Vector2(
		randf_range(-drift_speed, drift_speed),
		randf_range(-drift_speed * 0.4, drift_speed * 0.4)
	)
	linear_velocity = current_wander

	# Cache visual node
	visual_node = get_node_or_null("Sprite2D")
	if not visual_node:
		visual_node = get_node_or_null("AnimatedSprite2D")

	# Cache HUD for score reporting
	hud = get_tree().get_first_node_in_group("hud")

	# Connect Area2D bullet detection
	# (Area2D must be added as a child in the scene, with mask set to 4)
	var area := get_node_or_null("Area2D")
	if area:
		area.body_entered.connect(_on_area_body_entered)
	else:
		push_warning("SpaceDebris '%s': No Area2D child found — bullets won't detect it!" % name)


func _physics_process(delta: float) -> void:
	if is_destroyed:
		return

	# ── Wander ───────────────────────────────────────────────────────────
	# Every wander_interval seconds, pick a new gentle drift target.
	wander_timer -= delta
	if wander_timer <= 0.0:
		wander_timer = wander_interval + randf_range(-0.5, 0.5)
		current_wander = Vector2(
			randf_range(-drift_speed, drift_speed),
			randf_range(-drift_speed * 0.4, drift_speed * 0.4)
		)

	# Steer toward the wander target (soft steering, not instant snap).
	# Using lerp on velocity gives the organic, floaty feeling.
	linear_velocity = linear_velocity.lerp(current_wander, delta * wander_strength * 0.1)

	# ── Visual Bob ───────────────────────────────────────────────────────
	# Animate the sprite child up and down independently of physics position.
	# This keeps the bob looking smooth even when physics velocity changes.
	bob_offset += bob_speed * delta
	if visual_node:
		visual_node.position.y = sin(bob_offset) * bob_amount
		# Slow visual rotation (we locked physics rotation above)
		visual_node.rotation += spin_speed * delta


# ── Bullet Detection ──────────────────────────────────────────────────────

func _on_area_body_entered(body: Node2D) -> void:
	if is_destroyed:
		return

	if body.is_in_group("bullets"):
		_get_shot()
		return

	# Fallback: detect bullets by collision layer if they're missing the group tag
	if body.has_method("set_velocity") and body.collision_layer == 4:
		_get_shot()


func _get_shot() -> void:
	"""Called when a bullet hits this piece of debris."""
	is_destroyed = true
	freeze = true

	# Award score
	if hud:
		hud.add_score(points)

	# Tell the group this piece is gone
	debris_destroyed.emit(self)

	# Play a satisfying destruction effect then clean up
	_play_destruction_effect()


func _play_destruction_effect() -> void:
	"""Visual feedback — pop + spin + fade out."""
	var tween := create_tween()
	tween.set_parallel(true)

	# Pop scale
	tween.tween_property(self, "scale", Vector2.ONE * 1.6, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2)\
		.set_delay(0.15)

	# Brighten then fade
	if visual_node:
		tween.tween_property(visual_node, "modulate", Color.WHITE * 2.5, 0.08)
		tween.tween_property(visual_node, "modulate:a", 0.0, 0.25).set_delay(0.08)

	tween.finished.connect(queue_free)
