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
const GRAVITON_HARNESS    := "graviton_harness"
const PLASMA_SPIT         := "plasma_spit"
const MAGNETIC_REPULSION  := "magnetic_repulsion"
const HYDRO_FUNNEL        := "hydro_funnel"
const QUANTUM_MIRROR      := "quantum_mirror"

# ─── Tech definitions ────────────────────────────────────────────────────────

var _definitions: Array[Dictionary] = [
	{
		"id":             INERTIA_DAMPENER,
		"name":           "Inertia Dampener",
		"description":    "Ocean and sky become swimmable as if in shallow water. 3s active, 8s cooldown.",
		"hook":           "No Gravity!",
		"slot_label":     "Inertia Dampener",
		"needs_input":    true,
		"has_passive_bar": true,
		"color":          Color(0.5, 1.0, 0.5),
		"hot_description": "Click on, click off — no timer, no cooldown.",
	},
	{
		"id":          BRAVADO,
		"name":        "Bravado",
		"description": "Hitting enemies restores energy.\nFight more, swim more.",
		"hook":        "Fighting revs you up!",
		"slot_label":  "Bravado",
		"needs_input": false,
		"color":       Color(1.0, 0.4, 0.2),
		"hot_description": "1 second of invincibility every time you hit an enemy.",
	},
	{
		"id":          LATERAL_THRUST,
		"name":        "Lateral Thrust",
		"description": "Blast left or right, ignoring ocean drag. 5s cooldown.",
		"hook":        "Zip sideways!",
		"slot_label":  "Lateral Thrust",
		"needs_input": true,
		"color":       Color(0.4, 0.7, 1.0),
		"hot_description": "No cooldown.",
	},
	{
		"id":          TRANSPORTER,
		"name":        "Transporter",
		"description": "Teleport in the direction of your momentum. Brief invincibility on landing. 8s cooldown.",
		"hook":        "Where'd they go?!",
		"slot_label":  "Transporter",
		"needs_input": true,
		"color":       Color(0.6, 0.3, 1.0),
		"hot_description": "No cooldown.",
	},
	{
		"id":          SALIVA_NANOBOTS,
		"name":        "Saliva Nanobots",
		"description": "Bullets home toward nearby enemies\nand deal double damage.",
		"hook":        "Extra vicious homing spit!",
		"slot_label":  "Saliva Nanobots",
		"needs_input": false,
		"color":       Color(0.3, 1.0, 0.5),
		"hot_description": "Homing and damage doubled again.",
	},
	{
		"id":            BUBBLE_SHIELD,
		"name":          "Bubble Shield",
		"description":   "Absorbs one hit completely. Recharges over 15 seconds.",
		"hook":          "Safety bubble!",
		"slot_label":    "Bubble Shield",
		"needs_input":   false,
		"has_passive_bar": true,
		"color":         Color(0.3, 0.9, 1.0),
		"hot_description": "Half the recharge time. Nearby enemies take damage when it triggers.",
	},
	{
		"id":              DERMAL_REGEN,
		"name":            "Dermal Regenerator",
		"description":     "Hold tech button to heal. One use per level.\nTaking damage during activation time cancels it.",
		"hook":            "Lacerations be gone!",
		"slot_label":      "Dermal Regenerator",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.2, 1.0, 0.4),
		"hot_description": "Instant, full heal — no activation time needed.",
	},
	{
		"id":              BUMPER_MAGNET,
		"name":            "Bumper Magnet",
		"description":     "Hold tech button to grab onto a nearby bumper. Orbit with the stick, then release to launch. 5s cooldown.",
		"hook":            "Latch onto bumpers and do a twirl!",
		"slot_label":      "Bumper Magnet",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.75, 0.1),
		"hot_description": "Attracts from farther away at super speed, damaging enemies in your path. No cooldown.",
	},
	{
		"id":          PHASE_SHIFTER,
		"name":        "Phase Shifter",
		"description": "Hold tech button while shooting to fire phase bullets.\nPhased targets are passthrough and harmless for 5s. 10 shots before a 10s recharge. ",
		"hook":        "Send things to another dimension!",
		"slot_label":  "Phase Shifter",
		"needs_input": true,
		"color":       Color(0.3, 0.9, 1.0),
		"hot_description": "Unlimited phase bullets — no recharge.",
	},
	{
		"id":          POWERUP_REPLICATOR,
		"name":        "Powerup Replicator",
		"description": "Automatically copies powerups into 3 save slots. Quick press to cycle slots, long press to activate.",
		"hook":        "Stash copies of powerups!",
		"slot_label":  "Powerup Replicator",
		"needs_input": true,
		"color":       Color(1.0, 0.5, 0.9),
		"hot_description": "Each pickup fills the carousel with all 4 powerups, wild — pick any 2.",
	},
	{
		"id":              DEFLECTOR_SHIELD,
		"name":            "Deflector Shield",
		"description":     "Project a repulsion field. Enemies and projectiles are pushed away. 5s active, 10s cooldown.",
		"hook":            "Get some space!",
		"slot_label":      "Deflector Shield",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.3, 0.7, 1.0),
		"hot_description": "Twice the radius, half the cooldown.",
	},
	{
		"id":              TIME_FREEZE,
		"name":            "Time Freeze",
		"description":     "Freeze all enemies, projectiles, and hazards. 5s active, 10s cooldown.",
		"hook":            "Time stands still!",
		"slot_label":      "Time Freeze",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.5, 0.85, 1.0),
		"hot_description": "Twice as long, half the cooldown.",
	},
	{
		"id":          FLIPPER_VELCRO,
		"name":        "Flipper Velcro",
		"description": "Hold tech button while touching a flipper to grip to it.\nSlide position with the stick, then release to launch. No cooldown.",
		"hook":        "Get the perfect angle!",
		"slot_label":  "Flipper Velcro",
		"needs_input": true,
		"color":       Color(0.2, 1.0, 0.6),
		"hot_description": "Can shoot while gripping. Releases at much higher speed.",
	},
	{
		"id":              SHOCKWAVE,
		"name":            "Shockwave",
		"description":     "Blast a hit to all enemies on screen. Depletes all energy and shakes you up. 30s cooldown.",
		"hook":            "Zap them all!",
		"slot_label":      "Shockwave",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.55, 0.1),
		"hot_description": "No cooldown, no shake up — but costs a heart each use.",
	},
	{
		"id":          THING_BRINGER,
		"name":        "Thing Bringer",
		"description": "Nearby collectibles are pulled toward you\nand auto-collected.",
		"hook":        "Here kitty kitty!",
		"slot_label":  "Thing Bringer",
		"needs_input": false,
		"color":       Color(1.0, 0.85, 0.2),
		"hot_description": "Twice the range and pull speed.",
	},
	{
		"id":              GRAVITON_HARNESS,
		"name":            "Graviton Harness",
		"description":     "Nullify the weight of a carried UFO part. 5s active, 5s cooldown.",
		"hook":            "UFO part, I got this!",
		"slot_label":      "Graviton Harness",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.7, 0.8, 1.0),
		"hot_description": "Always active — no cooldown. Carry 2 UFO parts at once.",
	},
	{
		"id":          PLASMA_SPIT,
		"name":        "Plasma Spit",
		"description": "Bullets become plasma beams that passthrough all barriers.",
		"hook":        "Walls be damned!",
		"slot_label":  "Plasma Spit",
		"needs_input": false,
		"color":       Color(1.0, 0.2, 0.6),
		"hot_description": "Longer beam, double damage.",
	},
	{
		"id":              MAGNETIC_REPULSION,
		"name":            "Magnetic Repulsion",
		"description":     "Goodies hover above the ocean floor and side walls. 8s active, 5s cooldown.",
		"hook":            "Ahh.. much closer!",
		"slot_label":      "Magnetic Repulsion",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.85, 0.4, 1.0),
		"hot_description": "Always active — no cooldown. Stronger repulsion — everything hovers higher.",
	},
	{
		"id":              HYDRO_FUNNEL,
		"name":            "Hydro Funnel",
		"description":     "Creates special ocean currents around the level to ride. 10s active, 6s cooldown.",
		"hook":            "Weeeee!!!!",
		"slot_label":      "Hydro Funnel",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.3, 0.75, 1.0),
		"hot_description": "Click on, click off — no timer, no cooldown. Plus more currents!",
	},
	{
		"id":              QUANTUM_MIRROR,
		"name":            "Quantum Mirror",
		"description":     "An invincible copy of yourself briefly appears in your horizontally mirrored position. 5s active, 5s cooldown.",
		"hook":            "High tech reflection!",
		"slot_label":      "Quantum Mirror",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.85, 0.3, 0.95),
		"hot_description": "Mirrors both axes — reflect into the ocean depths (or back) instead of just side to side.",
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
