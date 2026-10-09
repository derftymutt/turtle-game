# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

This is a **Godot 4.6** project. Open the project in the Godot editor and press **F5** to run. There is no build step or CLI runner — all development happens via the Godot editor.

- Main scene: `ui/menus/main_menu.tscn`
- Viewport: 640×360 (displayed at 1920×1080 with integer scaling)
- Game speed: the whole game runs at `GameSettings.GAME_SPEED` (1.1×) via `Engine.time_scale`, with `Engine.physics_ticks_per_second` scaled to match (66) so each physics step stays 1/60 s of game time. All tuning values are in game time — never compensate for the speed by hand. `Time.get_ticks_msec()` and audio stay real-time.
- Bullet time (Acceleration Focus) multiplies that speed via `GameSettings.set_time_dilation()` without reducing the tick rate, so ticks get shorter in game time. Any per-tick velocity multiply (drag, damping) must go through `GameSettings.drag_step(factor, delta)` — identical to `factor` at normal speed, correct when dilated.

## Architecture Overview

### Autoloads (Globals)

These singletons are registered in `project.godot` and available everywhere:

| Singleton | File | Purpose |
|---|---|---|
| `GameManager` | `global/game_manager.gd` | Transient run state: score, UFO piece carrying |
| `GameSettings` | `global/game_settings.gd` | Player preferences (e.g. `thrust_inverted`) |
| `LevelManager` | `global/level_manager.gd` | Level progression, piece counting, scene transitions |
| `AlienTechRegistry` | `global/alien_tech_registry.gd` | **Pure data** — all 13 tech definitions. Never holds run state. |
| `AlienTechManager` | `global/alien_tech_manager.gd` | **Run state** — which techs are in slots, cooldowns, signals |
| `RainbowBonusManager` | `global/rainbow_bonus_manager.gd` | Swaps the bonus rainbow level in and the original level back out |

`AlienTechRegistry` must load **before** `AlienTechManager` in the autoload order.

### Level Structure

All levels (`levels/level_N.tscn`) inherit from `LevelBase` (`levels/shared/level_base.gd`). `LevelBase` handles HUD, GameOver screen, and PauseMenu as `@onready` children. Each level sets its `level_number` export in the Inspector. `LevelManager.start_level()` is called in `LevelBase._ready()`.

**Start prompt**: every level opens frozen behind a 3-second countdown that any button press skips (`LevelStartPrompt`, `ui/menus/level_start_prompt.gd`, built in code) so the player can plan first. `LevelBase.show_start_prompt()` pauses the tree straight from `_ready()`, before the level runs a frame; the level song keeps playing through the wait (its `process_mode` is `ALWAYS` until the level starts). Anything that should be visible for planning must therefore appear without the tree running (SceneTreeTimers and `TWEEN_PAUSE_PROCESS` tweens do run — the squid/puffer spawn fade-ins use that). The tutorial and the Academy opt out by overriding `_wants_start_prompt()`. A popup that is up at level load (`BossIntroPopup`) calls `hold_start_prompt()` and then `show_start_prompt()` when dismissed.

