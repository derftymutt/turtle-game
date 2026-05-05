extends BaseCollectible
class_name AlienTechPiece

@export var glow_speed: float = 3.0
@export var glow_amount: float = 0.4
@export var spin_speed: float = 1.2

var _glow_offset: float = 0.0

func _collectible_ready():
	point_value = 50
	sink_speed = 20.0
	sway_amount = 8.0
	sway_speed = 0.5
	bob_amount = 2.0
	bob_speed = 1.5
	mass = 1.2
	_glow_offset = randf() * TAU
	angular_velocity = spin_speed
	add_to_group("alien_tech_pieces")

func _collectible_physics_process(_delta: float):
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0 and depth < 160:
			apply_central_force(Vector2(0, sink_speed))
			sway_offset += sway_speed * _delta
			apply_central_force(Vector2(sin(sway_offset) * sway_amount, 0))

	_glow_offset += glow_speed * _delta
	if visual_node:
		var g = 1.0 + sin(_glow_offset) * glow_amount
		visual_node.modulate = Color(g, g * 0.9, g * 0.6, 1.0)

func _on_collected(collector):
	AlienTechManager.collect_piece()
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_score(point_value)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if visual_node:
		visual_node.modulate = Color(3.0, 2.5, 1.0, 1.0)
	tween.finished.connect(queue_free)
