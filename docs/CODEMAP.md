# CODEMAP — symbol reference

Read this before editing `sim/`/`scripts/` to find the right function/constant without opening every
file. **Names & signatures only — no numeric values** (code is the source of truth; read the file for
exact numbers). All durations are integer ticks @ 60 Hz. Pure sims `extend RefCounted` (preload, no
`class_name`); nodes are noted. Keep this in sync when you add/rename/remove a public symbol.

Full architecture/seam prose: `CLAUDE.md`. Design intent: `docs/GDD.md`. Status: `docs/ROADMAP.md`.

---

## services/  (autoloads)

### `services/rng.gd` — seeded RNG service, autoload `Rng` (Node)
Named independent streams from one master seed; the ONLY randomness source (no global `randf`).
- vars: `_master_seed`, `_streams`
- `set_seed(p_seed)` · `get_master_seed() -> int` · `new_match_seed(override_seed := -1) -> int`
- `stream(stream_name: String) -> RandomNumberGenerator` — e.g. `"weapon_spread"`, `"weapon_recoil"`

## input/

### `input/input_command.gd` — one tick of intent (RefCounted)
- button consts: `BTN_JUMP BTN_SPRINT BTN_CROUCH BTN_ADS BTN_FIRE BTN_RELOAD BTN_WEAPON1 BTN_WEAPON2 BTN_WEAPON3 BTN_DODGE BTN_SHIELD`
- vars: `tick`, `move_dir: Vector2` (x=strafe, y=forward), `look: Vector2` (yaw/pitch rad), `buttons: int`
- `_init(p_tick, p_move, p_look, p_buttons)`

### `input/input_provider.gd` — base provider (RefCounted)
- `poll(tick) -> InputCommand` (override)

### `input/scripted_input_provider.gd` — fixed list, tests/replay (extends input_provider)
- `_init(commands: Array)` · `poll(tick)` · static `from_seeded(count, stream_name) -> Array`

### `input/local_input_provider.gd` — the ONLY place raw `Input` is read (extends input_provider)
- consts: `MOUSE_SENS STICK_RATE ADS_SENS_MULT`
- `add_mouse_motion(rel: Vector2)` · `poll(tick)`
- static `resolve_exclusive(sprint_held, sprint_pressed, ads_in) -> Dictionary{sprint,ads}`
- static `look_delta(mouse_px, stick, dt, ads) -> Vector2`

### `input/bot_input_provider.gd` — trivial constant-move bot (extends input_provider)
- `_init(move_dir := Vector2(0,1))` · `poll(tick)`

### `input/default_binds.gd` — runtime InputMap defaults (RefCounted)
- static `ensure_default_actions()` (idempotent; actions: move_*/jump/sprint/crouch/look_*/ads_toggle/ads_hold/fire/reload/weapon_1..3/dodge/shield/debug_* F1–F6)

## sim/  (pure, headlessly tested)

### `sim/world.gd` — M0 demo sim core
- vars: `tick`, `_accum`, `_pos_x`
- `reset()` · `step(cmd)` · `get_recording() -> Array` · `state_hash() -> int`

### `sim/tile_topology.gd` — shape-agnostic tile interface (base)
- `tile_count() -> int` · `all_tiles() -> Array` · `in_bounds(coord) -> bool`
- `world_to_tile(pos) -> Vector2i` · `tile_to_world_center(coord) -> Vector3`
- `cell_polygon(coord) -> PackedVector3Array` · `edge_neighbors(coord) -> Array` · `world_aabb() -> AABB`

### `sim/square_topology.gd` — 9×20 @5 m, origin-centered (extends tile_topology)
- vars: `cols`, `rows`, `size`
- `_init(cols := 9, rows := 20, size := 5.0)` + overrides all topology methods

