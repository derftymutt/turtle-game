extends RigidBody2D
class_name BaseEnemy

## Base class for all enemies - handles common behavior
## Child classes override specific methods for custom behavior

# Collision behavior
@export var pass_through_player: bool = false  # If true, player can pass through but still takes damage

# Health system
@export var max_health: float = 30.0
@export var is_invincible: bool = false  # For enemies that can't be killed

# Damage dealing
@export var contact_damage: float = 25.0
@export var knockback_force: float = 300.0

# Visual feedback
@export var damage_flash_duration: float = 0.1
@export var damage_flash_color: Color = Color.RED

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

## Override in child classes for custom initialization
func _enemy_ready():
	pass

## Handle incoming damage from bullets/other sources
func take_damage(amount: float):
	if is_invincible:
		# Still show visual feedback but don't take damage
		_play_invincible_feedback()
		return
	
	current_health -= amount
	_play_damage_feedback()
	
	if current_health <= 0:
		die()

## Visual feedback when damaged
func _play_damage_feedback():
	if not sprite:
		return
	
	sprite.modulate = damage_flash_color
	await get_tree().create_timer(damage_flash_duration).timeout
	if sprite and is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

## Visual feedback when invincible (bounce off, sparkle, etc.)
func _play_invincible_feedback():
	if not sprite:
		return
	
	# Quick yellow flash to show "can't hurt me"
	sprite.modulate = Color.YELLOW
	await get_tree().create_timer(0.05).timeout
	if sprite and is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

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
