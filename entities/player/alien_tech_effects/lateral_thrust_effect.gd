extends AlienTechEffect
class_name LateralThrustEffect

## Lateral Thrust — an instant horizontal dash impulse. Suppresses ocean
## physics for a brief window (read directly by TurtlePlayer.apply_ocean_effects())
## so the dash isn't immediately killed by water drag/buoyancy.

const DURATION: float = 0.05
const FORCE: float = 600.0

var active: bool = false
var _timer: float = 0.0

func activate(player, _slot_index: int) -> void:
	active = true
	_timer = DURATION

	# Determine left or right purely from horizontal input, then facing, then velocity.
	var h_input := Input.get_axis("move_left", "move_right")
	var thrust_sign: float

	if abs(h_input) > 0.1:
		thrust_sign = sign(h_input)
		if GameSettings.thrust_inverted:
			thrust_sign = -thrust_sign
	else:
		# Derive from facing direction suffix ("e"/"ne"/"se" → right, rest → left)
		var facing_vec = player._direction_suffix_to_vector(player.facing_direction)
		if facing_vec.x != 0.0:
			thrust_sign = sign(facing_vec.x)
		elif player.linear_velocity.x != 0.0:
			thrust_sign = sign(player.linear_velocity.x)
		else:
			thrust_sign = 1.0  # default right if no signal

	player.linear_velocity = Vector2.ZERO
	player.apply_central_impulse(Vector2(thrust_sign * FORCE, 0.0))
	player._flash(Color.WHITE, 0.2)

func physics_process(_player, delta: float) -> void:
	if active:
		_timer -= delta
		if _timer <= 0:
			active = false