**Plunge start (Puffer Bird)**: a level that instances `entities/npcs/puffer_bird/puffer_bird_launcher.tscn` (`PufferBirdLauncher`, opt-in — Level 2 has one) opens with a plunge instead of the start prompt. Place the node where the bird should hold the turtle (top middle of the opening screen, just above the water). `LevelBase` finds it through the `"plunge_launchers"` group, calls `grab_turtle()` at load and `begin()` from `show_start_prompt()`. The tree stays paused throughout, like behind the prompt: the launcher runs `PROCESS_MODE_ALWAYS` and moves the paused turtle by hand, which is what makes the plunge pass through everything (it bounces off the edges of the opening screen and the world boundaries instead). The bird sprite is moved at runtime onto its own viewport-following `CanvasLayer` above the HUD. A countdown (`countdown_seconds`) runs while left/right pivots the angle (the bird stays put — same inputs as the community UFO) and holding `ufo_windup` pulls the plunger: the power climbs to full, drops back to zero and climbs again (a sawtooth, shown on the gauge beside the bird); release, or the countdown ending, plunges. Reach is `(launch speed − stop_speed) / plunge_drag`; full power is computed per level (`_full_launch_speed`) to just reach the far bottom corner of the opening screen, so steeper full-power plunges overshoot and bounce off the bounds (`_fold_into_bounds()`). One random reachable `SeaUrchin` glows as the Picky Puffer's target; stopping within `eat_radius` of it calls `SeaUrchin.be_eaten()` (gone for good, `SeaUrchinGroup.forget()`) and `GameManager.record_puffer_skill_shot()` (`puffer_skill_shots`, run state, saved — for the future Puffer Party bonus level). A catch also brings a trash bag in `trash_bag_delay` seconds later (`HUD.spawn_bonus_trash_cluster()`). Then the tree unpauses, `started` fires and the bird flies off — carrying the caught urchin in its feet, the way it held the turtle. The cut scene before such a level (`cut_scenes/level_transition_cutscene.gd`) checks `PufferBirdLauncher.level_has_launcher()` on the next level's scene and, if so, flies a puffer bird diagonally after the falling turtle. `camera_2d.gd` `snap_to_target()` re-frames the camera on the moved turtle while it can't process.

