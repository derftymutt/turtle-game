extends AlienTechEffect
class_name TransporterEffect

## Transporter — brief windup, then teleports in the aimed direction and
## grants short invincibility. A hit during the windup cancels the teleport
## (see cancel_on_damage()) without landing damage on it separately.
##
## Arrival also shocks the player for the same duration as the invincibility
## window (the same suspend_control() stun Disturbance Wave gives itself on a
## cold cast) — a nerf so the invincibility can't be chained into free,
## controlled repositioning. suspend_control() disables the whole input block
## in TurtlePlayer, including the tech-slot activation call, so while hot
## (0s cooldown) this also blocks re-triggering Transporter until the shock
## from the previous cast wears off, without any extra cooldown bookkeeping.
##
## `windup` and `invincible` are read directly by TurtlePlayer for its
## sprite-modulate priority chain and its damage-blocking OR-chain — they
## stay public flags rather than query methods so those call sites don't
## need to change shape.

const DISTANCE: float = 150.0
const INVINCIBLE_DURATION: float = 0.75
const WINDUP: float = 0.18

var invincible: bool = false
var _invincible_timer: float = 0.0
var windup: bool = false
var _canceled: bool = false

func activate(player, _slot_index: int) -> void:
	# Direction priority: active input > current velocity > facing direction
	var movement_input = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var dir: Vector2
	if movement_input.length() > 0.1:
		dir = movement_input.normalized()
		if GameSettings.thrust_inverted:
			dir = -dir
	elif player.linear_velocity.length() > 30.0:
		dir = player.linear_velocity.normalized()
	else:
		dir = player._direction_suffix_to_vector(player.facing_direction)

	# Windup: brief visual telegraph — player is vulnerable during this window
	windup = true
	_canceled = false
	await player.get_tree().create_timer(WINDUP).timeout
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	windup = false

	if _canceled:
		_canceled = false
		return

	# Teleport: ignore all regular geometry, clamp to world boundaries.
	# If there's no room (already at the edge), the clamp lands us at the wall — player's problem.
	var raw_target = player.global_position + dir * DISTANCE
	player.global_position = player._clamp_to_boundaries(raw_target)
	player.get_node("SfxTeleport").play()
	player.linear_velocity *= 0.3
	invincible = true
	_invincible_timer = INVINCIBLE_DURATION
	player.suspend_control(INVINCIBLE_DURATION)

	# Scale pop on arrival
	var sprite = player.get_node("AnimatedSprite2D")
	if sprite:
		var tween = player.create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.35, 1.35), 0.07)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)

func physics_process(_player, delta: float) -> void:
	if invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			invincible = false

## Real damage lands — abort an in-progress windup so it doesn't complete
## the teleport after the hit. Not called when a hit is absorbed by
## something else (e.g. Bubble Shield) before reaching this point.
func cancel_on_damage(_player) -> void:
	if windup:
		_canceled = true
