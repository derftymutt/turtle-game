extends Node
class_name DevTechSeeder

## Dev/QA tool: seeds alien tech slots when a level loads.
## Enable the checkbox in the Inspector, then pick a tech from each slot dropdown.
## Has no effect unless enabled is checked.

@export var enabled: bool = false

@export_enum(
	"(none)",
	"Inertia Dampener", "Bravado", "Lateral Thrust", "Transporter",
	"Saliva Nanobots", "Bubble Shield", "Dermal Regenerator", "Bumper Magnet",
	"Phase Shifter", "Powerup Replicator", "Deflector Shield",
	"Time Freeze", "Flipper Velcro", "Shockwave", "Thing Bringer"
) var slot_a: int = 0

@export_enum(
	"(none)",
	"Inertia Dampener", "Bravado", "Lateral Thrust", "Transporter",
	"Saliva Nanobots", "Bubble Shield", "Dermal Regenerator", "Bumper Magnet",
	"Phase Shifter", "Powerup Replicator", "Deflector Shield",
	"Time Freeze", "Flipper Velcro", "Shockwave", "Thing Bringer"
) var slot_b: int = 0

# Order must match the @export_enum options above (index 0 = "(none)")
const _TECH_IDS: Array[String] = [
	"",
	AlienTechRegistry.INERTIA_DAMPENER,
	AlienTechRegistry.BRAVADO,
	AlienTechRegistry.LATERAL_THRUST,
	AlienTechRegistry.TRANSPORTER,
	AlienTechRegistry.SALIVA_NANOBOTS,
	AlienTechRegistry.BUBBLE_SHIELD,
	AlienTechRegistry.DERMAL_REGEN,
	AlienTechRegistry.BUMPER_MAGNET,
	AlienTechRegistry.PHASE_SHIFTER,
	AlienTechRegistry.POWERUP_REPLICATOR,
	AlienTechRegistry.DEFLECTOR_SHIELD,
	AlienTechRegistry.TIME_FREEZE,
	AlienTechRegistry.FLIPPER_VELCRO,
	AlienTechRegistry.SHOCKWAVE,
	AlienTechRegistry.THING_BRINGER,
]

func _ready() -> void:
	if not enabled:
		return
	var id_a: String = _TECH_IDS[slot_a]
	var id_b: String = _TECH_IDS[slot_b]
	if id_a != "":
		AlienTechManager.assign_tech(id_a, 0)
		print("🔧 DevTechSeeder: slot A → %s" % id_a)
	if id_b != "" and id_b != id_a:
		AlienTechManager.assign_tech(id_b, 1)
		print("🔧 DevTechSeeder: slot B → %s" % id_b)
