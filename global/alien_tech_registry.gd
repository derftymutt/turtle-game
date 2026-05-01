extends Node

## Autoload: AlienTechRegistry
## Pure data — all tech definitions. Never holds run state.
## Add to Project Settings > Autoload as "AlienTechRegistry" (BEFORE AlienTechManager)

# ─── Tech ID constants ───────────────────────────────────────────────────────

const INERTIA_DAMPENER := "inertia_dampener"
const BRAVADO          := "bravado"
const JETPACK          := "jetpack"

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
		"id":          JETPACK,
		"name":        "Jetpack",
		"description": "Dash in your facing direction, ignoring ocean physics.\n5 second cooldown.",
		"slot_label":  "JETPACK",
		"needs_input": true,
		"color":       Color(0.4, 0.7, 1.0),
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
