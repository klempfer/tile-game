# Tile-Capture Shooter — Project Guide (CLAUDE.md)

3D third-person shooter where the map is a grid of 5 m capturable tiles. Territory control — not raw
aim — is the main advantage: you may only move on tiles your team owns or that are edge-adjacent to
one. Close-range fighting-game-flavored combat, WoWS-style detection, Hisoutensoku-style mid-match
card draws, buildable structures, energy-gated actions. Launch target: **1v1 vs bots**. Engine
**Godot 4.7 stable**, Windows PC.

## Reference docs — read on demand (keep them out of every turn's context)

Only this file is auto-loaded each session. Read these when the task needs them; don't load them
speculatively.

| Doc | Read it when |
|---|---|
| `docs/GDD.md` | Implementing a feature or unsure of intended behavior — the authoritative design spec. |
| `docs/ROADMAP.md` | Starting a session or planning the next milestone — build status + what's next + forward stubs + deferred tuning. |
| `docs/CODEMAP.md` | Before editing `sim/`/`scripts/` — symbol map (per-file purpose, public function signatures, constant/var names) so you find the right code without opening every file. |

Full approved roadmap history: `docs/ROADMAP.md` supersedes the old planning artifact.

---

## ⚠️ HOW WE WORK — the cadence (do not skip)

Build **one milestone at a time**, foundations first. For each milestone:
1. **Ask** the milestone's tuning/clarifying questions (small focused batches).
2. **WAIT for the user to type "proceed"** before writing ANY build code. Answering the questions —
   and even **approving a plan** — is NOT permission to build; the user often changes model effort
   between approval and "proceed". Wait for the explicit word.
3. **Build** the smallest testable increment.
4. **Verify via the Godot MCP** (below): headless self-test, run **twice, byte-identical** (the
   determinism gate); boot the live scene and confirm no errors.
5. **Hand a precise manual playtest** and **wait for sign-off** before the next milestone.

When the user requests a change, explain the approach and **wait for "proceed"** before coding. In
plan mode: explore → confirm choices with AskUserQuestion → write the plan → ExitPlanMode. The user is
detail-oriented and iterates on plans before approving — that's expected. Don't paint us into a
corner: prefer designs that extend cleanly (netcode, hex tiles, FOV slider, future build/cards).

## Hard constraints

- **Determinism is mandatory.** All randomness goes through the seeded `Rng` autoload (named streams,
  e.g. `Rng.stream("weapon_spread")`); no `randf()`/global random. **Durations are integer ticks,
  never accumulated float `dt`** (float accumulation drifts off exact boundaries — learned in M4).
  Float magnitudes (HP, energy) are fine when inputs are deterministic; printed/HUD output uses
  rounded ints (`hp_int()`/`energy_int()`) so logs stay byte-identical.
- **Netcode-ready from day 1.** Every actor emits an `InputCommand` per fixed tick; the sim reads
  commands, never raw `Input`. Bots/replays are just a different `InputProvider`. No networking yet —
  keep the seam clean.
- **Fixed 60 Hz sim tick** (`physics_ticks_per_second=60`). Sim logic lives in pure, headlessly-
  testable `RefCounted` classes under `sim/`; nodes apply the results.
- **Placeholder art only:** capsules, boxes, planes, colored materials. No assets.
- **KB+M default; controller required** (abstracted in the input layer from M1; verify KB+M each
  milestone, one dedicated controller pass deferred).

## Godot/GDScript gotchas (all hit during M0–M11)

- **Use `preload("res://…")` + `extends "res://…"`, NOT `class_name`.** A never-opened project has no
  global class cache, so `class_name` fails in headless CLI runs. Autoloads (`Rng`) resolve fine.
- **Self-tests must NOT `quit()`** — `get_debug_output` only scrapes a LIVE process. Tests print
  `[TEST] … PASS/FAIL` + `[TEST] SUITE <id> RESULT passed=X failed=Y`, then idle; end with `stop_project`.
- **Untyped/dynamic returns can't drive `:=`.** If a value comes from an untyped var/`Object`, write
  `var x: T = …` (or `var x = …`), not `:=`.
- **A `Camera3D` needs `current = true`** or you get the default grey screen.
- **Don't name a method `_set`/`_get`/`_init`/other `Object` virtuals** (parse error).
- **A ternary whose two branches are different script types warns** — use a plain `if/else`.
- **Sub-resources are SHARED across `PackedScene` instances** — set `resource_local_to_scene = true`
  on any sub-resource a script mutates per-instance (the player capsule shape/mesh do this).
- **Don't shadow built-ins/`Object` methods/sibling methods** with a var/param name (all warn in the
  MCP `errors` scrape; `errors` empty must include no warnings).
- **A running MCP instance does NOT hot-reload edits** — `stop_project` then `run_project` again after
  editing, or `get_debug_output` reflects the OLD code.
- **`top_level = true`** decouples a node from its parent transform (camera; the M10.1 shield quad) —
  drive its global transform in code.
- **Node visibility propagates to children** — hiding a parent `Node3D` hides the subtree. The player's
  body meshes live under one `$Model` node so a single `visible` toggle hides everything (M11 detection
  + the future asset-swap seam).

