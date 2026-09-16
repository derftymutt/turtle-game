extends AlienTechEffect
class_name DeflectorShieldEffect

## Deflector Shield — a repulsion field around the player that knocks back
## enemies and enemy/player bullets. The Area2D and visual ring are created
## once in setup() (called from TurtlePlayer._ready()) and reused across
## activations; activate() just resizes and re-enables them. `active` is
## read directly by TurtlePlayer for its damage-blocking OR-chain and its
## sprite-modulate priority chain.

const DURATION: float = 5.0    # seconds active — tweak for feel
const RADIUS: float = 35.0     # px repulsion radius — tweak for feel
const FORCE: float = 1000.0    # repulsion force — tweak for feel

var active: bool = false
var _timer: float = 0.0
var _area: Area2D = null
var visual: Line2D = null

## Called once from TurtlePlayer._ready() to create the runtime Area2D and
## visual ring, reused across every activation for the rest of the node's life.
func setup(player) -> void:
	_area = Area2D.new()
	_area.name = "DeflectorArea"
	_area.collision_layer = 0
	_area.collision_mask = 4 | 8 | 64  # Layer 3 (enemies) + Layer 4 (player bullets) + Layer 7 (enemy bullets)
	_area.monitoring = true
	_area.monitorable = false

	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	col.shape = circle
	_area.add_child(col)
	player.add_child(_area)

	_area.body_entered.connect(_on_body_entered.bind(player))

	# Visual ring — a closed Line2D circle
	visual = Line2D.new()
	visual.name = "DeflectorVisual"
	var pts: PackedVector2Array = []
	var segs := 36
	for i in range(segs + 1):
		var a := i * TAU / segs
		pts.append(Vector2(cos(a), sin(a)) * RADIUS)
	visual.points = pts
	visual.default_color = Color(0.3, 0.7, 1.0, 0.7)
	visual.width = 1.5
	visual.z_as_relative = false
	visual.z_index = 12
	visual.visible = false
	player.add_child(visual)

func activate(_player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.DEFLECTOR_SHIELD)
	_resize(RADIUS * (2.0 if hot else 1.0))
	active = true
	_timer = DURATION
	if visual:
		visual.visible = true

func physics_process(player, delta: float) -> void:
	if not active:
		return
	_timer -= delta
	var ratio: float = _timer / DURATION
	AlienTechManager.set_passive_bar(AlienTechRegistry.DEFLECTOR_SHIELD, max(0.0, ratio))
	_repel(player, delta)
	if _timer <= 0.0:
		active = false
		AlienTechManager.clear_passive_bar(AlienTechRegistry.DEFLECTOR_SHIELD)
		if visual:
			visual.visible = false

## Called from TurtlePlayer._process() for the pulsing ring color while active.
func update_visual_pulse() -> void:
	if active and visual:
		var pulse := (sin(Time.get_ticks_msec() * 0.008) + 1.0) * 0.5
		visual.default_color = Color(0.3, 0.7, 1.0, 0.4 + pulse * 0.45)

## Rebuilds the collision shape and visual ring at the given radius. Called
## on every activation (not just setup) so hot's doubled radius applies even
## though the Area2D was created once at spawn.
func _resize(radius: float) -> void:
	if _area:
		var col := _area.get_child(0) as CollisionShape2D
		if col and col.shape is CircleShape2D:
			(col.shape as CircleShape2D).radius = radius
	if visual:
		var pts: PackedVector2Array = []
		var segs := 36
		for i in range(segs + 1):
			var a := i * TAU / segs
			pts.append(Vector2(cos(a), sin(a)) * radius)
		visual.points = pts

func _on_body_entered(body: Node2D, player) -> void:
	if not active:
		return
	if body == player or body.is_in_group("player"):
		return
	if body.is_in_group("submarine_boss"):
		return
	var dir: Vector2 = body.global_position - player.global_position
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(dir * 500.0)
	elif body is CharacterBody2D:
		var cb := body as CharacterBody2D
		cb.velocity = dir * max(cb.velocity.length(), 250.0)
	elif body is AnimatableBody2D:
		# Immediate positional kick on entry — no physics forces on AnimatableBody2D
		body.global_position += dir * 12.0

func _repel(player, delta: float) -> void:
	if not _area:
		return
	for body in _area.get_overlapping_bodies():
		if body == player or body.is_in_group("player"):
			continue
		if body.is_in_group("submarine_boss"):
			continue
		var dir: Vector2 = body.global_position - player.global_position
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		else:
			dir = dir.normalized()
		if body is RigidBody2D:
			(body as RigidBody2D).apply_central_force(dir * FORCE)
		elif body is CharacterBody2D:
			var cb := body as CharacterBody2D
			cb.velocity = dir * max(cb.velocity.length(), FORCE * 0.4)
		elif body is AnimatableBody2D:
			# AnimatableBody2D (e.g. Crocodile) has no physics forces — push via position
			body.global_position += dir * FORCE * 0.3 * delta
