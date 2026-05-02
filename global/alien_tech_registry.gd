extends Node

## Autoload: AlienTechRegistry
## Pure data — all tech definitions. Never holds run state.
## Add to Project Settings > Autoload as "AlienTechRegistry" (BEFORE AlienTechManager)

# ─── Tech ID constants ───────────────────────────────────────────────────────

const INERTIA_DAMPENER := "inertia_dampener"
const BRAVADO          := "bravado"
const LATERAL_THRUST   := "lateral_thrust"
const TRANSPORTER      := "transporter"
const SALIVA_NANOBOTS  := "saliva_nanobots"
const BUBBLE_SHIELD    := "bubble_shield"
const BUMPER_MAGNET    := "bumper_magnet"
const DERMAL_REGEN     := "dermal_regen"

# ─── Tech definitions ────────────────────────────────────────────────────────

var _definitions: Array[Dictionary] = [
	{
		"id":          INERTIA_DAMPENER,
		"name":        "Inertia Dampener",
		"description": "Deep water feels like shallow water everywhere.\nEasier movement at depth.",
		"slot_label":  "DAMPENER",
		"needs_input": false,
		"color":       Color(0.5, 1.0, 0.5),
	},
	{
		"id":          BRAVADO,
		"name":        "Bravado",
		"description": "Hitting enemies restores stamina.\nFight more, swim more.",
		"slot_label":  "BRAVADO",
		"needs_input": false,
		"color":       Color(1.0, 0.4, 0.2),
	},
	{
		"id":          LATERAL_THRUST,
		"name":        "Lateral Thrust",
		"description": "Blast left or right, ignoring ocean drag.\nDirection from input or facing. 5s cooldown.",
		"slot_label":  "L-THRUST",
		"needs_input": true,
		"color":       Color(0.4, 0.7, 1.0),
	},
	{
		"id":          TRANSPORTER,
		"name":        "Transporter",
		"description": "Teleport ~200px in your momentum direction. Ignores walls. Brief invincibility on landing.",
		"slot_label":  "TPORT",
		"needs_input": true,
		"color":       Color(0.6, 0.3, 1.0),
	},
	{
		"id":          SALIVA_NANOBOTS,
		"name":        "Saliva Nanobots",
		"description": "Bullets gently home toward nearby enemies.",
		"slot_label":  "NANOBOTS",
		"needs_input": false,
		"color":       Color(0.3, 1.0, 0.5),
	},
	{
		"id":            BUBBLE_SHIELD,
		"name":          "Bubble Shield",
		"description":   "Absorbs one hit completely. Recharges over 15 seconds.",
		"slot_label":    "SHIELD",
		"needs_input":   false,
		"has_passive_bar": true,
		"color":         Color(0.3, 0.9, 1.0),
	},
	{
		"id":              DERMAL_REGEN,
		"name":            "Dermal Regenerator",
		"description":     "Hold to channel a 60 HP heal. One use per level.\nTaking damage during channeling cancels it.",
		"slot_label":      "REGEN",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.2, 1.0, 0.4),
	},
	{
		"id":              BUMPER_MAGNET,
		"name":            "Bumper Magnet",
		"description":     "Hold to magnetically snap to a nearby bumper.\nOrbit with the stick, then release to launch. 10s cooldown.",
		"slot_label":      "MAGNET",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.75, 0.1),
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
	return pool.slice(0, min(count, pool.size()))
