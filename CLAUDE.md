# Tile-Capture Shooter — Project Guide (CLAUDE.md)

3D third-person shooter where the map is a grid of 5 m capturable tiles. Territory control — not
raw aim — is the main source of advantage: you may only move on tiles your team has captured or that
are adjacent to them. Close-range, fighting-game-flavored combat, WoWS-style detection, Hisoutensoku
-style mid-match card draws, buildable structures, energy-gated actions. Launch target: **1v1,
single-player vs bots**. Engine **Godot 4.7 stable**, Windows PC.

- **Authoritative design doc:** `docs/GDD.md` (read it for any feature's intent).
- **Approved roadmap (full):** `C:\Users\sawad\.claude\plans\you-are-claude-code-stateless-lemon.md`.

---

## ⚠️ HOW WE WORK — the cadence (do not skip)

Build **one milestone at a time**, foundations first. For each milestone:
1. **Ask** the milestone's clarifying/tuning questions (small focused batches).
2. **WAIT for the user to type "proceed"** before writing ANY build code. Answering the questions is
   NOT permission to build — the user often changes model effort between answering and "proceed".
3. **Build** the smallest testable increment.
4. **Verify via the Godot MCP**: run the headless self-test, scrape output, **run it twice and
   confirm byte-identical** (the determinism gate). Also boot the live scene and confirm no errors.
5. **Hand the user a precise manual playtest** and **wait for sign-off** before the next milestone.

Don't paint us into a corner: prefer designs that extend cleanly (netcode, hex tiles, FOV slider).
When the user requests a change, explain the approach and **wait for "proceed"** before coding.

---

## Hard constraints

- **Determinism is mandatory.** All randomness goes through the seeded `Rng` autoload (named
  streams). No `randf()`/global random anywhere. Durations are counted in **integer ticks**, never
  by accumulating float `dt` (float accumulation drifts off exact boundaries — learned in M4).
- **Netcode-ready from day 1.** Player input is separated from simulation: every actor emits an
  `InputCommand` per fixed tick; the sim reads commands, never raw `Input`. Bots/replays are just a
  different `InputProvider`. Don't build networking yet — just keep the seam clean.
- **Fixed 60 Hz sim tick** (`physics_ticks_per_second=60`). Sim logic lives in pure, headlessly
  testable `RefCounted` classes under `sim/`; nodes apply the results.
- **Placeholder art only:** capsules, boxes, plane meshes, simple colored materials. No assets.
- **Target Godot 4.7 APIs.** Keyboard+mouse default; **controller support required** (abstracted in
  the input layer from M1; verify KB+M every milestone, one dedicated controller pass later).

## Godot/GDScript gotchas (all hit during M0–M7)

- **Use `preload("res://...")` + `extends "res://..."`, NOT `class_name`.** A never-opened project
  has no global class cache, so `class_name` identifiers fail in headless CLI runs ("Identifier …
  not declared"). Autoloads (e.g. `Rng`) resolve fine without the cache.
- **Self-tests must NOT `quit()`.** `get_debug_output` only scrapes a LIVE process; a test that
  quits exits before output is read. Tests print `[TEST] … PASS/FAIL` + `[TEST] SUITE <id> RESULT
  passed=X failed=Y`, then **idle**. End the run with `stop_project`.
- **Untyped/dynamic returns can't drive `:=` inference.** If `x` comes from an untyped var or an
  `Object`-typed value, write `var x: bool = ...` (not `:=`). This bit us repeatedly.
- **A `Camera3D` needs `current = true`** or you get Godot's default grey screen.
- **Don't name a method `_set` (or other `Object` virtuals).** `_set(name, value)` is a built-in
  virtual; a helper named `_set` fails parse with "signature doesn't match the parent" (hit in M5 —
  renamed to `_dset`). Same care for `_get`, `_init`, `_ready`, etc.
- **A ternary whose two branches are different script types warns** ("Values of the ternary operator
  are not mutually compatible"; hit in M6 picking `LocalInputProvider`/`BotInputProvider`). Use a
  plain `if/else` assignment instead — warnings show up in the MCP `errors` scrape.
- **Sub-resources are SHARED across instances of a PackedScene by default.** Two `player.tscn`
  instances shared one `CapsuleShape3D`/`CapsuleMesh`, so `_apply_crouch` mutating `.height` made the
  two actors fight over it (M6 crouch bug). Set `resource_local_to_scene = true` on any sub-resource a
  script mutates per-instance (or `.duplicate()` it in `_ready`).

## Running things via the Godot MCP

- Self-test: `run_project(projectPath="C:\\claude\\tile game", scene="res://tests/test_mX.tscn")`
  → poll `get_debug_output` → parse → `stop_project`. Run twice; output must be identical.
- Live scene: `run_project(..., scene="res://scenes/mX_*.tscn")`, check `errors` empty, `stop_project`.
- `project.godot` `run/main_scene` points at the current milestone's scene.

---

## Architecture & directory layout

```
project.godot      4.7, Forward+ (Vulkan), max_fps 60, physics 60 Hz, autoload Rng, main_scene = current milestone
services/rng.gd    Rng autoload: seeded named streams, per-match overridable seed (logged)
sim/               deterministic simulation (pure RefCounted; headlessly tested)
  world.gd           M0 demo SimWorld (tick/hash/record-replay contract)
  player_motion.gd   movement model (velocity from command+dt+on_floor+yaw; caller integrates)
  tile_topology.gd   shape-agnostic tile interface (enumerate, world<->tile, cell_polygon, edge_neighbors)
  square_topology.gd 9x20 @5 m, origin centered, Vector2i(col,row) 1-indexed
  tile_grid.gd       ownership state, spawns, is_unloseable, set_owner, outline_category
  capture.gd         integer-tick capture sim (capture/neutralize/contest/comeback/immunity)
  movement_restriction.gd  M5 walkable-region clamp (owned∪neighbors; margin inset; stranded free-roam)
  match_state.gd     M7 deterministic match/round phase machine (countdown/active/over; points→round→match)
  team_colors.gd     customizable palette (static vars; blend derived)
input/
  input_command.gd       per-tick intent: move_dir, look (rad), buttons bitmask (JUMP/SPRINT/CROUCH/ADS)
  input_provider.gd      base; ScriptedInputProvider (tests/replay); LocalInputProvider (KB+M+pad)
  bot_input_provider.gd  M6 trivial bot: constant move_dir (default forward), zero look/buttons
  default_binds.gd       registers default InputMap actions at runtime (code defaults until Config menu)
scripts/
  player.gd          CharacterBody3D: provider→PlayerMotion→camera rig; M5 restriction; M6 is_local/bot; M7 active/reset
  tile_grid_view.gd  tile visuals; drives capture from BOTH actors; binds restriction; M7 snapshot/reset_world; F1/F2/F3 debug
  match_director.gd  M7 per-tick orchestrator: drives MatchState, freezes actors + gates capture by phase, resets, debug HUD
scenes/             bootstrap, player, m1_movement..m7_match (per milestone; player.tscn shared)
tests/              test_m0..m7 (.gd + .tscn), idle-print pattern
docs/GDD.md         authoritative spec
```

**Input → sim seam:** `LocalInputProvider.poll()` reads `Input` (the only place) and returns an
`InputCommand`. Mouse look is fed in via `add_mouse_motion()` from the player's `_input`. Sprint and
ADS are resolved to be mutually exclusive in the provider (`resolve_exclusive`, last action wins).
**A bot is the same actor with a different provider** (`BotInputProvider`) — `player.gd`'s `is_local`
flag only gates the local-only bits (mouse capture, camera). This is the netcode/replay seam.

**Tile shape abstraction:** all grid logic goes through `TileTopology`; `SquareTopology` ships now, a
`HexTopology` could drop in later with only a map regen. Adjacency = shares an edge (never diagonal);
outlines are drawn from `cell_polygon` so hexes would render correctly.

---

## Locked design decisions

1. Tuning numbers gathered per-milestone (not all up front).
2. Architecture = fixed-tick `InputCommand` pipeline + seeded RNG inside the sim.
3. Flat arena, no cover initially (verticality via structures later).
4. Per-match overridable seed via the single `Rng` service.
5. Movement restriction feel = **hard stop, slide along the tile edge** (M5).
6. Controller abstracted from M1; aim-assist policy deferred to combat.
7. Gameplay-first; full Main Menu + Config (keybinds/sensitivity/FOV/FPS/renderer) is a late
   milestone. Keybinds live in the InputMap with code defaults until then.
8. Grid: 9 cols along X (45 m) × 20 rows along Z (100 m); origin centered; `Vector2i(col,row)`
   1-indexed; spawns `(5,1)`=Team 1 and `(5,20)`=Team 2, both pre-owned and **un-loseable**.
9. Tile shape abstracted (square now, hex-ready), adjacency = shared edges, outlines from cell polys.

### Tuning chosen so far
- **Movement (M1):** walk 5 m/s, sprint ×1.6, crouch ×0.5; gravity 25, jump apex 1.2 m; ground accel
  56.25 / decel 68.75, air accel 12; crouch is ground-only (stand while airborne, resume on landing).
- **Camera/look (M2):** hip dist 3 / height 1.6 / shoulder 0.5 / FOV 75; mouse 0.003 rad/px, stick
  2.618 rad/s, pitch ±80°, invert off; body faces camera yaw (strafe). **ADS:** shoulder 0.5→0.85
  (shift RIGHT, character clears crosshair), **no pull-in** (dist stays 3.0), zoom via FOV
  magnification `ADS_ZOOM=1.8` relative to `_base_fov` (FOV-slider-safe; `set_base_fov()` stub),
  look sens ×0.6. Camera can't go under the floor (`camera_position_grounded`, `CAM_MIN_Y=0.4`).
  Sprint and ADS are mutually exclusive (most recent action wins).
- **Tile visuals (M3/M4):** neutral grey / Team 1 blue / Team 2 red; fill = owner color (blended
  toward capturing color by progress); 0.1 m outlines; outline = frontier category (neutral / team1 /
  team2 / blend-purple). Colors centralized + customizable in `team_colors.gd`. F1 toggles (col,row)
  debug labels (off by default).
- **Capture (M4):** capture neutral→yours = 300 ticks (150 with comeback when you own <5 tiles, which
  counts the spawn tile); neutralize enemy→neutral = 300 ticks (NOT sped by comeback); one continuous
  stand on an enemy tile goes enemy→neutral→yours; contest pauses/holds; leaving or death resets
  progress to 0; spawn tiles immune.
- **Movement restriction (M5):** walkable = your owned tiles ∪ their edge-neighbors; per-axis
  margin-inset clamp (`BODY_MARGIN=0.4` = capsule radius → whole body stays on legal tiles; set 0 for
  center-point). Hard-stop + slide along the boundary; pure XZ, **no vertical cap** (jumps blocked the
  same way at any height). **Stranded** (a tile flips under you → current cell illegal): no clamp,
  free roam until you re-enter a legal cell, then it re-engages — you can never *walk* yourself
  stranded. The clamp is **no-pushback**: it only blocks advancing further into a wall, never shoves
  you back, so re-entry (and a tile flipping illegal next to you) is smooth — you land in the margin
  band and the inset restores itself as you move inward (no inward snap). A separate **map border**
  (`_clamp_to_map` vs `topology.world_aabb()`, inset by margin) is applied on *every* path including
  stranded, so a stranded actor roams freely but can never walk off the map. Future cross-tile cards
  make the target legal or grant a temporary travel-illegal override (same bypass path as stranded).
  **Future M9:** severe damage-over-time while stranded. F2 debug = collapse Team-1 territory to
  spawn (force a strand for playtesting).
- **Second actor (M6):** the bot is the **same `player.gd` actor** with `is_local=false` →
  `BotInputProvider` (constant forward), no mouse/camera capture, camera not current, capsule tinted
  via `body_color`. The trivial "hold forward" + M5 restriction makes it creep its capture frontier
  tile-by-tile (no AI; real AI is M14). `tile_grid_view` feeds BOTH actors' tile presence into
  `capture.step`. Live scene: blue local player vs red bot down column 5, debug head-starts so the
  fronts meet near mid-map; **F3** toggles a top-down observation camera.
- **Match flow (M7):** `MatchState` (pure) = phases COUNTDOWN→ACTIVE→ROUND_OVER→(next round /
  MATCH_OVER); **3 points win a round, first to 2 rounds wins the match** (GDD §14); 180-tick (3 s)
  countdown + round-over freezes. `MatchDirector` (scene-root node, runs FIRST in tree so it gates
  the same tick) ticks the state, sets each actor's `active` + `view.set_capture_active` by phase, and
  on the `"round_reset"` event restores **match-start ownership snapshot** (`TileGrid.snapshot/restore`,
  incl. debug head-starts) + `Capture.reset()` + `player.reset_to_spawn`. Points come from **debug
  keys** standing in for M9 kills: **F4**/**F5** award Team 1/2 a point, **F6** restarts the match.
  M9 kills will just call `MatchState.add_point(team)` — nothing else changes. Minimal on-screen Label
  is a placeholder until the real HUD (M15).

---

## Status & remaining roadmap

**Done & signed off:**
- **M0** Project skeleton, `Rng`, fixed-tick `SimWorld`, `InputCommand` + providers, replay-hash.
- **M1** Player movement (capsule CharacterBody3D, KB+M + controller).
- **M2** Over-the-shoulder camera, mouse/stick look, ADS (right-shift + magnification zoom),
  camera-relative movement, ground clamp, sprint/ADS exclusivity.
- **M3** Tile grid data + visualization + coordinate/adjacency math (TileTopology/SquareTopology).
- **M4** Capture / neutralize / contest / comeback / spawn-immunity + frontier outlines.
- **M5** Movement restriction: walkable = owned ∪ edge-neighbors; margin-inset clamp (hard-stop +
  slide), pure XZ / no height cap, stranded = free roam back to territory. Live with captures.
- **M6** Second actor: `BotInputProvider` (trivial hold-forward) on a second `player.gd` instance;
  both actors' presence drive capture; creeping two-actor tile war; F3 top-down camera.
- **M7** Match/round state machine (`MatchState`) + `MatchDirector` orchestrator: countdown/round/
  match phases, freezes, and clean deterministic resets (tile snapshot + actor respawn). Debug F4/F5
  points (placeholder for M9 kills), F6 restart. Foundations complete.

All milestones have green self-tests (test_m0..m7) that pass twice byte-identically.

**Feature layers (each opens with its own tuning questions):**
- **M8 (NEXT)** Weapons & firing (hitscan + projectile, seeded spread, ADS = no spread, falloff,
  headshots). Fire is an `InputCommand` button; spread via the seeded `Rng`. *Open:* all combat numbers.
- **M9** Health / death / respawn (5 s invuln, broken by firing) + kills→score (3/round, 2 rounds/match).
  A kill calls `MatchState.add_point(team)` (the M7 scoring skeleton already handles round/match flow);
  replace the F4/F5 debug points. *Also wire the M5 stranded damage-over-time here* (severe DoT while
  on an illegal tile until you reach a legal one — the `_apply_tile_restriction` stranded branch in
  `player.gd` is the hook).
- **M10** Energy (200; sprint/dodge/shield/build; 0→2 s stun) + dodge roll + directional shield.
- **M11** Detection (20 m, 50 m/1 s on fire, team-shared, 3 s linger, outlines + HP bars, indicator).
- **M12** Structures (build radial menu; wall/turret/lookout; owned-tiles-only; persist; SpringArm
  camera collision lands here).
- **M13** Cards & decks (deckbuild in menu, seeded draws, 5-card hand visible to both, swap/use).
- **M14** Bot AI (difficulty levels; capture/fight/build/card behavior).
- **M15** Full HUD (§15 of the GDD).
- **M16** Menus & Config (Main Menu, keybind rebinding, sensitivity, FOV slider, FPS cap, renderer).
- **M17** Vertical-slice integration + full-match determinism replay.

**Deferred tuning to ask at the relevant milestone:** all combat/weapon numbers, energy costs/regen,
respawn delay, base HP, card list/effects/cadence, structure stats, bot difficulty definitions,
controller default bindings + aim-assist policy.
