extends AlienTechEffect
class_name ShockwaveEffect

## Shockwave — instant full-screen nuke. Damages every enemy, drains energy
## to zero, and either stuns the player briefly (cold) or costs a heart
## (hot, trading the stun for self-damage so it isn't a free-spam nuke).
## Pure one-shot: no persistent state, nothing to tick in physics_process().

func activate(player, _slot_index: int) -> void:
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.SHOCKWAVE)
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.has_method("take_damage"):
			enemy.take_damage(10.0)
	if player.hud:
		player.hud.current_energy = 0.0
		player.hud.update_energy(0.0, player.hud.max_energy)
	if hot:
		# Hot trade-off: no self-stun, but it costs a heart every use (still
		# subject to the normal heart-damage iframe, which is what keeps this
		# from being a truly free-spam full-screen nuke).
		player.take_damage(1.0, false, "fried by your own shockwave")
	else:
		player.suspend_control(1.0)
	_spawn_visual(player)
	player._flash(Color(1.0, 0.55, 0.1), 0.2)

func _spawn_visual(player) -> void:
	var ring := Line2D.new()
	var segs := 32
	var pts: PackedVector2Array = []
	for i in range(segs + 1):
		var a := i * TAU / segs
		pts.append(Vector2(cos(a), sin(a)))
	ring.points = pts
	ring.default_color = Color(1.0, 0.55, 0.1, 0.85)
	ring.width = 2.5
	ring.z_as_relative = false
	ring.z_index = 18
	player.get_parent().add_child(ring)
	ring.global_position = player.global_position
	var tween: Tween = player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE * 400.0, 0.5)
	tween.tween_property(ring, "modulate:a", 0.0, 0.5)
	tween.finished.connect(ring.queue_free)
