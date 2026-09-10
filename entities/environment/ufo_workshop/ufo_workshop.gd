# ufo_workshop.gd
extends StaticBody2D
class_name UFOWorkshop

const _SFX_BEAT_LEVEL = preload("res://assets/sounds/sfx/beat level_1.ogg")

## Static workshop at ocean surface where UFO pieces are delivered

#@export var workshop_radius: float = 30.0  # For reference only
#@export var surface_y_position: float = -126.0  # Position hint

## Multi-instance selection
## A level may contain several UFO Workshop instances placed in different spots.
## On load, exactly one is kept (chosen at random) and the rest remove themselves,
## so gameplay always sees a single workshop. Higher weight = more likely to be
## the one that stays. Levels with a single instance are unaffected.
@export var selection_weight: float = 1.0

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
var _sfx_beat: AudioStreamPlayer

func _ready():
	add_to_group("ufo_workshop_candidate")
	# Elect a single active workshop for this level load. Every instance defers
	# the same call; a deterministic leader performs the pick once, after all
	# instances have registered themselves.
	call_deferred("_elect_single_workshop")

	add_to_group("workshop")
	_sfx_beat = AudioStreamPlayer.new()
	_sfx_beat.stream = _SFX_BEAT_LEVEL
	_sfx_beat.volume_db = 0.0
	add_child(_sfx_beat)
	
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

func _elect_single_workshop() -> void:
	"""Keep exactly one workshop instance per level load; free the rest."""
	var candidates := get_tree().get_nodes_in_group("ufo_workshop_candidate")
	candidates = candidates.filter(func(w: Node) -> bool:
		return is_instance_valid(w) and not w.is_queued_for_deletion())
	if candidates.size() <= 1:
		return  # Single instance (or none) — nothing to cull

	# Only the leader (lowest instance id) runs the pick, so every instance's
	# deferred call resolves to the same outcome.
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	if candidates[0] != self:
		return

	var total_weight := 0.0
	for w in candidates:
		total_weight += maxf(0.0, w.selection_weight)

	var chosen: Node = candidates[0]
	if total_weight > 0.0:
		var roll := randf() * total_weight
		for w in candidates:
			roll -= maxf(0.0, w.selection_weight)
			if roll <= 0.0:
				chosen = w
				break

	for w in candidates:
		if w != chosen:
			w.queue_free()

	print("🛠️ UFO Workshop: %d candidates, kept '%s'" % [candidates.size(), chosen.name])

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

	var is_final := (LevelManager.pieces_collected + 1 >= LevelManager.pieces_needed)
	if is_final:
		# Final piece: play the level-complete fanfare immediately and silence everything else
		_sfx_beat.play()
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.begin_level_completion()
	else:
		$SfxDeliver.play()

	# 🆕 AWARD POINTS HERE (not on pickup!)
	piece.award_delivery_points()
	GameManager.spawn_floating_score(global_position, piece.point_value)

	# Notify LevelManager
	LevelManager.deliver_piece()
	
	# Play satisfying delivery animation
	_play_delivery_animation(piece)
	
	# Clear carrier state
	GameManager.is_carrying_piece = false
	GameManager.carried_piece = null
	
	# Update piece state
	piece.is_carried = false
	piece.carrier = null
	
	# Notify LevelManager
	#LevelManager.deliver_piece()
	
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