## Running things via the Godot MCP

- Self-test: `run_project(projectPath="C:\\claude\\tile game", scene="res://tests/test_mX.tscn")` →
  poll `get_debug_output` → parse `[TEST] SUITE … RESULT` → `stop_project`. **Run twice; output must be
  byte-identical** (the determinism gate). `errors` must be empty (includes no warnings).
- Live scene: `run_project(scene="res://scenes/mX_*.tscn")`, confirm `errors` empty, `stop_project`.
  (MCP-launched windows sometimes grab focus and auto-fire — harmless.)
- `project.godot` `run/main_scene` = `scenes/m8_combat.tscn` (the richest scene: weapons/HP/energy/
  detection/match flow).

---

## Architecture & seams

**Directory layout** (full symbol map in `docs/CODEMAP.md`):
```
project.godot   4.7, Forward+, 60 Hz, autoload Rng, main_scene
services/rng.gd seeded named RNG streams
sim/            deterministic RefCounted sims (headlessly tested): topology/grid/capture/movement,
                match_state, weapon_defs/loadout/ballistics/recoil, health/energy/dodge/shield/detection,
                player_motion, team_colors
input/          input_command + providers (local reads Input; bot; scripted/replay), default_binds
scripts/        nodes that apply the sims: player.gd, tile_grid_view, match_director, combat_director,
                detection_director, bootstrap
scenes/  tests/ per-milestone scenes + idle-print self-tests   docs/  GDD, ROADMAP, CODEMAP
```

**The seams** (each keeps input→sim→node clean and netcode-ready; detail in `docs/CODEMAP.md` + code):
- **Input→sim:** `LocalInputProvider.poll()` is the ONLY place `Input` is read → `InputCommand`. A bot
  is the same `player.gd` with `is_local=false`; `is_local` only gates mouse capture + camera.
- **Combat (M8):** firing = `InputCommand` bits. `player.gd._fire()` steps `WeaponLoadout`; on fire it
  queues a Shot dict (`{weapon,muzzle,cam_origin,cam_dir,ads,spread_state,team,tick}`). Phase-gated
  `CombatDirector` (runs after actors) drains `consume_shots()`, converges aim (two-trace), resolves via
  `Ballistics`, applies `take_damage`. Not gated by `is_local`. Spread from `Rng.stream("weapon_spread")`.
- **Health/death (M9):** actor owns its life. `combat_director` → `victim.take_damage(...)`; a lethal
  hit hides the `$Model` + emits `died(killer_team)` → `MatchDirector` → `MatchState.add_point` (one path
  for weapon kills AND stranded territory deaths). Dead actors count down respawn independent of the M7
  freeze.
- **Energy/dodge/shield (M10/M10.1):** one 200 pool backs sprint/dodge/shield (build is M12).
  `player.gd` gates the command before motion: dodge first (uncancellable burst + post-roll lock),
  shield toggle (not planted), sprint drain. Directional block extends the damage seam via
  `take_damage(amount, team, shot_dir, hit_point)` (ray-vs-quad; absorbs into energy at 2×; `shot_dir=0`
  unblockable).
- **Detection (M11):** `player.gd` owns a `Detection`; `on_fire()` blooms its own detectability (WoWS).
  `DetectionDirector` (phase-gated, after actors) feeds each actor its nearest-enemy distance, steps it,
  and renders enemies only when detected via `set_detection_visual()` (single `$Model` toggle + code-built
  silhouette/HP-bar). The HUD reads the local player's `detected` for the indicator.

## Locked design decisions
1. Tuning gathered per-milestone (not all up front).
2. Architecture = fixed-tick `InputCommand` pipeline + seeded RNG inside the sim.
3. Flat arena, no cover initially (verticality via structures later).
4. Per-match overridable seed via the single `Rng` service (logged).
5. Movement restriction feel = **hard stop, slide along the tile edge** (M5).
6. Controller abstracted from M1; aim-assist policy deferred to a controller pass.
7. Gameplay-first; full Main Menu + Config is a late milestone (M16). Keybinds live in the InputMap with
   code defaults until then.
8. Grid: 9 cols along X (45 m) × 20 rows along Z (100 m), origin centered, `Vector2i(col,row)` 1-indexed;
   spawns `(5,1)`=T1 / `(5,20)`=T2, pre-owned + un-loseable.
9. Tile shape abstracted behind `TileTopology` (square now, hex-ready); adjacency = shared edges (never
   diagonal); outlines from cell polygons.
10. Controls: Move WASD · Jump Space · Sprint Shift · Crouch Ctrl · ADS RMB (toggle) · Fire LMB ·
    Reload R · Weapon 1/2/3 · Dodge X · Shield F (toggle) · Build B (M12). Debug: F1 labels · F2 strand
    · F3 top-down cam · F4/F5 debug-damage bot/self · F6 restart · Esc free mouse.

## Status
**M0–M11 signed off. M11.5 (cleanup pass) built & verified — awaiting playtest sign-off. M12 next.**
See `docs/ROADMAP.md` for the full status table + remaining milestones.