### `sim/tile_grid.gd` — tile ownership state (RefCounted)
- `enum { NEUTRAL, TEAM1, TEAM2 }` · vars: `topology`, `spawn`
- `get_owner(coord) -> int` · `is_unloseable(coord) -> bool` · `set_owner(coord, team) -> bool`
- `snapshot() -> Dictionary` · `restore(snap)` · `owners_hash() -> int` · `outline_category(coord) -> int`

### `sim/capture.gd` — integer-tick capture/neutralize/contest/comeback (RefCounted)
- consts: `COMEBACK_THRESHOLD CAPTURE_TICKS COMEBACK_TICKS NEUTRALIZE_TICKS PHASE_NONE PHASE_CAPTURE PHASE_NEUTRALIZE`
- `_init(grid)` · `progress_team(coord) -> int` · `progress_phase(coord) -> int` · `progress_fraction(coord) -> float`
- `active_tiles() -> Array` · `step(presence: Dictionary, _dt) -> bool` (presence = {TEAM: Vector2i|null}) · `reset()`

### `sim/movement_restriction.gd` — M5 walkable clamp (RefCounted, all static)
- consts: `EPS PROBE BIG`
- static `walkable_cells(grid, team) -> Dictionary` (owned ∪ edge-neighbors)
- static `is_walkable(walkable, coord) -> bool`
- static `clamp_move(from, to, walkable, topology, margin) -> Dictionary{pos, hit_x, hit_z, stranded}`

### `sim/match_state.gd` — round/match phase machine (RefCounted)
- consts: `TEAM1 TEAM2 PHASE_COUNTDOWN PHASE_ACTIVE PHASE_ROUND_OVER PHASE_MATCH_OVER POINTS_TO_WIN_ROUND ROUNDS_TO_WIN_MATCH COUNTDOWN_TICKS ROUND_OVER_TICKS`
- vars: `phase`, `round_index`, `round_wins`, `points`
- `restart()` · `is_active() -> bool` · `round_winner() -> int` · `match_winner() -> int` · `time_left_ticks() -> int`
- `tick() -> String` (returns `"round_reset"` one-shot) · `add_point(team) -> bool` (true if it won the round)

### `sim/team_colors.gd` — customizable palette (RefCounted)
- static vars: `fill`, `outline` (index 0=neutral,1=T1,2=T2)
- static `fill_color(owner) -> Color` · static `outline_color(category) -> Color` (3 = blend)

### `sim/weapon_defs.gd` — weapon stat table + combat consts, DATA (RefCounted)
- consts: `HITSCAN PROJECTILE` · ids `REVOLVER BOLT SMG` · `EYE_HEIGHT HEAD_BAND ASSUMED_HP`
- spread states: `SPREAD_STAND SPREAD_WALK SPREAD_AIR SPREAD_CROUCH SPREAD_CROUCH_WALK SPREAD_SPRINT` (0..5)
- `WEAPONS` array; per-weapon keys: `name kind damage headshot_mult fire_ticks mag reload_ticks auto
  fire_while_sprint spread_hip[6] spread_ads[6] falloff_full_m falloff_min_m falloff_min_factor
  proj_speed proj_radius proj_life_ticks recoil_pitch_deg recoil_yaw_deg recoil_recovery_deg`
- static `get_def(weapon_id) -> Dictionary` · static `spread_cone(weapon, ads, state) -> float` (deg; 0 = none)

### `sim/weapon_loadout.gd` — per-actor fire/ammo/reload/switch SM (RefCounted)
- const `FIRE_QUEUE_TICKS` (semi-auto input queue) · var `current`
- `reset()` · `ammo() -> int` · `reloading() -> bool`
- `step(fire_held, reload_pressed, switch_to) -> Dictionary{fired, weapon, ammo, reloading}` (auto vs semi internal)

