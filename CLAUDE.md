# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

This is a **Godot 4.6** project. Open the project in the Godot editor and press **F5** to run. There is no build step or CLI runner — all development happens via the Godot editor.

- Main scene: `ui/menus/main_menu.tscn`
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
- **Alien tech effects** are extracted into one class per tech under `entities/player/alien_tech_effects/` (see Alien Tech System below) — `_on_alien_tech_activated()` is now pure dispatch, not implementation.
- Collision layers **must be set in the Inspector**, not programmatically, except for runtime-created nodes (`SuperSpeedArea`, `DeflectorArea`).

### Alien Tech System

1. **Definitions** live in `AlienTechRegistry._definitions` (array of Dictionaries). Each tech has `id`, `name`, `description`, `slot_label`, `needs_input`, optional `has_passive_bar`, and `color`.
2. **Run state** lives in `AlienTechManager`: two slots (`slots[0]`, `slots[1]`), cooldown timers, and per-tech state (phase shifter ammo, powerup replicator storage, time freeze active flag).
3. **Signal flow**: `AlienTechManager.tech_activated` → `TurtlePlayer._on_alien_tech_activated()` → `_tech_effects[tech_id].activate(self, slot_index)`. HUD subscribes to `tech_slots_changed`, `piece_collected`, and per-tech signals.
4. **Effect classes** (`entities/player/alien_tech_effects/`): every tech reachable through the normal press-to-activate dispatch (16 of the 23 tech IDs — see the exception list below) has its own `AlienTechEffect` subclass, e.g. `GravitonHarnessEffect`, `BumperMagnetEffect`, `TimeFreezeEffect`. `TurtlePlayer._ready()` creates one instance per tech into `_tech_effects: Dictionary` (keyed by `AlienTechRegistry` id) and keeps it for the node's lifetime — `activate()`/`physics_process()` toggle it on and off rather than the object itself being created/destroyed. `_on_alien_tech_activated()` is now a one-line dispatcher: `if _tech_effects.has(tech_id): _tech_effects[tech_id].activate(self, slot_index)`.
   - **Base class hooks** (`alien_tech_effect.gd`), all optional and no-op by default: `setup(player)` (called once from `TurtlePlayer._ready()`, for effects that create runtime child nodes — e.g. Deflector Shield's `Area2D`/`Line2D`), `activate(player, slot_index)` (on press), `physics_process(player, delta)` (called **every** physics frame regardless of active state — effects check their own flag internally, mirroring the timer blocks they replaced), `on_slots_changed(player)` (tech swapped out mid-effect — called generically over every effect from `_on_alien_tech_slots_changed_player()`), `cancel_on_damage(player)` (real damage about to land — called explicitly per-effect from `take_damage()`, not generically, since only a few techs need it).
   - **Effects are stateless w.r.t. player identity**: `player` is always passed as a parameter, never stored as a member, so one effect instance never gets attached to the wrong node. Effects call back into `TurtlePlayer` for shared utilities that don't belong on a single tech (`_flash()`, `_direction_suffix_to_vector()`, `_get_boundary_limits()` / `_clamp_to_boundaries()` / `_mirrored_position()`, `restore_hearts()`, `suspend_control()`, `apply_powerup()`) and for public state (`hud`, `ocean`, `linear_velocity`, `global_position`).
   - **Public fields, not getters**: several effects expose plain public vars (`active`, `attached`, `windup`, `invincible`, `ghost`) that `TurtlePlayer` reads directly in its own core methods — the sprite-modulate priority chain in `_update_sprite_modulate()`, the damage-blocking OR-chain in `take_damage()`, the ocean-physics-suppression checks in `_physics_process()`. This keeps those call sites a one-line swap (`_tech_effects[ID].active` instead of a local bool) rather than needing a redesign.
   - **GDScript gotcha**: `player` is intentionally untyped (avoids a circular class dependency with `TurtlePlayer`), so a duck-typed call chained through it — e.g. `player.global_position.distance_to(...)` or `player.create_tween()` — can't have its result type inferred by `:=`. This has caused several real parse errors during extraction; give the local var an explicit type (`var dist: float = ...`) instead of `:=` whenever the right-hand side touches `player`.
   - **Not every tech ID has an effect class.** `BRAVADO`, `PLASMA_SPIT`, `SALIVA_NANOBOTS`, `PHASE_SHIFTER`, `BUBBLE_SHIELD`, and `FLIPPER_VELCRO` never go through `_on_alien_tech_activated()` — they're passive checks inline in `shoot()` / `take_damage()` / `apply_ocean_effects()`, or (Flipper Velcro) their own hold-input state machine polled directly from `_physics_process()`. Adding one of these does **not** mean creating an effect class.
   - **Deferred cooldown**: a tech whose cooldown should run from the *end* of its action (Multi Lance) is listed in `AlienTechManager._HOLD_COOLDOWN_TECHS`. `try_activate_slot()` still seeds the cooldown on press (bar reads full, re-presses refused) but `_process()` doesn't drain it until the effect calls `AlienTechManager.release_cooldown_hold(id)` (optionally with a `max_remaining` cap, which Multi Lance uses to shorten the cooldown after a miss). Every exit path of the effect — including `cancel_on_damage()` — must reach that call, or the slot stays locked; a fresh `TurtlePlayer` clears any leftover holds in `_ready()`.
5. **Adding a new activate-on-press tech**: add a definition to `AlienTechRegistry._definitions`, add a constant ID, add a `_COOLDOWN_DURATIONS` entry if it needs cooldown, create `entities/player/alien_tech_effects/<name>_effect.gd` extending `AlienTechEffect`, register it in `TurtlePlayer._ready()` (`_tech_effects[AlienTechRegistry.YOUR_ID] = YourEffect.new()`) — no dispatch code needed beyond that. Update `AlienTechManager.try_activate_slot()` only if the tech needs special activation logic (see Powerup Replicator's tap-vs-hold handling for an example of a tech that bypasses `try_activate_slot()` entirely via its own `handle_input()` called from `TurtlePlayer`'s input loop).

### Enemies (`entities/enemies/base_enemy.gd`)

All enemies extend `BaseEnemy` (which extends `RigidBody2D`). Override `_enemy_ready()` for per-enemy setup. Key behaviors inherited: `take_damage()`, `die()` (with 2% chance to drop an alien tech piece), `phase_shift()` (used by Phase Shifter tech), contact-damage area via a child `DamageArea` node.

`BaseEnemyStatic` (`AnimatableBody2D`, e.g. Crocodile) is a parallel base class with the same health/damage API. Invincible enemies (crocodile, sea urchin) can be frozen and disarmed for a time via `shock(duration)` on either base class, which delegates to `EnemyShock` (`entities/enemies/enemy_shock.gd`); the boss submarine opts out through `can_be_shocked()`.

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

Mouse mode (`GameSettings.mouse_mode`) is the **default** keyboard layout; "Keyboard Only" in Options switches to the IJKL layout defined in `project.godot`.

| Action | Mouse mode (default) | Keyboard only |
|---|---|---|
| Move | WASD | WASD |
| Shoot | Mouse aim, auto-fire | IJKL |
| Toggle auto-fire | Tab / middle click | — |
| Flipper left / right | LMB / RMB | L Shift / R Shift |
| Tech slot left | L Shift | Q |
| Tech slot right | Space | E |
| Drop UFO piece | F | Space |
| Pause | Escape | Escape |
| UFO windup | Z | Z |

All actions also support gamepad.

**Mouse mode internals**: `project.godot` holds the keyboard-only bindings; `GameSettings._apply_mouse_mode_bindings()` rewires the InputMap at runtime (and fully undoes it when switched off). `toggle_fire` is a runtime-only action. `GameSettings` tracks the last-used device (`using_gamepad`, `input_device_changed`); `mouse_aim_active()` = mouse mode **and** keyboard/mouse in use — auto-fire and the `MouseCrosshair` (runtime child of the player, hides the OS cursor during live play) only run when it's true. All shooting input goes through `TurtlePlayer.get_shoot_input()` — don't read the `shoot_*` axes directly. UI key hints come from `GameSettings.tech_slot_key_label()` / `drop_key_label()`. Popups that can appear mid-play (tech selection, game over, level complete) ignore mouse clicks for 500 ms, since LMB/RMB are the flippers. Every `BaseButton` gets the pointing-hand cursor automatically via `GameSettings._on_node_added()` — no need to set it per scene; non-button clickables must set `mouse_default_cursor_shape` themselves.

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
