extends AlienTechEffect
class_name QuantumMirrorEffect

## Quantum Mirror — teleports to a mirrored position, invincible until it
## teleports back. Cold mirrors X only; hot mirrors X and Y. `active` is read
## directly by TurtlePlayer for its sprite-modulate priority chain and its
## damage-blocking OR-chain. `ghost` (the translucent marker left at the
## origin) is pulsed from TurtlePlayer._process() since that's where every
## other per-frame visual pulse already lives.

var active: bool = false
var _timer: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var ghost: Sprite2D = null

func activate(player, _slot_index: int) -> void:
	_origin = player.global_position
	_spawn_ghost(player)
	var hot := AlienTechManager.is_tech_hot(AlienTechRegistry.QUANTUM_MIRROR)
	player.global_position = player._clamp_to_boundaries(player._mirrored_position(player.global_position, hot))
	player.linear_velocity *= 0.3
	player.get_node("SfxTeleport").play()
	active = true
	_timer = AlienTechManager.QUANTUM_MIRROR_ACTIVE_DURATION
	player._play_teleport_pop()

func physics_process(player, delta: float) -> void:
	if active:
		_timer -= delta
		if _timer <= 0.0:
			_return_home(player)

## Teleports back to where the mirror was activated from and ends
## invincibility — called when the timer runs out. Not reachable while
## `active` is keeping TurtlePlayer.take_damage() from landing, so this is
## the only way the trip ends.
func _return_home(player) -> void:
	player.global_position = player._clamp_to_boundaries(_origin)
	player.linear_velocity *= 0.3
	player.get_node("SfxTeleport").play()
	active = false
	_clear_ghost()
	player._play_teleport_pop()

## A translucent duplicate of the current sprite frame left behind at
## _origin, so the player can see where they'll return to. Cleared in
## _return_home(); its own alpha pulses gently in TurtlePlayer._process() so
## it clearly reads as an intentional marker, not a glitch.
func _spawn_ghost(player) -> void:
	_clear_ghost()  # defensive — shouldn't already exist, cooldown gates re-activation
	var sprite = player.get_node("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return
	var g := Sprite2D.new()
	g.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	g.global_position = _origin
	g.global_rotation = sprite.global_rotation  # always 0 — sprite stays axis-aligned
	g.modulate = Color(0.85, 0.3, 0.95, 0.35)
	g.z_index = 9  # under the live turtle (15) and motion trails (10)
	player.get_parent().add_child(g)
	ghost = g

func _clear_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
