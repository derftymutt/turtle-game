# star_collectible.gd
extends BaseCollectible
class_name StarCollectible

## Star collectible - gives points immediately on pickup
## Sinks to ocean floor and becomes more valuable

@export var point_value_valuable: int = 100
@export var floor_despawn_time: float = 10.0
@export var disable_floor_despawn: bool = false

var despawning: bool = false
var on_floor: bool = false
var floor_timer: float = 0.0
var is_valuable: bool = false
var animation_set: bool = false

func _collectible_physics_process(delta):
	if despawning:
		return
	
	# Check if settled on floor
	var is_near_floor = global_position.y > 160
	var is_mostly_still = linear_velocity.length() < 50
	
	if is_near_floor and is_mostly_still:
		if not on_floor:
			on_floor = true
			is_valuable = true
			floor_timer = 0.0
		
		# Only despawn if not disabled (seeded collectibles don't despawn)
		if not disable_floor_despawn:
			floor_timer += delta
			
			if floor_timer >= floor_despawn_time:
				despawning = true
				start_despawn()
				return
	else:
		on_floor = false
		floor_timer = 0.0
	
	# Apply sinking and swaying forces
	if ocean:
		var depth = ocean.get_depth(global_position)
		if depth > 0 and depth < 160:
			apply_central_force(Vector2(0, sink_speed))
			
			sway_offset += sway_speed * delta
			var sway_force = sin(sway_offset) * sway_amount
			apply_central_force(Vector2(sway_force, 0))
	
	# Play valuable animation when becoming valuable
	if is_valuable and not animation_set:
		var animated_sprite = get_node_or_null("AnimatedSprite2D")
		if animated_sprite and animated_sprite.animation != "valuable":
			animated_sprite.play("valuable")
			animation_set = true
		point_value = point_value_valuable

func _on_collected(collector):
	"""Stars give points immediately"""
	# Award score through player
	if collector.has_method("add_score"):
		collector.add_score(point_value)
	
	# Tween to turtle with satisfying animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collector.global_position, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(func():
		print("⭐ Collected star! +%d points" % point_value)
		queue_free()
	)

func start_despawn():
	collected = true
	freeze = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 1.0)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position:y", global_position.y + 30, 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.3, 0.3), 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

func make_valuable_immediately():
	"""Used by FloorSeeder for pre-placed stars"""
	is_valuable = true
	on_floor = true
	point_value = point_value_valuable
	disable_floor_despawn = true
	z_index = 100
	
	var animated_sprite = get_node_or_null("AnimatedSprite2D")
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("valuable"):
		animated_sprite.play("valuable")
		animation_set = true
	
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	linear_damp = 20.0
	gravity_scale = 0.0
