extends Node

## Autoload: AlienTechRegistry
## Pure data — all tech definitions. Never holds run state.
## Add to Project Settings > Autoload as "AlienTechRegistry" (BEFORE AlienTechManager)

# ─── Tech ID constants ───────────────────────────────────────────────────────

const INERTIA_DAMPENER    := "inertia_dampener"
const BRAVADO             := "bravado"
const LATERAL_THRUST      := "lateral_thrust"
const TRANSPORTER         := "transporter"
const SALIVA_NANOBOTS     := "saliva_nanobots"
const BUBBLE_SHIELD       := "bubble_shield"
const BUMPER_MAGNET       := "bumper_magnet"
const DERMAL_REGEN        := "dermal_regen"
const PHASE_SHIFTER       := "phase_shifter"
const POWERUP_REPLICATOR  := "powerup_replicator"
const DEFLECTOR_SHIELD    := "deflector_shield"
const TIME_FREEZE         := "time_freeze"
const FLIPPER_VELCRO      := "flipper_velcro"
const SHOCKWAVE           := "shockwave"
const THING_BRINGER       := "thing_bringer"

# ─── Tech definitions ────────────────────────────────────────────────────────

var _definitions: Array[Dictionary] = [
	{
		"id":             INERTIA_DAMPENER,
		"name":           "Inertia Dampener",
		"description":    "Activate for 3s: ocean and sky become swimmable as if in shallow water,\n 8s recovery.",
		"slot_label":     "Inertia Dampener",
		"needs_input":    true,
		"has_passive_bar": true,
		"color":          Color(0.5, 1.0, 0.5),
	},
	{
		"id":          BRAVADO,
		"name":        "Bravado",
		"description": "Hitting enemies restores stamina.\nFight more, swim more.",
		"slot_label":  "Bravado",
		"needs_input": false,
		"color":       Color(1.0, 0.4, 0.2),
	},
	{
		"id":          LATERAL_THRUST,
		"name":        "Lateral Thrust",
		"description": "Blast left or right, ignoring ocean drag.\nDirection from input or facing. 5s cooldown.",
		"slot_label":  "Lateral Thrust",
		"needs_input": true,
		"color":       Color(0.4, 0.7, 1.0),
	},
	{
		"id":          TRANSPORTER,
		"name":        "Transporter",
		"description": "Teleport in the direction of your momentum. Brief invincibility on landing.",
		"slot_label":  "Transporter",
		"needs_input": true,
		"color":       Color(0.6, 0.3, 1.0),
	},
	{
		"id":          SALIVA_NANOBOTS,
		"name":        "Saliva Nanobots",
		"description": "Bullets home toward nearby enemies\nand deal double damage.",
		"slot_label":  "Saliva Nanobots",
		"needs_input": false,
		"color":       Color(0.3, 1.0, 0.5),
	},
	{
		"id":            BUBBLE_SHIELD,
		"name":          "Bubble Shield",
		"description":   "Absorbs one hit completely. Recharges over 15 seconds.",
		"slot_label":    "Bubble Shield",
		"needs_input":   false,
		"has_passive_bar": true,
		"color":         Color(0.3, 0.9, 1.0),
	},
	{
		"id":              DERMAL_REGEN,
		"name":            "Dermal Regenerator",
		"description":     "Hold slot button to heal. One use per level.\nTaking damage during channeling cancels it.",
		"slot_label":      "Dermal Regenerator",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.2, 1.0, 0.4),
	},
	{
		"id":              BUMPER_MAGNET,
		"name":            "Bumper Magnet",
		"description":     "Hold slot button to magnetically snap to a nearby bumper.\nOrbit with the stick, then release to launch. 10s cooldown.",
		"slot_label":      "Bumper Magnet",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.75, 0.1),
	},
	{
		"id":          PHASE_SHIFTER,
		"name":        "Phase Shifter",
		"description": "Hold your slot button while shooting to fire phase bullets.\n10 shots before a 10s recharge. Phased targets are passthrough and harmless for 5s. Works on invincible enemies.",
		"slot_label":  "Phase Shifter",
		"needs_input": false,
		"color":       Color(0.3, 0.9, 1.0),
	},
	{
		"id":          POWERUP_REPLICATOR,
		"name":        "Powerup Replicator",
		"description": "Automatically copies powerups in 3 save slots. Quick press to cycle slots, long press to activate.",
		"slot_label":  "Powerup Replicator",
		"needs_input": true,
		"color":       Color(1.0, 0.5, 0.9),
	},
	{
		"id":              DEFLECTOR_SHIELD,
		"name":            "Deflector Shield",
		"description":     "Activate to project a repulsion field for 5s.\nEnemies and projectiles are pushed away. 10s cooldown.",
		"slot_label":      "Deflector Shield",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.3, 0.7, 1.0),
	},
	{
		"id":              TIME_FREEZE,
		"name":            "Time Freeze",
		"description":     "Activate to freeze all enemies, projectiles, and hazards for 5s.\n10s cooldown.",
		"slot_label":      "Time Freeze",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.5, 0.85, 1.0),
	},
	{
		"id":          FLIPPER_VELCRO,
		"name":        "Flipper Velcro",
		"description": "Hold slot button while touching a flipper to grip its surface.\nSlide along it with the stick, then release to trigger the flipper and launch. No cooldown.",
		"slot_label":  "Flipper Velcro",
		"needs_input": true,
		"color":       Color(0.2, 1.0, 0.6),
	},
	{
		"id":              SHOCKWAVE,
		"name":            "Shockwave",
		"description":     "Blast 1 hit to all enemies on screen.\nDepletes all energy. 15s cooldown.",
		"slot_label":      "Shockwave",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.55, 0.1),
	},
	{
		"id":          THING_BRINGER,
		"name":        "Thing Bringer",
		"description": "Nearby collectibles are pulled toward you\nand auto-collected.",
		"slot_label":  "Thing Bringer",
		"needs_input": false,
		"color":       Color(1.0, 0.85, 0.2),
	},
]

# ─── API ─────────────────────────────────────────────────────────────────────

func get_tech(id: String) -> Dictionary:
	for tech in _definitions:
		if tech["id"] == id:
			return tech
	push_warning("AlienTechRegistry: Unknown id '%s'" % id)
	return {}

func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	for tech in _definitions:
		ids.append(tech["id"])
	return ids

func get_random_choices(count: int, exclude: Array[String] = []) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for tech in _definitions:
		if tech["id"] not in exclude:
			pool.append(tech)
	pool.shuffle()
	# always return time freeze for now for testing
	# for i in range(pool.size()):
	# 	if pool[i]["id"] == THING_BRINGER:
	# 		var temp = pool[i]
	# 		pool[i] = pool[0]
	# 		pool[0] = temp
	# 		break
	return pool.slice(0, min(count, pool.size()))
