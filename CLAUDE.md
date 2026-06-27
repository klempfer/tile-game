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

## Godot/GDScript gotchas (all hit during M0–M8)

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
- **Don't shadow built-in functions / `Object` methods / sibling methods with a var or param name.**
  All emit warnings that show up in the MCP `errors` scrape (M8): a var named `minf` shadows the
  global `minf()`; a `for tr in …` iterator shadows `Object.tr()`; a param named `team` shadowed our
  own `team()` method (→ renamed it `team_id()`). Pick non-colliding names.
- **A running MCP instance does NOT hot-reload your edits.** After editing a script, `stop_project`
  then `run_project` again — otherwise `get_debug_output`/`finalOutput` reflects the OLD code (bit us
  mid-M8: a "still failing" test was just the stale process).

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
  weapon_defs.gd     M8 weapon stat table (revolver hitscan / bolt projectile) + combat consts (DATA)
  weapon_loadout.gd  M8 per-actor fire-rate/ammo/reload/switch state machine (integer ticks; pure)
  ballistics.gd      M8 pure shot math: spread, ray-capsule hitscan, projectile step, falloff, headshot, aim_direction (two-trace)
  health.gd          M9 pure HP/death/respawn state machine (integer-tick invuln + respawn timers; stranded DoT)
  energy.gd          M10 pure energy pool: sprint/dodge/shield costs + 2-phase stun→recovery (integer-tick)
  dodge.gd           M10 pure dodge-roll kinematic burst (locked dir × speed for N ticks; no i-frames)
  shield.gd          M10 pure ±45° directional-block arc test (is a shot inside the shield's front cone)
input/
  input_command.gd       per-tick intent: move_dir, look (rad), buttons bitmask (JUMP/SPRINT/CROUCH/ADS + M8 FIRE/RELOAD/WEAPON1-3 + M10 DODGE/SHIELD)
  input_provider.gd      base; ScriptedInputProvider (tests/replay); LocalInputProvider (KB+M+pad)
  bot_input_provider.gd  M6 trivial bot: constant move_dir (default forward), zero look/buttons (never fires yet)
  default_binds.gd       registers default InputMap actions at runtime (code defaults until Config menu)
scripts/
  player.gd          CharacterBody3D: provider→PlayerMotion→camera rig; M5 restriction; M6 is_local/bot; M7 active/reset; M8 WeaponLoadout + queues Shots; M9 Health + take_damage/_die(died)/respawn + stranded DoT; M10 Energy/Dodge/Shield gating + take_damage(from_dir)
  tile_grid_view.gd  tile visuals; drives capture from BOTH actors; binds restriction; M7 snapshot/reset_world; F1/F2/F3 debug
  match_director.gd  M7 per-tick orchestrator: drives MatchState, freezes actors + gates capture/combat by phase, resets, debug HUD (+ M8 weapon/ammo, M9 HP line); M9 actor `died`→add_point scoring
  combat_director.gd M8 resolver: collects both actors' Shots, converges aim, resolves hitscan + steps projectiles vs enemy capsule; M9 applies damage to victim HP; spawns tracers/markers; phase-gated
scenes/             bootstrap, player, m1_movement..m7_match, m8_combat (per milestone; player.tscn shared)
tests/              test_m0..m7, test_m8, test_m8_5, test_m9 (pure sim) + test_m8_integration (combat+death node wiring) (.gd + .tscn), idle-print pattern
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

**Combat seam (M8):** firing is just `InputCommand` buttons. Each tick `player.gd._fire()` steps its
pure `WeaponLoadout`; when it fires it queues a **Shot** dict `{weapon, muzzle (eye), cam_origin (rig
pivot), cam_dir (look_forward), ads, team, tick}` into `_pending_shots`. The scene-level
`CombatDirector` (driven like `tile_grid_view`: phase-gated by `MatchDirector.set_active`, runs after
the actors so it sees this tick's shots) drains both actors' `consume_shots()`, resolves them via the
pure `Ballistics`, **(M9) applies the damage to the victim's HP via `victim.take_damage(dmg, team)`**,
and owns projectile state + placeholder visuals. Firing is **not** gated by `is_local` (a bot would
fire the same way — it just emits no fire button yet), so the netcode/replay seam stays clean. Spread
draws from `Rng.stream("weapon_spread")`.

**Health / death seam (M9):** the actor owns its life state. Pure `sim/health.gd` (RefCounted,
integer-tick) holds HP + invuln/respawn timers; `player.gd` feeds it damage (`take_damage`) and one
`tick()` per ACTIVE tick (timers pause during match-phase freezes). On a lethal hit the actor hides
its capsule and emits **`died(killer_team)`** — `MatchDirector` connects both actors' `died` to
`MatchState.add_point()` (the M7 scoring skeleton), so weapon kills AND stranded "territory" deaths
score through one path. Death/respawn are independent of the M7 `active` freeze: a dead actor in an
ACTIVE round holds still and counts down `RESPAWN_TICKS`, then self-respawns at its cached spawn pose
with `INVULN_TICKS` of firing-broken invulnerability. Stranded DoT hooks the `r["stranded"]` branch in
`_apply_tile_restriction` (credits the enemy team on death). Combat stays ignorant of scoring; it only
calls `take_damage`.

**Energy / dodge / shield seam (M10):** one 200 pool (`sim/energy.gd`, pure integer-tick) backs sprint,
dodge, and shield (build is M12). `player.gd` gates the per-tick command **before** motion: a dodge
(`sim/dodge.gd`, uncancellable burst — only look + ADS mid-roll) is triggered first and overrides
horizontal velocity; the shield (toggle `F`, owns `_shield_up`) drains while up and strips
sprint/fire/reload (but allows walk/crouch/jump); sprint drains 15/s and is stripped when unpayable.
Draining to 0 → **STUNNED 2 s** (no fire/reload/energy) → **RECOVERING** (refills 50/s, energy actions
locked but fire/reload allowed) → NORMAL at full. The **directional block** extends the M9 damage seam:
`combat_director._apply_hit` passes the shot direction **and hit point** to `take_damage(amount, team,
shot_dir, hit_point)`, and a raised shield blocks **only if the shot's path crosses the visible quad**
(`sim/shield.gd` ray-vs-quad — the quad tracks the full aim yaw+pitch, `top_level` `$ShieldVisual` driven
in code, pushed `SHIELD_DIST` out), absorbing the hit into energy (2× the damage) and leaking only the
unaffordable remainder to HP. Stranded DoT / debug damage pass `shot_dir=0` (unblockable). The bot emits
no dodge/shield buttons yet (its pool stays full) — the seam stays clean.

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
  **M9 (done):** severe damage-over-time while stranded (`100/180` HP/tick ≈ death in 3 s) hooks the
  `r["stranded"]` branch; dying stranded is a territory kill for the enemy. F2 debug = collapse Team-1
  territory to spawn (force a strand for playtesting).
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
  keys**: pre-M9 these awarded Team 1/2 a point directly; **M9 (done)** replaced them — kills now call
  `MatchState.add_point(team)` via each actor's `died` signal, and **F4/F5 now deal debug damage** to
  force a kill. **F6** restarts the match. Minimal on-screen Label is a placeholder until the real HUD
  (M15).
- **Weapons & firing (M8):** two weapons, switched with **1 / 2** (`weapon_1`/`weapon_2` actions).
  **Revolver** (hitscan, single-shot): 26 dmg, 1.5× headshot, fire every 30 ticks, mag 6, reload 96
  ticks, hip-cone 3°, falloff 100%≤10 m→40% at ≥30 m. **Bolt** (straight-line projectile, no gravity,
  45 m/s, radius 0.25, life 180 ticks): 45 dmg, 1.5× headshot, fire every 48 ticks, mag 4, reload 132
  ticks, hip-cone 2°, falloff 100%≤15 m→50% at ≥35 m. ADS = **no spread** (keys off the `BTN_ADS`
  command bit, frame-exact). Damage is calibrated to an **assumed 100 HP** (real base HP + final TTK
  tuning are M9). Headshot = top 0.45 m of the capsule. **Magazine + reload** (`R`; empty trigger
  auto-reloads; can't fire mid-reload; switching cancels a reload but keeps the fire-rate cooldown).
  **No HP yet** — hits are computed (falloff + headshot) and **logged** (`[COMBAT] …`) + shown on the
  HUD, with placeholder tracers (yellow line), in-flight projectile spheres, and red hit-markers; a
  **missed projectile despawns after its life (180 ticks)** — verified, never persists. **No recoil**
  yet → **M8.5**. **Third-person aim = two-trace** (fixes muzzle-vs-camera parallax): trace #1 from the
  rig **pivot** along `look_forward` finds what the crosshair covers (enemy capsule via `ray_capsule`,
  else a far point); trace #2 fires from the eye-muzzle toward that point (`Ballistics.aim_direction`),
  so shots converge on the crosshair. Starting trace #1 at the pivot is also the "closest-point-to-
  player" guard (no shooting backward through yourself); a small `TRACE_BACK` handles a muzzle already
  overlapping the target. Controls added: **LMB** fire, **R** reload, **1/2** weapon select (controller
  binds deferred to the controller pass).
- **Health / death / respawn (M9):** **base HP 100** (`Health.MAX_HP`; M8 damage was already calibrated
  to it). A hit subtracts HP; 0 HP = death → killer's team scores via `MatchState.add_point`. **Respawn
  delay 180 ticks (3 s)** at your own un-loseable spawn; **respawn invulnerability 300 ticks (5 s),
  broken the moment you fire** (`on_fire`). **Stranded DoT** = `100/180` HP/tick (a full bar in 180
  ticks ≈ 3 s) while standing on a tile that flipped under you; dying that way is a **territory kill**
  crediting the enemy. No passive regen (energy/regen is M10; HP bars over heads are M11). Death/respawn
  timers advance only during the ACTIVE phase (they pause through countdown/round-over freezes, which
  fully reset HP). Debug keys repurposed: **F4** damages the bot, **F5** damages the player (force a
  kill without aiming); **F6** still restarts. Placeholder visuals: dead = capsule hidden, invuln =
  translucent tint.
- **Energy / dodge / shield (M10, refined in M10.1):** one **200** pool (`Energy.MAX`). **Regen 40/s**,
  with a **per-action regen delay** (M10.1): sprint **0** (regen resumes the tick you stop), dodge/shield
  **1 s**; delays compose as a **single-int max** (`_regen_pause = maxi(remaining, action_delay)`) =
  parallel timers blocked until the latest expiry, so a shorter delay never overwrites a longer one and
  spamming isn't cumulative (a `_spent_this_tick` flag also stops same-tick regen so sprint can't
  out-regen its drain). **Sprint** drains **15/s**. **Dodge** (key **X**) costs **40**, **no i-frames**,
  a locked burst (`DODGE_SPEED 17.5 m/s × 18 ticks`, M10.1: +25%), **uncancellable** (only look + ADS
  mid-roll), usable in air, **cancels a raised shield**. **Shield** (key **F, toggle**) costs **20 to
  deploy**, **20/s** passive, **+2× the damage it blocks**; **not planted** (walk/crouch/jump OK, no
  sprint/fire/reload). **M10.1:** the shield is a **flat quad tracking the full aim (yaw + pitch)**,
  `top_level` + code-driven, pushed `SHIELD_DIST=1.5 m` out (clears the capsule up/down; ±80° pitch cap);
  it blocks **only shots whose path actually crosses the visible quad** (`Shield.blocks` = ray-vs-quad,
  `HALF_W/H` match the mesh) — NOT an infinite cone. **Out of energy → STUN 2 s** (visual flash; no
  fire/reload/energy, can still walk/jump/crouch) **→ RECOVERY ~4 s** (refills 50/s, energy actions
  locked until full, fire/reload return). HUD: energy line + STUN/RECOVER/SHIELD tags. Shield extends the
  M9 damage seam via `take_damage(amount, team, shot_dir, hit_point)`; stranded/debug damage is
  unblockable (`shot_dir=0`).

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
- **M8** Weapons & firing: revolver (hitscan) + bolt (projectile), seeded hip-fire spread, ADS = no
  spread, falloff, headshots, magazine + reload, weapon switch (1/2), tracers/markers. Pure sim
  (`weapon_defs`/`weapon_loadout`/`ballistics`) + `CombatDirector` node, phase-gated. Two-trace aim
  convergence fixes third-person muzzle-vs-camera parallax. Signed off.
- **M8.5** Recoil pass: pure `sim/recoil.gd` aim-punch + AOP auto-recovery through the look channel,
  per-weapon numbers in `weapon_defs.gd`, SMG full-auto test weapon (key 3), `$Muzzle` marker, crouch
  camera-drop. Signed off.

- **M9** Health / death / respawn + kills→score. Pure `sim/health.gd` (HP/invuln/respawn, integer-tick)
  applied through `player.gd`; combat applies damage to victim HP; a lethal hit emits `died(killer_team)`
  → `MatchDirector` → `MatchState.add_point` (replacing the F4/F5 debug points, now debug-damage). Base
  HP 100, respawn 3 s, spawn invuln 5 s broken by firing; stranded DoT (`100/180` HP/tick) credits the
  enemy. Signed off.

**Feature layers (each opens with its own tuning questions):**
- **M10 + M10.1 (signed off)** Energy + dodge roll + directional shield. Pure
  `sim/energy.gd` (200 pool, regen 40/s w/ per-action delay, 2-phase stun→recovery), `sim/dodge.gd`
  (uncancellable burst, no i-frames, 17.5 m/s), `sim/shield.gd` (ray-vs-quad block) applied through
  `player.gd`; the shield extends the M9 damage seam (`take_damage(amount, team, shot_dir, hit_point)`),
  absorbing into energy (2× the damage). Toggle-F shield (not planted, tracks full aim yaw+pitch via a
  `top_level` quad pushed out, blocks only what crosses the visible plane), X dodge, energy-gated sprint,
  stun visual + opponent-visible shield plane, energy HUD line. **M10.1:** per-action regen delays (sprint
  0, dodge/shield 1 s) composed as a single-int `max` (parallel, scales to e.g. a 5 s build delay).
  *Verified: test_m10 24/24 + test_m8_integration 12/12 twice byte-identical; m8_combat boots clean;
  M7 regression 11/11. Playtest signed off.*
- **M11 (NEXT)** Detection (20 m, 50 m/1 s on fire, team-shared, 3 s linger, outlines + HP bars, indicator).
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
