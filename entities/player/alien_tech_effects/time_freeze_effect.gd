extends AlienTechEffect
class_name TimeFreezeEffect

## Time Freeze — pauses enemies, projectiles, trash, spawners, and powerups
## across the whole level for a duration (doubled when hot). `active` is
## read directly by TurtlePlayer for its sprite-modulate priority chain.
## AlienTechManager.time_freeze_active is a separate global flag (read by
## several enemies/spawners) kept in sync here exactly as before.

var active: bool = false
var _duration: float = 0.0  # set per-activation; doubled when hot
var _timer: float = 0.0
var _frozen_bodies: Array = []

func activate(player, _slot_index: int) -> void:
	active = true
	AlienTechManager.time_freeze_active = true
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.TIME_FREEZE)
	_duration = AlienTechManager.TIME_FREEZE_ACTIVE_DURATION * (2.0 if hot else 1.0)
	_timer = _duration
	_freeze_world_bodies(player)
	AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_FREEZE, 1.0)
	player._flash(Color(0.5, 0.9, 1.0), 0.3)

func physics_process(_player, delta: float) -> void:
	if not active:
		return
	_timer -= delta
	AlienTechManager.set_passive_bar(AlienTechRegistry.TIME_FREEZE, max(0.0, _timer / _duration))
	if _timer <= 0.0:
		_unfreeze_world_bodies()

func _freeze_world_bodies(player) -> void:
	_frozen_bodies.clear()
	var groups := ["enemies", "bullets", "plane_projectiles", "enemy_projectiles",
				   "trash_clusters", "trash_cluster_pieces", "air_bubbles"]
	for group in groups:
		for node in player.get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node is RigidBody2D:
				var rb := node as RigidBody2D
				_frozen_bodies.append({
					"body":       rb,
					"lin_vel":    rb.linear_velocity,
					"ang_vel":    rb.angular_velocity,
					"was_frozen": rb.freeze,
					"type":       "rigid",
				})
				rb.freeze = true
				rb.set_physics_process(false)
				rb.set_process(false)
			elif node is AnimatableBody2D:
				_frozen_bodies.append({
					"body": node,
					"type": "animatable",
				})
				node.set_physics_process(false)
				node.set_process(false)
	# Pause all spawners FIRST. process_mode=DISABLED propagates to children,
	# which would include trash items — we handle that below.
	var spawner_groups := ["spawners", "trash_spawners"]
	for group in spawner_groups:
		for node in player.get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			_frozen_bodies.append({"body": node, "type": "spawner", "process_mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	# Trash items: their parent spawner is now DISABLED, which would remove them
	# from the physics simulation via inheritance. Override with PROCESS_MODE_ALWAYS
	# so their physics body stays live and bullets can still hit them.
	# is_time_frozen flag zeroes velocity each frame so they appear frozen.
	# Spawners are appended before trash items so unfreeze restores spawners first,
	# letting INHERIT correctly flow back when trash items are restored.
	for node in player.get_tree().get_nodes_in_group("trash_items"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is TrashItem:
			var trash := node as TrashItem
			_frozen_bodies.append({
				"body":         trash,
				"lin_vel":      trash.linear_velocity,
				"ang_vel":      trash.angular_velocity,
				"process_mode": trash.process_mode,
				"type":         "trash_frozen",
			})
			trash.linear_velocity = Vector2.ZERO
			trash.angular_velocity = 0.0
			trash.is_time_frozen = true
			trash.process_mode = Node.PROCESS_MODE_ALWAYS
	# Powerups: reward powerups are children of the trash sequence spawner too
	# (spawn_powerup() adds them under the same node trash items live under),
	# so they have the exact same disabled-parent problem — handled the same way.
	for node in player.get_tree().get_nodes_in_group("powerups"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is RigidBody2D:
			var pu := node as RigidBody2D
			_frozen_bodies.append({
				"body":         pu,
				"lin_vel":      pu.linear_velocity,
				"ang_vel":      pu.angular_velocity,
				"was_frozen":   pu.freeze,
				"process_mode": pu.process_mode,
				"type":         "powerup_frozen",
			})
			pu.freeze = true
			pu.linear_velocity = Vector2.ZERO
			pu.angular_velocity = 0.0
			pu.set_physics_process(false)
			pu.set_process(false)
			pu.process_mode = Node.PROCESS_MODE_ALWAYS

func _unfreeze_world_bodies() -> void:
	for entry in _frozen_bodies:
		var body = entry["body"]
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		match entry["type"]:
			"rigid":
				var rb := body as RigidBody2D
				rb.freeze = entry["was_frozen"]
				if not entry["was_frozen"]:
					rb.linear_velocity = entry["lin_vel"]
					rb.angular_velocity = entry["ang_vel"]
				rb.set_physics_process(true)
				rb.set_process(true)
			"trash_frozen":
				var trash := body as TrashItem
				trash.is_time_frozen = false
				trash.process_mode = entry["process_mode"]
				trash.linear_velocity = entry["lin_vel"]
				trash.angular_velocity = entry["ang_vel"]
			"animatable":
				body.set_physics_process(true)
				body.set_process(true)
			"spawner":
				body.process_mode = entry["process_mode"]
			"powerup_frozen":
				var pu := body as RigidBody2D
				pu.process_mode = entry["process_mode"]
				pu.freeze = entry["was_frozen"]
				if not entry["was_frozen"]:
					pu.linear_velocity = entry["lin_vel"]
					pu.angular_velocity = entry["ang_vel"]
				pu.set_physics_process(true)
				pu.set_process(true)
	_frozen_bodies.clear()
	active = false
	AlienTechManager.time_freeze_active = false
	AlienTechManager.clear_passive_bar(AlienTechRegistry.TIME_FREEZE)
