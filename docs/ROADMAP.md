# ROADMAP — status & remaining milestones

Single source of truth for build status. Design intent: `docs/GDD.md`. Symbol map: `docs/CODEMAP.md`.
Working rules + locked decisions: `CLAUDE.md`. Each milestone: build the smallest increment → verify
(headless self-test twice byte-identical + live boot errors-empty) → manual playtest → sign-off before
the next. Tuning numbers are gathered at the start of each milestone (locked decision #1).

## Current position
**M0–M11 signed off. M11.5 (cleanup pass) BUILT & verified — awaiting playtest sign-off. M12 (Structures) is next.**

## Done

| # | What shipped |
|---|---|
| **M0** | Project skeleton, `Rng` autoload, fixed-tick `world.gd`, `InputCommand` + providers, replay-hash. |
| **M1** | Player movement (`player_motion.gd` + `player.gd` CharacterBody3D), KB+M + controller. walk/sprint/crouch, gravity/jump, ground-only crouch. |
| **M2** | Over-shoulder camera, mouse/stick look, ADS (camera shifts right + FOV-zoom, no pull-in), camera-relative move, ground clamp, sprint/ADS mutually exclusive. |
| **M3** | Tile grid data + visuals + coord/adjacency math (`tile_topology`/`square_topology`/`tile_grid`/`tile_grid_view`). |
| **M4** | Capture/neutralize/contest/comeback/spawn-immunity (`capture.gd`, integer-tick) + frontier outlines (`team_colors`). |
| **M5** | Movement restriction (`movement_restriction.gd`): walkable = owned ∪ edge-neighbors; margin-inset hard-stop-slide, no-pushback, stranded free-roam, separate map border. |
| **M6** | Second actor = same `player.gd` with `is_local=false` + `bot_input_provider` (hold-forward); both drive capture; F3 top-down cam. |
| **M7** | Match/round machine (`match_state.gd`) + `match_director.gd`: countdown/active/round-over/match-over, 3 pts=round, first-to-2-rounds=match, clean snapshot/restore resets. |
| **M8** | Weapons: revolver (hitscan) + bolt (projectile); seeded hip spread, falloff, headshots, mag+reload, switch 1/2; `weapon_defs`/`weapon_loadout`/`ballistics` + `combat_director`; two-trace aim convergence. |
| **M8.5** | Recoil (`recoil.gd`): aim-punch + AOP auto-recovery through the look channel; SMG full-auto test weapon (key 3); `$Muzzle` marker; crouch camera-drop. |
| **M9** | Health/death/respawn (`health.gd`): base HP 100, respawn 3 s, spawn invuln 5 s broken by firing, stranded DoT = territory kill; kills → `MatchState.add_point` via `died`; debug F4/F5 damage. |
| **M10 + M10.1** | Energy/dodge/shield (`energy`/`dodge`/`shield`): 200 pool, 2-phase stun→recovery, per-action regen delay; dodge burst; toggle-F shield (ray-vs-quad block, absorbs into energy); energy-gated sprint. |
| **M11** | Detection (`detection.gd` + `detection_director.gd`): WoWS bloom (firing reveals you); base 17.5 m, fire-bloom 50 m/1 s, linger 2 s, team-shared, center-to-center. Enemies hidden until detected (single `$Model` toggle — asset-swap seam); red silhouette + billboarded HP bar; `detect` HUD line. |
| **M11.5** | Cleanup (9 fixes): dead actors stop capturing; ADS walk ×0.75 (stacks w/ crouch); firing interrupts sprint (`fire_while_sprint` hook); state-dependent hip+ADS spread (`spread_hip`/`spread_ads` × `spread_state`); semi-auto + 0.2 s input queue (`auto` flag); post-dodge 0.2 s lock; dodge defaults forward; gradual integer-tick crouch. **← awaiting sign-off.** |

## Remaining (feature layers — each opens with a tuning-question batch)

- **M12 — Structures.** Build radial menu (Build key `B`); buildable only on owned tiles; wall
  (instant, blocks fire/climbable), turret (auto-fire, build time), lookout (climbable, sets all
  detection to 50 m); one-per-tile (rebuild replaces); persist through capture changes; inactive on
  neutral. **Build = the 4th energy consumer.** SpringArm camera-vs-wall collision lands here. *Tuning:
  full structure list, costs, build times, turret range/damage/fire-rate, wall HP.*
- **M13 — Cards & decks.** Deck-build in menu from a fixed card set; seeded mid-match draws; 5-card
  hand visible to both; default-first selection, Swap (`E`) cycles/wraps, Use (`Q`) plays; effects with
  durations. *Reuses the M5 clamp-bypass seam: a "may travel on illegal tiles" card grants a temporary
  travel override on the same path as `stranded`/DoT (see `movement_restriction.clamp_move`).* *Tuning:
  full card list/effects/numbers, draw cadence, deck rules, hand-reset behavior.*
- **M14 — Bot AI.** Real difficulty-scaled AI via `BotInputProvider` (still just emits `InputCommand`s):
  capture/fight/build/card behavior. This is when the shield-block & detection become fully live-testable
  (the M6 bot doesn't return fire yet). *Tuning: difficulty definitions.*
- **M15 — Full HUD (GDD §15).** HP+energy (bottom-left), ammo + your hand (bottom-right), opponent
  hands (top-left), capture bar (lower-middle), kill+round score (top-middle), detection indicator.
- **M16 — Menus & Config.** Main Menu (Play/Config/Exit); Config: rebind all actions, mouse & ADS
  sensitivity, FOV, FPS cap (≤144), show-FPS, renderer select (Vulkan/D3D12/Compatibility/Mobile);
  persist to disk.
- **M17 — Vertical slice + full-match determinism replay.** All systems together; record a full match
  (seed+inputs) → replay to an identical end-state hash; perf sane at the 60 FPS cap.

## Deferred tuning (gather at the milestone)
Structure stats/costs/build-times (M12); card list/effects/cadence/deck rules (M13); bot difficulty
definitions (M14); controller default bindings + aim-assist policy (controller pass). A full
combat/movement **balance pass** is planned before M14.

## Determinism scope (honest note)
Target = **same-binary reproducibility** (identical seed+inputs → identical run on this machine) + clean
input/sim separation, so authoritative-server netcode + replays can layer in later. Bit-exact
*cross-machine* float determinism is NOT promised; we avoid the worst traps (kinematic bodies, no
unseeded RNG) so the door stays open.