### `sim/ballistics.gd` — shot math (RefCounted, all static)
- `sample_spread(forward, half_angle, rng) -> Vector3` (≤0 = forward)
- `damage_at(weapon, dist) -> float` · `resolve_damage(weapon, dist, headshot) -> float`
- `is_headshot(hit_y, foot_y, height) -> bool`
- `aim_direction(muzzle, cam_origin, cam_dir, target, far_dist) -> Vector3` (two-trace convergence)
- `ray_capsule(origin, dir, cap_pos, radius, height) -> Dictionary{hit, point, hit_y, dist}`
- `step_projectile(pos, vel) -> Vector3` · `projectile_hits(center, proj_radius, cap_pos, radius, height) -> bool`

### `sim/recoil.gd` — M8.5 aim-punch + AOP recovery (RefCounted)
- consts: `RECOVERY_DELAY_TICKS STATE_IDLE STATE_FIRING STATE_RECOVERY_DELAY STATE_RECOVERING`
- `reset()` · static `apply_look(yaw, pitch, look, pitch_limit) -> Dictionary{yaw, pitch, delta}`
- `update(player_delta, fired, def, weapon_id, rng, cur_yaw, cur_pitch, pitch_limit) -> Dictionary{yaw, pitch}`
- `state_id() -> int` · `state_name() -> String` · `displacement() -> Vector2` · `shot_index() -> int`

### `sim/health.gd` — HP/death/respawn/invuln (RefCounted)
- consts: `MAX_HP RESPAWN_TICKS INVULN_TICKS STRANDED_DOT_PER_TICK` · vars: `hp`, `alive`
- `reset()` · `is_dead() -> bool` · `is_invulnerable() -> bool` · `hp_int() -> int`
- `take_damage(amount) -> bool` (true iff this call killed) · `on_fire()` · `tick() -> String` (`"respawn"`)
- `respawn()` · `invuln_ticks() -> int` · `respawn_ticks() -> int`

### `sim/energy.gd` — 200 pool + 2-phase stun→recovery (RefCounted)
- consts: `MAX REGEN_PER_TICK REGEN_PAUSE_TICKS SPRINT_REGEN_DELAY RECOVER_PER_TICK SPRINT_DRAIN_PER_TICK
  DODGE_COST SHIELD_DEPLOY_COST SHIELD_DRAIN_PER_TICK SHIELD_BLOCK_MULT STUN_TICKS STATE_NORMAL STATE_STUNNED STATE_RECOVERING`
- var `energy`
- `reset()` · `is_stunned() -> bool` · `is_recovering() -> bool` · `can_use_energy() -> bool` · `energy_int() -> int`
- `try_spend(cost, regen_delay := REGEN_PAUSE_TICKS) -> bool` · `drain(per_tick, regen_delay := …) -> bool`
- `absorb(damage) -> float` (leaked remainder) · `tick()`
- `state_id() -> int` · `stun_ticks_left() -> int` · `regen_pause_ticks() -> int`

### `sim/dodge.gd` — dodge burst + post-roll lock (RefCounted)
- consts: `DODGE_TICKS LOCK_TICKS DODGE_SPEED` (one `_ticks_left` spans burst+lock)
- `reset()` · `active() -> bool` (burst OR lock) · `try_start(dir) -> bool` · `velocity() -> Vector3` (burst only)
- `tick()` · `ticks_left() -> int`

### `sim/shield.gd` — directional block, ray-vs-quad (RefCounted, static)
- consts: `SHIELD_DIST HALF_W HALF_H` (MUST match `$ShieldVisual` mesh in player.gd/player.tscn)
- static `blocks(eye, aim, hit_point, shot_dir) -> bool`

### `sim/detection.gd` — per-actor detectability, WoWS bloom+linger (RefCounted)
- consts: `BASE_RANGE FIRE_RANGE BLOOM_TICKS LINGER_TICKS` · var `detected: bool`
- `reset()` · `on_fire()` (blooms own range) · `effective_range() -> float`
- `step(min_enemy_dist)` (one active tick) · `bloom_ticks() -> int` · `linger_ticks() -> int`

