# ufo_workshop.gd
extends StaticBody2D
class_name UFOWorkshop

## Static workshop at ocean surface where UFO pieces are delivered

#@export var workshop_radius: float = 30.0  # For reference only
#@export var surface_y_position: float = -126.0  # Position hint

# Visual feedback
@export var idle_color: Color = Color(0.3, 0.6, 1.0, 0.8)  # Blue glow
@export var active_color: Color = Color(1.0, 0.8, 0.0, 1.0)  # Gold when player nearby
@export var pulse_speed: float = 2.0
@export var pulse_amount: float = 0.2

# Node references (set up in scene editor)
@onready var delivery_area: Area2D = $DeliveryArea
@onready var sprite: Node2D = $Sprite2D  # or AnimatedSprite2D

# Internal state
var is_player_nearby_with_piece: bool = false
var pulse_offset: float = 0.0

func _ready():
	add_to_group("workshop")
	
	# Position at surface (optional - can also set in editor)
	#global_position.y = surface_y_position
	
	# Verify scene structure
	if not delivery_area:
		push_error("UFOWorkshop: Missing DeliveryArea child! Add it in the scene editor.")
		return
	
	if not sprite:
		push_warning("UFOWorkshop: No sprite found! Add Sprite2D or AnimatedSprite2D child.")
	
	# Connect delivery area signals
	delivery_area.body_entered.connect(_on_delivery_area_entered)
	delivery_area.body_exited.connect(_on_delivery_area_exited)
	
	# Connect to LevelManager signals
	if LevelManager:
		LevelManager.piece_delivered.connect(_on_piece_delivered)
		LevelManager.level_complete.connect(_on_level_complete)
	
	print("🛠️ UFO Workshop ready at surface (y=%.1f)" % global_position.y)

func _process(delta):
	# Visual pulsing when player nearby with piece
	if is_player_nearby_with_piece:
		pulse_offset += pulse_speed * delta
		_apply_active_visuals()
	else:
		_apply_idle_visuals()

func _on_delivery_area_entered(body: Node2D):
	"""Player entered delivery zone"""
	if not body.is_in_group("player"):
		return
	
	# Check if carrying a piece
	if GameManager.is_carrying_piece and GameManager.carried_piece:
		is_player_nearby_with_piece = true
		attempt_delivery()

func _on_delivery_area_exited(body: Node2D):
	"""Player left delivery zone"""
	if body.is_in_group("player"):
		is_player_nearby_with_piece = false

func attempt_delivery():
	"""Try to deliver the carried UFO piece"""
	if not GameManager.is_carrying_piece:
		return
	
	var piece = GameManager.carried_piece
	if not piece or not is_instance_valid(piece):
		push_warning("Workshop: Invalid carried piece reference!")
		GameManager.is_carrying_piece = false
		GameManager.carried_piece = null
		return
	
	# Successful delivery!
	deliver_piece(piece)

func deliver_piece(piece: UFOPiece):
	"""Accept the UFO piece and remove it from world"""
	print("🛠️ Workshop received UFO piece!")
	
	# Play satisfying delivery animation
	_play_delivery_animation(piece)
	
	# Notify LevelManager
	LevelManager.deliver_piece()
	
	# Clear carrier state
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	
	# Update piece state
	piece.is_carried = false
	piece.carrier = null
	

	
	# Remove piece from world after animation
	await get_tree().create_timer(0.5).timeout
	if piece and is_instance_valid(piece):
		piece.queue_free()

func _play_delivery_animation(piece: UFOPiece):
	"""Satisfying 'snap into place' animation"""
	if not piece or not is_instance_valid(piece):
		return
	
	# Tween piece to workshop center
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(piece, "global_position", global_position, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	tween.tween_property(piece, "rotation", piece.rotation + TAU, 0.3)\
		.set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(piece, "scale", Vector2.ZERO, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Flash workshop sprite
	if sprite:
		var sprite_tween = create_tween()
		sprite_tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)
		sprite_tween.tween_property(sprite, "modulate", active_color, 0.2)

func _apply_active_visuals():
	"""Pulsing gold glow when player nearby with piece"""
	if not sprite:
		return
	
	var pulse_scale = 1.0 + (sin(pulse_offset) * pulse_amount)
	sprite.scale = Vector2.ONE * pulse_scale
	sprite.modulate = active_color

func _apply_idle_visuals():
	"""Gentle blue glow when idle"""
	if not sprite:
		return
	
	sprite.scale = Vector2.ONE
	sprite.modulate = idle_color

func _on_piece_delivered(pieces_collected: int, pieces_needed: int):
	"""React to piece delivery (visual feedback)"""
	print("🛠️ Workshop: %d/%d pieces" % [pieces_collected, pieces_needed])

func _on_level_complete():
	"""React to level completion"""
	print("🛠️ Workshop: Level complete! UFO assembled!")
