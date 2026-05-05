---
name: Alien Tech Acquisition System Design
description: How alien tech pieces are acquired — sources, spawning, and selection flow
type: project
---

Alien tech pieces now come from three sources (as of May 2026 redesign):

1. **Trash Clusters** — slow-moving multi-hit objects (5 shots) that spawn every 200 points. Each drops one AlienTechPiece on destruction. Spawned from screen right edge by HUD's `_spawn_trash_cluster()`.
2. **Enemy death** — 2% chance any enemy drops an AlienTechPiece on death (both BaseEnemy and BaseEnemyStatic).
3. ~~Ocean flora~~ — **REMOVED**. Previously hidden pieces in flora. OceanFloraSeeder and OceanFlora stripped of all tech piece logic.

**Selection flow**: Collecting a piece immediately offers ONE random tech (CHOICES_OFFERED = 1). Player sees "Alien Tech Found!" with Equip/Skip buttons. No choice between options — the randomness is the journey.

**Why:** User found fauna hunting busy and thematically wrong (turtle shouldn't shoot animals). Trash cluster approach fits the ocean cleanup theme and gives more natural pacing.

**How to apply:** Don't reintroduce fauna-based tech spawning. Trash cluster hitpoints (`max_hits`) and spawn interval (`CLUSTER_SCORE_INTERVAL` in hud.gd) are tunable. Enemy drop rate is `randf() < 0.02` in both base enemy classes.