**Level 6** is three screens wide (x −960..960, camera follows horizontally) with the sky above all of it — a pinball table meant to be crossed on flippers, with swimming only sprinkled in. Elements sit under `OceanWest/Central/East` and `SkyWest/Central/East` containers. The ocean is five *stations*: a tent (down-flipper pair, dive shots for floor pickups) over a valley (west/east flippers under long awnings, lateral shots toward the next station). Every ocean `DeadWall` there is a *valve*: its `CollisionShape2D` is overridden with `one_way_collision = true` and `scale = Vector2(-1, -1)`, so shots pass through from above/outside and a rising turtle is caught from below. The sky uses cloud flippers and ordinary pass-through walls (a low eastbound line, a high westbound one). Three currents act as ramps into the sky (`WestRamp`, `Chimney`, `Geyser`). Its `UFOWorkshop` instances set `relocate_on_delivery` (after each delivery but the last the workshop `hop_to()`s another placed spot at least `relocate_min_distance` away) and `offscreen_pointer` (`WorkshopPointer`, a screen-edge arrow); set them on any one instance — the election hands them to the survivor. Pieces come from two `UFOPieceSeeder`s with `use_fixed_points` (floor spots, and sky ledges); each spawn point is used once per seeding.

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
   - **Cradle Scope is the one passive tech with an effect class** (`CradleScopeEffect`, `needs_input: false`, never `activate()`d): its `physics_process()` switches the scope on when `FlipperBase.is_cradling(player)` and keeps it while the turtle touches that flipper. The line comes from `FlipperBase.predict_press_launch()`, which shares `_launch_velocity()` with `hit_body()`; `hit_body()` in turn launches from the scope's frozen aim point (`TurtlePlayer.cradle_scope_origin()`), so the launch matches the line. Cold = short line, hot = ray to the first wall/enemy.
   - **Time Crawl** (`TimeCrawlEffect`) slows the world through its own `GameSettings.set_time_crawl()` channel (the slower of it and Acceleration Focus's `set_time_dilation()` applies) and exposes a `scale_factor` that `TurtlePlayer` multiplies into Stim Shot's turtle-clock hooks (`clock_scale`) plus kick strength, so the turtle slows less than the world. `notify_launch()` speeds launches up by part of that factor (`LAUNCH_COMPENSATION`) to offset the stronger drag. Its 3s window is timed in real seconds; the cooldown is held until it ends (hot: no cooldown, but a press mid-crawl is ignored).
   - **Deferred cooldown**: a tech whose cooldown should run from the *end* of its action (Multi-Beam) is listed in `AlienTechManager._HOLD_COOLDOWN_TECHS`. `try_activate_slot()` still seeds the cooldown on press (bar reads full, re-presses refused) but `_process()` doesn't drain it until the effect calls `AlienTechManager.release_cooldown_hold(id)` (optionally with a `max_remaining` cap, which Multi-Beam uses to shorten the cooldown after a miss). Every exit path of the effect — including `cancel_on_damage()` — must reach that call, or the slot stays locked; a fresh `TurtlePlayer` clears any leftover holds in `_ready()`.
5. **Adding a new activate-on-press tech**: add a definition to `AlienTechRegistry._definitions`, add a constant ID, add a `_COOLDOWN_DURATIONS` entry if it needs cooldown, create `entities/player/alien_tech_effects/<name>_effect.gd` extending `AlienTechEffect`, register it in `TurtlePlayer._ready()` (`_tech_effects[AlienTechRegistry.YOUR_ID] = YourEffect.new()`) — no dispatch code needed beyond that. Update `AlienTechManager.try_activate_slot()` only if the tech needs special activation logic (see Powerup Replicator's tap-vs-hold handling for an example of a tech that bypasses `try_activate_slot()` entirely via its own `handle_input()` called from `TurtlePlayer`'s input loop).

### Enemies (`entities/enemies/base_enemy.gd`)

All enemies extend `BaseEnemy` (which extends `RigidBody2D`). Override `_enemy_ready()` for per-enemy setup. Key behaviors inherited: `take_damage()`, `die()` (with 2% chance to drop an alien tech piece), `phase_shift()` (used by Phase Shifter tech), contact-damage area via a child `DamageArea` node.

**Spawn clearance**: no spawner may put an enemy on top of the turtle. `EnemySpawnSafety` (`entities/enemies/enemy_spawn_safety.gd`) has the shared radius (`MIN_TURTLE_DISTANCE`) and helpers: `random_point()` to pick the spot, and `move_clear()` again when the enemy actually appears, since the turtle moves during the spawn telegraph. Puffer and squid spawners use their own (larger) `min_player_distance`. A new spawner needs the same two checks.

An enemy that defines `on_super_speed_contact(turtle)` gets that call from the turtle's `SuperSpeedArea` instead of `take_damage(super_speed_damage)`. `PufferFish` uses it to swallow the turtle: `TurtlePlayer.enter_puffer()` hides the turtle, disables its collision and hands its physics tick to `PufferFish.update_capture()` (so the capture keeps running under Time Freeze / shock) until `exit_puffer()` launches it out of the mouth. While `captor_puffer` is set the turtle is invulnerable and super speed / ocean physics are off, the same way they are during a Bumper Magnet attach.

`Squid` (`entities/enemies/squid/`) hides in walls (HIDE → THRUST → SWIM). Hide spots come from `Squid.find_hide_spots()`, which raycasts for any `DeadWall` face or collidable `TileMapLayer` (ocean walls/floor) and returns the surface point + normal; `SquidSpawner` uses the same helper to place squids hidden at level start. Hiding holds position by velocity rather than `freeze`, since Time Freeze / `EnemyShock` save and restore `freeze`. Each thrust drops an `InkCloud` that calls `TurtlePlayer.apply_ink()` — while `is_inked()`, `shoot()` returns early (covers every spit type) and the sprite pulses black.

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

### Virtual Keyboard

`VirtualKeyboard` (`ui/shared/virtual_keyboard.gd`, built in code) is an on-screen keyboard for typing into a `LineEdit` with a gamepad — Godot's `DisplayServer.virtual_keyboard_show()` only works on mobile/web. Set `target`, add it, `focus_first_key()`; keys use normal focus navigation (A presses), B = backspace, Y = space, `done` fires on its Done key. It types at the field's caret (so `max_length` holds), replaces a prefilled default on the first letter, and auto-capitalises word starts (Shift flips the next letter). Show it only while `GameSettings.using_gamepad` (listen to `input_device_changed`) — the Academy's graduation name prompt (`AcademyPanel.ask_name()`) does exactly that.

### Menu Panels

Menu boxes are hand-drawn 9-slice art (`ui/panel_base.png`, 6px corners), registered in `theme/pixel_theme.tres` as theme type variations of `PanelContainer`: `PanelBase` (16/14 content padding, popups), `PanelBaseCompact` (8/14/8/8, the full menus) and `PanelBaseOpaque` (`ui/panel_base_opaque.png`, 16/14 — for dialogs that stack on top of another menu, like `TurtleConfirmDialog`), plus `PanelBaseCompactOpaque` (opaque art with the compact padding — the Academy info panel). A menu panel sets `theme_type_variation` to one of these instead of carrying its own `StyleBoxFlat` override — including panels built in code (`TurtleConfirmDialog`). The Alien Tech selection screen and its help dialog are deliberately left on their own flat styles. New panel art = new `StyleBoxTexture` + variation in the theme.

### Trash Cleanup System

`TrashSequenceSpawner` (in `systems/trash_cleanup/`) periodically spawns `TrashSequence` nodes. Each sequence contains multiple `TrashItem` collectibles in patterns (STRAIGHT, WAVE, DIAGONAL). Completing a sequence awards a powerup.

### Rainbow Fish Minigame

Opt-in per level: instance `systems/rainbow_fish/rainbow_fish_spawner.tscn` (`RainbowFishSpawner`) anywhere in the level and set `kill_triggers` (kills per round, counted from level start / the last failure, each rolled ± `kill_trigger_jitter` — its length caps the rounds), `fish_per_color` and `free_points`. It counts `GameManager.enemy_killed` (emitted once per defeated enemy by `BaseEnemy`/`BaseEnemyStatic._report_kill()` — call that wherever a new enemy type is actually beaten, not from `die()`, which also runs for despawns). Red spawns first; freeing colour c spawns 2c+1 and 2c+2 (×`fish_per_color`; every fish of the colour must be freed — the earlier ones swim off, the last one paints and advances the colour). Each round opens with `RainbowFishPopup` (`ui/menus/`), which pauses until any input. Fish of the next colour pulse (`is_target`). Fish are freed by spit or a super-speed hit (`on_super_speed_contact()`, same SuperSpeedArea hook as `PufferFish`); a normal-speed bump does nothing. Hitting a fish out of ROYGBIV order, or the round timer (`round_seconds_per_fish` × `fish_per_color`, +`seconds_per_free` per correct free, shown centred on the HUD via `show_rainbow_timer()`) running out, fails the round: the `RainbowArc` shatters (`dissolve()`: chunks crash into the ocean, splash, sink and fade) and every trapped fish dies in place, the wrong one included. Freeing the last colour wins (`_win()`) and opens the bonus rainbow level entrance at once, without waiting for the final stripe to finish painting: `_open_bonus_rainbow_level_entrance()` builds two `OceanCurrent`s at runtime (Curve2D from `RainbowArc.band_point()`, starting `entrance_current_depth` under the water at each end, riding the band to the apex) and lights a glow at `RainbowArc.apex()`; while the turtle rides them the level camera frames the whole rainbow (`camera_2d.gd` `focus_on()` / `release_focus()`, which override its state machine). Reaching the glow emits `bonus_rainbow_level_entrance_reached`; the turtle glides into its centre, shines like a rainbow (`TurtlePlayer.rainbow_shine`, top priority in `_update_sprite_modulate()`), then `RainbowBonusManager.enter()` fades to white and takes it into the bonus rainbow level; on return the entrance closes (one visit per rainbow). State is per level — nothing carries over.

`RainbowFish` (`entities/npcs/rainbow_fish/`) is on the Enemies layer so spit hits it but is **not** in `"enemies"` (homing, Shockwave, flippers ignore it). Player projectiles call `on_shot()` for the `"rainbow_fish"` group — a new projectile type needs that branch too. It bounces only off ocean walls (`RainbowFish.is_ocean_wall()`: TileMapLayers + `WorldSafetyBoundaries`) and the surface, and passes through bumpers/flippers/dead walls.

### Bonus Rainbow Level

`levels/bonus/rainbow_bonus_level.tscn` (`RainbowBonusLevel`) — inside the rainbow: 7 screens tall (x −320..320, y 0..2520), one band per colour, red on top (`RainbowBonusBackground`, a `@tool` draw so the bands show in the editor). An Ocean far below violet gives the turtle normal sky physics everywhere. The turtle starts at the bottom of `LaunchCurrent` (right edge, walled off by `LaunchWall`) and is shot out into red; falling out the bottom of violet, or dying, ends the level. `RainbowBonusCamera` follows the turtle vertically. Every `CircularBumper.player_bounced` spawns a `Fruit` (`entities/collectibles/fruit/`, collect-by-touch, hovers) in the upper half of that bumper's band, ≥ `fruit_min_turtle_distance` from the turtle, capped at `max_fruit_per_band` uncollected; worth `Fruit.BASE_POINTS` (50) × band level value (red 7 … violet 1). Points are tallied by the level and paid out on `RainbowBonusSummary` (`ui/menus/`) when the level ends; the fruit type is random from the sheet (2 frames per fruit — widen the sheet to add more).

`RotatingLauncher` (`entities/environment/rotating_launcher/`, an `Area2D`; `comet.png` is split in code by `_build_frames()` into a head that never rotates and a tail that swings round it to sit opposite the aim / drift) is a comet — a passive pinball element that never damages and needs no super speed. WANDERING: drifts slowly around its home (its scene position, `wander_range`). HOLDING: touching it pulls the turtle in through the puffer capture (`TurtlePlayer.enter_puffer()` / `update_capture()` / `exit_puffer()`); it holds still while its aim spins. FLYING: the launch button (`ufo_windup`) or `hold_seconds` running out fires the turtle out as a normal physics body, and the comet follows it as a cloud (it no longer catches) until the turtle slows, bounces back or `max_flight_seconds` passes. GONE: it evaporates there and rematerialises around home after `respawn_seconds` (5). With `roams` set it has no home: it drifts on a meandering course all over `roam_area` (the bonus level has one, under `Roaming Launchers`) and rematerialises wherever it evaporated.

`RainbowBonusManager.enter(on_return)` (called by `RainbowFishSpawner` at the apex) doesn't save/reload the level: it disables it, fades to white (so in-flight SceneTreeTimer awaits finish in-tree), **detaches** it from the tree and makes the bonus scene current; `finish()` puts it back exactly as it was. Hearts and score are carried in and back, a carried UFO piece is held back, alien techs are used normally (their state is shared), and the turtle gets `grant_grace_iframes()` on return. A detached level still receives autoload signals — any handler that needs the tree must check `is_inside_tree()` first (TurtlePlayer, TechAura, AlienTechSelectionScreen do). Leaving the bonus scene any other way (pause-menu restart / main menu) frees the set-aside level.

**Rainbow hearts**: finishing the bonus level calls `GameManager.grant_rainbow_heart()` (run state, saved by `SaveManager`) and returns the turtle at full health. Each rainbow heart turns the next heart icon from the right into a 2-HP heart, so `TurtlePlayer.current_hearts` is really **HP**: full is `GameManager.max_hp()` (= `HEART_SLOTS` + rainbow hearts), not `MAX_HEARTS`. Damage drains HP from the right (one hit half-empties a rainbow heart, drawn by `ui/hud/shaders/rainbow_heart.gdshader`); `restore_hearts(n)` heals n *whole hearts* from the left (a rainbow heart counts as one heart, 2 HP). The heart maths (`heart_capacity()`, `max_hp()`) lives on `GameManager` so HUD code can use it without a circular dependency on `TurtlePlayer`.

### UFO Repair Turtle Academy

`levels/academy/academy.tscn` (`AcademyController`, extends `LevelBase`) — the gamified successor to the tutorial, being built alongside it (the old tutorial will be removed once the Academy is stable). Launched from the main menu via `LevelManager.load_academy()`; it shares the `LevelManager.is_tutorial` training-mode flag (no scoring, saving, progression or tech selection), respawns the turtle instead of game over (emitting `player_respawned`), and its HUD has air and trash bags off until needed.

- **Layout**: the left third of the screen is out of play. `AcademyPanel` (`academy_panel.gd`, a CanvasLayer) fills screen x 0..`PLAY_AREA_LEFT_X` (208) from the bottom of the HUD's top bar (tracked live) to the bottom edge; the left ocean wall / `BoundaryLeft` sit at world x −112..−104 beside it (camera fixed at x 0). Play area is world x −104..312, centred on x 104 — mirror layout pairs around that. `PinballElements` (Level 1-style flipper/wall units + bumpers) starts disabled and is revealed in Lesson 2.
- **Panel**: agenda (one drawn checkbox per lesson), lesson title, typewriter dialogue and a blinking hint line. `say(chunks, wait_last)` paginates each chunk by measuring the body (whole sentences per page) and waits for **Enter / gamepad A** after each page — not Space, which drops a piece (keyboard-only) or fires a tech slot (mouse mode) while the world keeps running.
- **Course**: `AcademyDirector` (`academy_director.gd`) runs the intro, Lessons 1–4, the exam and graduation as one coroutine (the exam is `_lesson_5()` / `start_lesson` 5 internally, but isn't on the agenda or numbered as a lesson — `AGENDA_LESSON_COUNT`). The play area is paused whenever the instructor talks so the player reads instead of playing: `_say()` pauses the tree and any task hint (`_set_task()`) un-pauses it. The director, the panel and the level song run with `PROCESS_MODE_ALWAYS`; waits resume on the director's own `_ticked` signal, which is skipped while the pause menu is open (the menu restores the paused state it found). Enemy challenges restart on death (`_enemy_challenge()`); the exam needs `EXAM_DELIVERIES` (2) pieces delivered without dying; for the first one the swim-hold limit applies (`EXAM_SWIM_HOLD_LIMIT_SECONDS`, shown as the `SwimPie` by the turtle — holding a swim direction that long in one go restarts just that piece, turtle back at the centre; the same "flowing dance" rule that Lesson 2's `_nudge_challenge()` introduces with the shorter `SWIM_HOLD_LIMIT_SECONDS`). Between that challenge and the exam the rule stays on for every challenge at the longer limit: `_swim_hold_start()` / `_swim_hold_stop()` switch it, `_process()` counts it and sets `_swam`, and each challenge loop clears `_swam` when it starts and restarts itself (with `SWAM_TEXT`) when it sees it — a new challenge loop needs that check too. The workshop never treats a training-mode delivery as a level's final piece (that would mute the HUD energy-charge sound). Each lesson (and graduation) opens with `AcademyPanel.play_banner()` (flash + band + title, centred on the whole screen on its own top CanvasLayer, level paused, dismissed with Enter / A); flipper practice in Lesson 2 keeps the level paused and lets only the `FlipperBase` nodes run (`_set_flippers_live()`). Passing asks the graduate to sign their certificate (`AcademyPanel.ask_name()`, saved via `SaveManager.set_player_name()` / `get_player_name()` in the permanent best-scores file — the player name for a future scoreboard), shows "[NAME], Certified UFO Repair Turtle", saves `SaveManager.set_academy_certified()` and returns to the main menu. Set the director's `start_lesson` export to jump straight to a lesson while tuning (keep it 0).
- **Hooks it relies on**: `GameManager.flipper_launched` / `last_flipper_launch_msec`, `TurtlePlayer.shoot_locked` / `spit_fired` / `powerup_applied`, `UFOPiece.pickup_filter` (Lesson 2's "flipper hits only"), `HUD.score_clusters_enabled`. Spawned scenes get `position` set **before** `add_child()` — sea urchins anchor to wherever `_ready()` finds them.

### Score → Alien Tech Pipeline

Defeating enemies has a 2% chance to drop an `AlienTechPiece`. Collecting one calls `AlienTechManager.collect_piece()`. When `pieces_this_threshold >= PIECES_PER_TECH` (currently 1), `AlienTechManager` emits `selection_ready` and shows the tech selection screen. Tech selection assigns a tech to an empty slot.

**Insight (skip/reroll)**: declining an offer ("Study it") calls `AlienTechManager.study_tech()` for +1 `insight`. With Insight, the selection screen shows "Use Insight", which instantly spends one via `use_insight()` to swap the offer for a different random tech (never the current offer or an equipped tech). Run state — cleared in `reset_run()`, saved by `SaveManager`.

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