### `sim/player_motion.gd` — movement model (RefCounted)
- consts: `WALK_SPEED SPRINT_MULT CROUCH_MULT ADS_MULT GRAVITY JUMP_APEX GROUND_ACCEL GROUND_DECEL AIR_ACCEL`
- vars: `velocity`, `crouching`
- `reset()` · `tick(cmd, dt, on_floor, yaw := 0.0)` (caller integrates position) · `_target_speed(buttons) -> float`

## scripts/  (nodes; apply the sims)

### `scripts/bootstrap.gd` — M0 entry (Control)
- `_ready()` (logs match seed)

### `scripts/player.gd` — the actor (CharacterBody3D)
Provider→PlayerMotion→camera rig; holds all per-actor sims. `is_local` gates mouse/camera only; firing
& sims run for bots too (netcode-clean).
- signal `died(killer_team)`
- exports: `start_yaw`, `is_local`, `body_color`
- consts: `STAND_HEIGHT CROUCH_HEIGHT PITCH_LIMIT HIP_DIST HIP_HEIGHT HIP_SHOULDER ADS_DIST ADS_HEIGHT
  ADS_SHOULDER ADS_ZOOM ADS_BLEND_SPEED CAM_MIN_Y CROUCH_CAM_DROP CROUCH_T_TICKS BODY_MARGIN`
- world/round: `bind_world(grid, team)` · `reset_to_spawn(pos, yaw)`
- combat in: `take_damage(amount, attacker_team, shot_dir := ZERO, hit_point := ZERO)`
- combat out / queries: `consume_shots() -> Array` · `hitbox() -> Dictionary{pos,radius,height}` · `team_id() -> int`
- sim accessors: `health()` · `energy()` · `shield_up() -> bool` · `detection()` · `loadout()` · `recoil()`
- M11.5/detection: `alive() -> bool` · `set_detection_visual(rendered, is_enemy)` · `body_center() -> Vector3`
- `set_base_fov(fov)` (Config stub)
- static helpers: `look_forward(yaw,pitch)` `look_right(yaw)` `camera_position(...)` `camera_position_grounded(...)`
  `clamp_pitch(p)` `rig_params(blend)` `ads_fov_for(base_fov, zoom)`
- key private: `_fire`, `_queue_shot(weapon, ads, state)`, `_spread_state(cmd) -> int`,
  `_fire_suppresses_sprint(cmd) -> bool`, `_advance_crouch(target)`, `_apply_crouch_height(frac)`,
  `_crouch_frac()`, `_dodge_direction(move_dir)`, `_tick_dodge`, `_update_shield`, `_apply_tile_restriction`

### `scripts/tile_grid_view.gd` — grid visuals + drives capture from both actors (Node3D)
- vars: `grid`, `capture` · exports: `player_path bot_path debug_enemy_patch debug_prowned
  debug_prowned_team2 overhead_cam_path player_cam_path`
- `set_capture_active(v)` · `reset_world()` · `set_tile(coord, team)` · `_actor_alive(actor) -> bool`
- input: F1 labels · F2 strand · F3 overhead cam

### `scripts/match_director.gd` — per-tick orchestrator, runs FIRST in tree (Node)
- exports: `view_path player_path bot_path hud_label_path combat_path detection_path`
- drives MatchState; gates actors + `_combat`/`_detection`/view by phase; `_reset_world` on `"round_reset"`;
  connects both actors' `died` → `MatchState.add_point`; debug F4/F5 damage, F6 restart; HUD Label.

### `scripts/combat_director.gd` — shot resolver, phase-gated (Node3D)
- exports: `player_path bot_path` · var `last_event` (HUD string)
- `set_active(v)` · `reset()` — drains both actors' `consume_shots()`, converges aim, resolves hitscan +
  steps projectiles via Ballistics, applies `take_damage`, owns tracers/markers.

### `scripts/detection_director.gd` — detection resolver, phase-gated (Node3D)
- exports: `player_path bot_path local_team`
- `set_active(v)` · `reset()` — each active tick feeds every actor its nearest-enemy center-to-center
  distance, steps `detection()`, then renders enemies only when detected (`set_detection_visual`).
