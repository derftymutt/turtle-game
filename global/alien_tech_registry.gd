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
		"hook":           "Swim like you're only ever in the shallows.",
		"slot_label":     "Inertia Dampener",
		"needs_input":    true,
		"has_passive_bar": true,
		"color":          Color(0.5, 1.0, 0.5),
		"hot_description": "Click on, click off — no timer, no cooldown.",
	},
	{
		"id":          BRAVADO,
		"name":        "Bravado",
		"description": "Hitting enemies restores stamina.\nFight more, swim more.",
		"hook":           "Every hit you land fuels the next.",
		"slot_label":  "Bravado",
		"needs_input": false,
		"color":       Color(1.0, 0.4, 0.2),
		"hot_description": "1 second of invincibility every time you hit an enemy.",
	},
	{
		"id":          LATERAL_THRUST,
		"name":        "Lateral Thrust",
		"description": "Blast left or right, ignoring ocean drag.\nDirection from input or facing. 5s cooldown.",
		"hook":           "Punch sideways through the water, drag be damned.",
		"slot_label":  "Lateral Thrust",
		"needs_input": true,
		"color":       Color(0.4, 0.7, 1.0),
		"hot_description": "No cooldown.",
	},
	{
		"id":          TRANSPORTER,
		"name":        "Transporter",
		"description": "Teleport in the direction of your momentum. Brief invincibility on landing. 8s cooldown.",
		"hook":           "Blink past danger in the direction you're already moving.",
		"slot_label":  "Transporter",
		"needs_input": true,
		"color":       Color(0.6, 0.3, 1.0),
		"hot_description": "No cooldown.",
	},
	{
		"id":          SALIVA_NANOBOTS,
		"name":        "Saliva Nanobots",
		"description": "Bullets home toward nearby enemies\nand deal double damage.",
		"hook":           "Your shots hunt enemies down and hit twice as hard.",
		"slot_label":  "Saliva Nanobots",
		"needs_input": false,
		"color":       Color(0.3, 1.0, 0.5),
		"hot_description": "Homing and damage doubled again.",
	},
	{
		"id":            BUBBLE_SHIELD,
		"name":          "Bubble Shield",
		"description":   "Absorbs one hit completely. Recharges over 15 seconds.",
		"hook":           "A shield that shrugs off the next hit for you.",
		"slot_label":    "Bubble Shield",
		"needs_input":   false,
		"has_passive_bar": true,
		"color":         Color(0.3, 0.9, 1.0),
		"hot_description": "Half the recharge time. Nearby enemies take damage when it triggers.",
	},
	{
		"id":              DERMAL_REGEN,
		"name":            "Dermal Regenerator",
		"description":     "Hold slot button to heal. One use per level.\nTaking damage during channeling cancels it.",
		"hook":           "Turn your own spit into a self-heal.",
		"slot_label":      "Dermal Regenerator",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.2, 1.0, 0.4),
		"hot_description": "Instant, full heal — no channel needed.",
	},
	{
		"id":              BUMPER_MAGNET,
		"name":            "Bumper Magnet",
		"description":     "Hold slot button to magnetically snap to a nearby bumper. Orbit with the stick, then release to launch. 5s cooldown.",
		"hook":           "Grab a bumper, spin it up, launch yourself like a pinball.",
		"slot_label":      "Bumper Magnet",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.75, 0.1),
		"hot_description": "Attracts from much farther away, at super speed — damages enemies in its path. No cooldown.",
	},
	{
		"id":          PHASE_SHIFTER,
		"name":        "Phase Shifter",
		"description": "Hold your slot button while shooting to fire phase bullets.\n10 shots before a 10s recharge. Phased targets are passthrough and harmless for 5s. Works on invincible enemies.",
		"hook":           "Fire bullets that pass clean through anything, even the invincible.",
		"slot_label":  "Phase Shifter",
		"needs_input": false,
		"color":       Color(0.3, 0.9, 1.0),
		"hot_description": "Unlimited phase bullets — no recharge.",
	},
	{
		"id":          POWERUP_REPLICATOR,
		"name":        "Powerup Replicator",
		"description": "Automatically copies powerups in 3 save slots. Quick press to cycle slots, long press to activate.",
		"hook":           "Bank your powerups now, cash them in later.",
		"slot_label":  "Powerup Replicator",
		"needs_input": true,
		"color":       Color(1.0, 0.5, 0.9),
		"hot_description": "Each pickup fills the carousel with all 4 powerups, wild — pick any 2.",
	},
	{
		"id":              DEFLECTOR_SHIELD,
		"name":            "Deflector Shield",
		"description":     "Project a repulsion field. Enemies and projectiles are pushed away. 5s active, 10s cooldown.",
		"hook":           "Push everything hostile away from you at once.",
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
		"hook":           "Stop the whole ocean cold while you make your move.",
		"slot_label":      "Time Freeze",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.5, 0.85, 1.0),
		"hot_description": "Twice as long, half the cooldown.",
	},
	{
		"id":          FLIPPER_VELCRO,
		"name":        "Flipper Velcro",
		"description": "Hold slot button while touching a flipper to grip its surface.\nSlide along it with the stick, then release to trigger the flipper and launch. No cooldown.",
		"hook":           "Stick to flippers and sling yourself off them.",
		"slot_label":  "Flipper Velcro",
		"needs_input": true,
		"color":       Color(0.2, 1.0, 0.6),
		"hot_description": "Can shoot while gripping. Releases at much higher speed.",
	},
	{
		"id":              SHOCKWAVE,
		"name":            "Shockwave",
		"description":     "Blast 1 hit to all enemies on screen. Depletes all energy. 30s cooldown.",
		"hook":           "One shockwave, every enemy on screen feels it.",
		"slot_label":      "Shockwave",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(1.0, 0.55, 0.1),
		"hot_description": "No cooldown, no self-stun — but costs a heart each use.",
	},
	{
		"id":          THING_BRINGER,
		"name":        "Thing Bringer",
		"description": "Nearby collectibles are pulled toward you\nand auto-collected.",
		"hook":           "Loot comes to you instead of the other way around.",
		"slot_label":  "Thing Bringer",
		"needs_input": false,
		"color":       Color(1.0, 0.85, 0.2),
		"hot_description": "Twice the range and pull speed.",
	},
	{
		"id":              GRAVITON_HARNESS,
		"name":            "Graviton Harness",
		"description":     "Nullify the weight of a carried UFO part. 5s active, 5s cooldown.",
		"hook":           "Makes a UFO part weigh nothing in your hands.",
		"slot_label":      "Graviton Harness",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.7, 0.8, 1.0),
		"hot_description": "Always active — no cooldown. Carry 2 UFO parts at once.",
	},
	{
		"id":          PLASMA_SPIT,
		"name":        "Plasma Spit",
		"description": "Bullets become thin plasma beams that pierce enemies and pass\nthrough all barriers. Slightly shorter range than a regular shot.\nSame damage per hit.",
		"hook":           "Shots turn into beams that punch through everything.",
		"slot_label":  "Plasma Spit",
		"needs_input": false,
		"color":       Color(1.0, 0.2, 0.6),
		"hot_description": "Longer beam, double damage.",
	},
	{
		"id":              MAGNETIC_REPULSION,
		"name":            "Magnetic Repulsion",
		"description":     "Powerups, UFO parts, trash pieces, and tech pieces hover just off the ocean floor and walls instead of sinking flush against them. 8s active, 5s cooldown.",
		"hook":           "Keeps loot floating just out of the muck.",
		"slot_label":      "Magnetic Repulsion",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.85, 0.4, 1.0),
		"hot_description": "Always active — no cooldown. Much stronger repulsion — everything floats farther out.",
	},
	{
		"id":              HYDRO_FUNNEL,
		"name":            "Hydro Funnel",
		"description":     "Opens hidden ocean currents around the level to ride. 10s active, 6s cooldown.",
		"hook":           "Unlocks hidden currents that carry you through the level.",
		"slot_label":      "Hydro Funnel",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.3, 0.75, 1.0),
		"hot_description": "Click on, click off — no timer, no cooldown. Any hot-only currents in the level open too.",
	},
	{
		"id":              QUANTUM_MIRROR,
		"name":            "Quantum Mirror",
		"description":     "Instantly swap with your mirror position — invincible the whole time. Returns automatically when it ends. 5s active, 5s cooldown.",
		"hook":           "Swap places with your own reflection, safe the whole time.",
		"slot_label":      "Quantum Mirror",
		"needs_input":     true,
		"has_passive_bar": true,
		"color":           Color(0.85, 0.3, 0.95),
		"hot_description": "Mirrors both axes — leap into the ocean depths (or back) instead of just side to side.",
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
