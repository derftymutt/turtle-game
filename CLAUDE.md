# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

This is a **Godot 4.6** project. Open the project in the Godot editor and press **F5** to run. There is no build step or CLI runner — all development happens via the Godot editor.

- Main scene: `scenes/main.tscn`
- Viewport: 640×360 (displayed at 1920×1080 with integer scaling)

## Architecture Overview

### Autoloads (Globals)

Five singletons are registered in `project.godot` and available everywhere:

| Singleton | File | Purpose |
|---|---|---|
| `GameManager` | `global/game_manager.gd` | Transient run state: score, UFO piece carrying |
| `GameSettings` | `global/game_settings.gd` | Player preferences (e.g. `thrust_inverted`) |
| `LevelManager` | `global/level_manager.gd` | Level progression, piece counting, scene transitions |
| `AlienTechRegistry` | `global/alien_tech_registry.gd` | **Pure data** — all 13 tech definitions. Never holds run state. |
| `AlienTechManager` | `global/alien_tech_manager.gd` | **Run state** — which techs are in slots, cooldowns, signals |

`AlienTechRegistry` must load **before** `AlienTechManager` in the autoload order.

### Level Structure

All levels (`levels/level_N.tscn`) inherit from `LevelBase` (`levels/shared/level_base.gd`). `LevelBase` handles HUD, GameOver screen, and PauseMenu as `@onready` children. Each level sets its `level_number` export in the Inspector. `LevelManager.start_level()` is called in `LevelBase._ready()`.

### Player (`entities/player/turtle_player.gd`)

`TurtlePlayer` extends `RigidBody2D`. Key design decisions:
- **Ocean physics**: buoyancy/drag applied every `_physics_process` via an `Ocean` node found by group. If no ocean exists, falls back to simple damping.
- **8-directional sprite**: The body can spin freely (correct flipper/bumper physics), but the `AnimatedSprite2D` counter-rotates every frame to stay axis-aligned. Animation names follow the pattern `idle_e`, `kick_sw`, `shoot_n`, etc.
- **Sprite modulate**: `_process` is the single source of truth for all sprite color states (super speed, powerups, alien techs, iframes). All visual states are prioritized in `_update_sprite_modulate()`.
- **Alien tech effects** are all implemented in `_on_alien_tech_activated()`, which receives signals from `AlienTechManager`.
- Collision layers **must be set in the Inspector**, not programmatically, except for runtime-created nodes (`SuperSpeedArea`, `DeflectorArea`).

### Alien Tech System

1. **Definitions** live in `AlienTechRegistry._definitions` (array of Dictionaries). Each tech has `id`, `name`, `description`, `slot_label`, `needs_input`, optional `has_passive_bar`, and `color`.
2. **Run state** lives in `AlienTechManager`: two slots (`slots[0]`, `slots[1]`), cooldown timers, and per-tech state (phase shifter ammo, powerup replicator storage, time freeze active flag).
3. **Signal flow**: `AlienTechManager.tech_activated` → `TurtlePlayer._on_alien_tech_activated()` → effect runs. HUD subscribes to `tech_slots_changed`, `piece_collected`, and per-tech signals.
4. **Adding a new tech**: add a definition to `AlienTechRegistry._definitions`, add a constant ID, add a `_COOLDOWN_DURATIONS` entry if it needs cooldown, then handle it in `TurtlePlayer._on_alien_tech_activated()`. Update `AlienTechManager.try_activate_slot()` only if the tech needs special activation logic.

### Enemies (`entities/enemies/base_enemy.gd`)

All enemies extend `BaseEnemy` (which extends `RigidBody2D`). Override `_enemy_ready()` for per-enemy setup. Key behaviors inherited: `take_damage()`, `die()` (with 2% chance to drop an alien tech piece), `phase_shift()` (used by Phase Shifter tech), contact-damage area via a child `DamageArea` node.

### Physics Collision Layers

| Layer | Name | Used by |
|---|---|---|
| 1 | World_Player | Walls, world geometry, player body |
| 2 | Collectibles | Powerups, UFO pieces |
| 3 | Enemies | Enemy bodies |
| 4 | PlayerBullets | Bullets from turtle |
| 5 | CloudFlippers | Flipper objects |
| 6 | Player | Player's own collision |
| 7 | EnemyBullets | Projectiles from enemies |
| 8 | Trash | Trash items |

### HUD (`ui/hud/hud.gd`)

HUD is instantiated as a child of each level scene (via `LevelBase`). It manages:
- **Air system** (toggleable via `air_enabled` export): drains underwater, refills at surface. Damage dealt by `TurtlePlayer` when `drain_air()` returns true.
- **Energy system** (toggleable via `energy_enabled` export): consumed per-thrust via `try_thrust()`, recovered over time and faster when touching walls.
- **Alien tech slots**: subscribes to `AlienTechManager` signals; cooldown bars use `AlienTechManager.get_cooldown_ratio()`.
- **Trash clusters**: every 200 score points, HUD spawns a `TrashCluster` that drifts across the screen.

### Trash Cleanup System

`TrashSequenceSpawner` (in `systems/trash_cleanup/`) periodically spawns `TrashSequence` nodes. Each sequence contains multiple `TrashItem` collectibles in patterns (STRAIGHT, WAVE, DIAGONAL). Completing a sequence awards a powerup.

### Score → Alien Tech Pipeline

Defeating enemies has a 2% chance to drop an `AlienTechPiece`. Collecting one calls `AlienTechManager.collect_piece()`. When `pieces_this_threshold >= PIECES_PER_TECH` (currently 1), `AlienTechManager` emits `selection_ready` and shows the tech selection screen. Tech selection assigns a tech to an empty slot.

## Input Actions (Keyboard Defaults)

| Action | Key |
|---|---|
| Move | WASD |
| Shoot | IJKL |
| Tech slot left | Q |
| Tech slot right | E |
| Drop UFO piece | Space |
| Pause | Escape |
| UFO windup | Z |

All actions also support gamepad.

## Groups Convention

Nodes register themselves in `_ready()` via `add_to_group()`. Key groups:
- `"player"` — TurtlePlayer
- `"enemies"` — all enemies
- `"hud"` — HUD node
- `"ocean"` — Ocean node (looked up by TurtlePlayer and LevelBase)
- `"level"` — the active level root
- `"bumpers"` — CircularBumper nodes (used by Bumper Magnet tech)
- `"spawners"`, `"trash_spawners"` — paused during Time Freeze
- `"bullets"`, `"enemy_projectiles"`, `"trash_items"`, `"powerups"` — frozen during Time Freeze
