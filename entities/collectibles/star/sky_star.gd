# sky_star.gd
extends BaseCollectible
class_name SkyStar

## Sky Star collectible - floats stationary in the sky, never sinks
## Worth slightly more than a regular ocean star's base value
## Managed by SkyStarSeeder for initial seeding and respawning

@export var sky_point_value: int = 20

signal star_collected

func _collectible_ready():
	# Override base physics — sky stars hover in place
	gravity_scale = 0.0
	linear_damp = 100.0
	angular_damp = 100.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

	# Slightly gentler bob than sinking stars
	bob_amount = 1.5

	point_value = sky_point_value

	var animated_sprite = get_node_or_null("AnimatedSprite2D")
	if animated_sprite:
		animated_sprite.play("default")

func _collectible_physics_process(_delta: float):
	# Kill any residual velocity each frame so physics drift can't accumulate
	if linear_velocity.length_squared() > 1.0:
		linear_velocity = Vector2.ZERO
	if angular_velocity != 0.0:
		angular_velocity = 0.0

func _on_collected(collector):
	# Award points immediately
	if collector.has_method("add_score"):
		collector.add_score(point_value)

	# Notify seeder before tweening so it can recount right away
	star_collected.emit()

	# Satisfying shrink-to-player animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	tween.finished.connect(func():
		print("🌟 Collected sky star! +%d points" % point_value)
		queue_free()
	)
