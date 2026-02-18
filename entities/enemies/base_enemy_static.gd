extends AnimatableBody2D
class_name BaseEnemyStatic

## Base class for static enemies that don't move via physics
## Provides health, damage dealing, and visual feedback like BaseEnemy
## Child classes control movement manually via position/velocity

# Collision behavior
@export var pass_through_player: bool = false

# Health system
@export var max_health: float = 30.0
@export var is_invincible: bool = false

# Damage dealing
@export var contact_damage: float = 25.0
@export var knockback_force: float = 300.0

# Visual feedback
@export var damage_flash_duration: float = 0.3
@export var damage_flash_color: Color = Color.CHARTREUSE

# Internal state
var current_health: float
var sprite: Node2D = null
var damage_area: Area2D = null

func _ready():
	current_health = max_health
	add_to_group("enemies")
	
	# Find sprite (AnimatedSprite2D or Sprite2D)
	sprite = get_node_or_null("AnimatedSprite2D")
	if not sprite:
		sprite = get_node_or_null("Sprite2D")
	
	# Set up damage area if it exists
	damage_area = get_node_or_null("DamageArea")
	if damage_area:
		damage_area.body_entered.connect(_on_damage_area_entered)
		damage_area.collision_layer = 0
		damage_area.collision_mask = 1  # Only detect layer 1 (player)
	
	# Call child class setup
	_enemy_ready()
	
	print(name, " (STATIC) collision: layer=", collision_layer, " mask=", collision_mask, 
		" | pass_through_player=", pass_through_player, " | invincible=", is_invincible)

## Override in child classes for custom initialization
func _enemy_ready():
	pass

## Handle incoming damage from bullets/other sources
func take_damage(amount: float):
	if is_invincible:
		_play_invincible_feedback()
		return
	
	current_health -= amount
	_play_damage_feedback()
	
	if current_health <= 0:
		die()

## Visual feedback when damaged
var _is_playing_damage_animation: bool = false

## Visual feedback when damaged
func _play_damage_feedback():
	if not sprite or not sprite is AnimatedSprite2D:
		# Fallback for Sprite2D - just flash
		if sprite:
			sprite.modulate = damage_flash_color
			await get_tree().create_timer(damage_flash_duration).timeout
			if sprite and is_instance_valid(sprite):
				sprite.modulate = Color.WHITE
		return
	
	var animated_sprite := sprite as AnimatedSprite2D
	
	# Don't restart if already playing - just let it finish
	if _is_playing_damage_animation:
		return
	
	_is_playing_damage_animation = true
	
	# Save what we were doing before the hit
	var previous_animation: String = animated_sprite.animation
	var previous_frame: int = animated_sprite.frame
	
	# Play damage animation if it exists
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("damage"):
		animated_sprite.play("damage")
		await animated_sprite.animation_finished
	else:
		# Fallback: color flash
		animated_sprite.modulate = damage_flash_color
		await get_tree().create_timer(damage_flash_duration).timeout
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.modulate = Color.WHITE
	
	_is_playing_damage_animation = false
	
	if not animated_sprite or not is_instance_valid(animated_sprite):
		return
	
	# Decide what to play after the damage animation
	_resume_animation_after_damage(animated_sprite, previous_animation, previous_frame)

## Determines the correct animation to resume after taking damage
func _resume_animation_after_damage(animated_sprite: AnimatedSprite2D, previous_animation: String, previous_frame: int) -> void:
	# Near-death check: 10hp or less triggers near_death animation if available
	if current_health <= 10.0 and animated_sprite.sprite_frames.has_animation("near_death"):
		animated_sprite.play("near_death")
		return
	
	# Otherwise restore previous animation
	# Only restore frame if the animation loops - for one-shots it makes more sense to restart
	animated_sprite.play(previous_animation)
	if animated_sprite.sprite_frames.get_animation_loop(previous_animation):
		animated_sprite.frame = previous_frame

## Visual feedback when invincible
func _play_invincible_feedback():
	if not sprite:
		return
	
	# Shake effect when hit
	var original_pos = sprite.position
	var shake_amount = 3.0
	
	# Quick shake sequence
	for i in range(4):
		if sprite and is_instance_valid(sprite):
			sprite.position = original_pos + Vector2(
				randf_range(-shake_amount, shake_amount),
				randf_range(-shake_amount, shake_amount)
			)
			await get_tree().create_timer(0.03).timeout
			
	if sprite and is_instance_valid(sprite):
		sprite.position.x = original_pos.x

## Handle player collision in damage area
func _on_damage_area_entered(body: Node2D):
	if body.is_in_group("player") and body.has_method("take_damage"):
		_deal_damage_to_player(body)

## Deal damage and knockback to player
func _deal_damage_to_player(player: Node2D):
	player.take_damage(contact_damage)
	
	# Apply knockback
	var knockback_dir = (player.global_position - global_position).normalized()
	if player is RigidBody2D:
		player.apply_central_impulse(knockback_dir * knockback_force)

## Override in child classes for custom death behavior
func die():
	# Default death: simple fade out and remove
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
