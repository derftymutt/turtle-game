extends RigidBody2D

## Plasma Spit's beam projectile. Unlike a regular bullet it never decays
## (straight line at constant speed for its whole lifetime) and its collision
## mask excludes World_Player, so it passes straight through walls, dead
## walls, bumpers, and flippers. It also pierces every enemy/trash/flora/
## bubble it touches instead of stopping at the first one.

@export var lifetime: float = 0.3  # shorter range than bullet.gd's decayed real travel distance
@export var damage: float = 10.0
@export var is_homing: bool = false
@export var homing_turn_speed_deg: float = 150.0  # overridden when Saliva Nanobots is hot
@export var bravado_stamina_restore: float = 20.0

var velocity: Vector2 = Vector2.ZERO
var hit_targets: Array = []  # enemies already damaged — piercing beam, never double-hit the same one

func _ready():
	# Physics setup
	gravity_scale = 0.0
	linear_damp = 0.0
	lock_rotation = true
	mass = 0.01
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	# CRITICAL: Enable contact monitoring for body_entered signal
	contact_monitor = true
	max_contacts_reported = 8

	add_to_group("bullets")

	# NOTE: Collision layers MUST be set in Inspector:
	# - Collision Layer: 4 (bullets — same as bullet.tscn)
	# - Collision Mask: 3 + 8 (enemies + trash) — deliberately NOT 1 (world),
	#   so the beam passes straight through walls/dead walls/bumpers/flippers.

	body_entered.connect(_on_body_entered)

	linear_velocity = velocity

	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func set_velocity(vel: Vector2):
	velocity = vel
	linear_velocity = vel

func _physics_process(delta):
	# No water drag: a beam holds its speed for its whole (short) range.
	if is_homing:
		_apply_homing(delta)

	if linear_velocity.length() > 10:
		rotation = linear_velocity.angle()

func _apply_homing(delta: float):
	const HOMING_RANGE: float = 200.0

	var nearest: Node2D = null
	var nearest_dist: float = HOMING_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or enemy in hit_targets:
			continue
		var d = global_position.distance_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy

	if not nearest:
		return

	var speed = linear_velocity.length()
	if speed < 1.0:
		return

	var to_enemy = (nearest.global_position - global_position).normalized()
	var angle_to = linear_velocity.normalized().angle_to(to_enemy)
	var max_rot = deg_to_rad(homing_turn_speed_deg) * delta
	linear_velocity = linear_velocity.rotated(clamp(angle_to, -max_rot, max_rot))

func _on_body_entered(body):
	# Ignore player
	if body.is_in_group("player"):
		return

	# Pierce through trash items — destroy them and keep going
	if body.is_in_group("trash_items"):
		if body.has_method("destroy_trash"):
			body.destroy_trash()
		return

	# Pop air bubbles and keep going
	if body.is_in_group("air_bubbles") and body.has_method("pop_from_bullet"):
		body.pop_from_bullet()
		return

	# Damage ocean flora and keep going
	if body.is_in_group("ocean_flora") and body.has_method("take_damage"):
		body.take_damage(damage)
		return

	# Pierce through enemies — damage each one once, keep going
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		if body in hit_targets:
			return
		hit_targets.append(body)
		body.take_damage(damage)
		_apply_bravado_hit(body)
		return

	# Collision mask excludes World_Player, so walls/dead walls/bumpers/
	# flippers never reach here in the first place — nothing else to handle.

func _apply_bravado_hit(body) -> void:
	if not AlienTechManager.is_tech_active(AlienTechRegistry.BRAVADO) or body.get("is_invincible"):
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.current_energy = min(hud.max_energy, hud.current_energy + bravado_stamina_restore)
		hud.update_energy(hud.current_energy, hud.max_energy)
	if AlienTechManager.is_tech_hot(AlienTechRegistry.BRAVADO):
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("grant_bravado_iframe"):
			player.grant_bravado_iframe()
