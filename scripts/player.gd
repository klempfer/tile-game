extends CharacterBody3D
## M2 player: third-person over-the-shoulder camera, mouse + stick look, ADS zoom,
## camera-relative movement. One InputCommand per fixed tick; look + ADS travel in
## the command (netcode/replay-friendly). Motion stays in the pure PlayerMotion
## model; the camera orbit + look math are pure static helpers (unit-tested).

const InputCommand = preload("res://input/input_command.gd")
const PlayerMotion = preload("res://sim/player_motion.gd")
const LocalInputProvider = preload("res://input/local_input_provider.gd")
const BotInputProvider = preload("res://input/bot_input_provider.gd")
const MovementRestriction = preload("res://sim/movement_restriction.gd")
const WeaponLoadout = preload("res://sim/weapon_loadout.gd")
const WeaponDefs = preload("res://sim/weapon_defs.gd")
const Recoil = preload("res://sim/recoil.gd")
const Health = preload("res://sim/health.gd")
const Energy = preload("res://sim/energy.gd")
const Dodge = preload("res://sim/dodge.gd")
const Shield = preload("res://sim/shield.gd")

## M9: emitted once when this actor's HP hits 0. `killer_team` is the shooter's team for a weapon
## kill, or the enemy team for a stranded "territory" death. MatchDirector connects this to scoring.
signal died(killer_team)

const FIXED_DT := 1.0 / 60.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const PITCH_LIMIT := 1.3962634  # deg_to_rad(80)

# Camera rig (hip / ADS) — chosen with the user.
const HIP_DIST := 3.0
const HIP_HEIGHT := 1.6
const HIP_SHOULDER := 0.5
const ADS_DIST := 3.0           # no pull-in; ADS zoom comes from FOV only
const ADS_HEIGHT := 1.6
const ADS_SHOULDER := 0.85      # shift camera right so the character clears the crosshair
const ADS_ZOOM := 1.8           # on-screen magnification, relative to base FOV (FOV-slider-safe)
const ADS_BLEND_SPEED := 8.0    # 1/sec; ~0.125s hip <-> ADS transition
const CAM_MIN_Y := 0.4          # camera never dips below this height (flat ground at y=0)
# Crouch camera: lower the viewpoint to the crouched stance. Camera-drop only — the reticle then
# points lower in the world via parallax and recoil/AOP stay untouched (crouch = translation, AOP =
# angle; orthogonal). Both knobs are independently tunable.
const CROUCH_CAM_DROP := 0.6    # how far the camera lowers when fully crouched (= STAND-CROUCH height)
const CROUCH_BLEND_SPEED := 8.0 # 1/sec; ~0.125s stand <-> crouch camera ease (matches ADS)

# M5 movement restriction: inset the body from disallowed tile edges. = capsule
# radius so the whole capsule stays on legal tiles. Single knob for footprint feel —
# set 0.0 for center-point (position-only) restriction.
const BODY_MARGIN := 0.4

@export var start_yaw := 0.0     # initial facing (radians); set per scene
# M6: false = AI/bot actor — driven by BotInputProvider, no mouse capture, camera not
# current. Defaults true so existing m1/m2/m4/m5 scenes stay the local player unchanged.
@export var is_local := true
@export var body_color := Color(0.2, 0.5, 1, 1)  # capsule tint (bot scene sets red)

var _motion = PlayerMotion.new()
var _provider = null              # set in _ready: Local (KB+M) or Bot, per is_local
var _tick := 0
var _yaw := 0.0
var _pitch := 0.0
var _ads_blend := 0.0
var _crouch_blend := 0.0        # 0 = standing, 1 = crouched; eases the camera down (visual, like ADS)
var _base_fov := 75.0           # hip FOV; later driven by the Config FOV slider
var _grid = null                # bound TileGrid sim (M5); null in scenes without a grid
var _team := 0                  # which team's walkable region restricts this player
var active := true              # M7: false = frozen (countdown / round-over / match-over)
var _loadout = WeaponLoadout.new()   # M8: per-actor fire/ammo/reload/switch state
var _pending_shots: Array = []       # M8: shots fired this tick, drained by the combat director
var _recoil = Recoil.new()           # M8.5: aim-punch + AOP recovery, through the look channel
var _health = Health.new()           # M9: HP / death / respawn-timer / invulnerability
var _spawn_pos := Vector3.ZERO       # M9: cached spawn pose so the actor can self-respawn mid-round
var _spawn_yaw := 0.0
var _body_mat: StandardMaterial3D    # M9: kept so the death/invuln visual can re-tint the capsule
var _energy = Energy.new()           # M10: energy pool / stun / recovery
var _dodge = Dodge.new()             # M10: dodge-roll kinematic burst
var _shield_up := false              # M10: directional shield raised (toggled with F)

@onready var _col: CollisionShape3D = $Collision
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _camera: Camera3D = $Camera3D
# M8.5: bullet-origin marker. A real node (not a computed point) so that once character + weapon
# models exist it can be parented under the weapon — its global_position then tracks the actual muzzle
# through any animation for free. For the placeholder capsule its height follows the crouch (see
# _apply_crouch). get_node_or_null keeps older scenes safe; _muzzle_origin() falls back to a computed
# eye point if absent.
@onready var _muzzle: Marker3D = get_node_or_null("Muzzle")
# M10: translucent flat barrier shown in front of the actor while the shield is up. A world mesh (not
# is_local-gated) so the opponent sees it too; parented under the body so it inherits the body yaw
# (= the shield's facing). get_node_or_null keeps older scenes safe (it simply stays absent there).
@onready var _shield_visual: MeshInstance3D = get_node_or_null("ShieldVisual")

func _ready() -> void:
	if is_local:
		_provider = LocalInputProvider.new()
	else:
		_provider = BotInputProvider.new()
	_apply_body_color()
	_setup_shield_visual()
	_yaw = start_yaw
	rotation.y = _yaw
	# M9: remember the scene-placed spawn pose so a mid-round death can respawn here even before the
	# first round_reset (MatchDirector records the same poses but only calls reset_to_spawn on resets).
	_spawn_pos = global_position
	_spawn_yaw = start_yaw
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_camera.current = true   # explicit: win the active-camera race vs. the bot's
		print("[Player] spawned at %v, active camera: %s" % [global_position, _camera.name])
		_update_camera(false, 0.0)
	else:
		_camera.current = false  # avoid two cameras both current=true
		print("[Bot] spawned at %v" % global_position)

func _apply_body_color() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = body_color
	_mesh.material_override = _body_mat

## M10: tint the shield barrier plane to the team color (translucent, double-sided, unshaded) and hide
## it until raised. M10.1: `top_level` so it is NOT glued to the body transform — `_update_shield_visual`
## drives its world pose from the full aim (yaw + pitch) each tick. A world mesh, so the opponent sees it.
func _setup_shield_visual() -> void:
	if _shield_visual == null:
		return
	_shield_visual.top_level = true
	var sm := StandardMaterial3D.new()
	var sc := body_color
	sc.a = 0.3
	sm.albedo_color = sc
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_visual.material_override = sm
	_shield_visual.visible = false

## M10.1: place the shield quad in front of the eye along the FULL aim (yaw + pitch), perpendicular to
## it, SHIELD_DIST out (pushed out so it clears the capsule when looking up/down). Centralised constants
## (Shield.SHIELD_DIST) keep the visible plane identical to the block test. Only runs while raised.
func _update_shield_visual() -> void:
	if _shield_visual == null or not _shield_up:
		return
	var eye := global_position + Vector3(0.0, _eye_height(), 0.0)
	var aim := look_forward(_yaw, _pitch)
	var center := eye + aim * Shield.SHIELD_DIST
	_shield_visual.global_position = center
	_shield_visual.look_at(center + aim, Vector3.UP)  # quad perpendicular to the aim (pitch-safe ≤80°)

func _input(event: InputEvent) -> void:
	if not is_local:
		return  # bot has no mouse / BotInputProvider has no add_mouse_motion
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_provider.add_mouse_motion((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed("ui_cancel"):
		# Free / recapture the mouse for testing.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
	var cmd = _provider.poll(_tick)  # poll even when frozen (drains the mouse accumulator)

	if not active:
		# M7 freeze (countdown / round-over / match-over): hold still on the floor. Death/invuln
		# timers deliberately do NOT advance here — they only count during ACTIVE play.
		velocity = Vector3.ZERO
		move_and_slide()
		_tick += 1
		return

	if _health.is_dead():
		# M9: dead but in an ACTIVE round — hold still and count down to respawn (the rest of the
		# living tick is skipped: no look / motion / firing / capture presence while dead).
		velocity = Vector3.ZERO
		move_and_slide()
		if _health.tick() == "respawn":
			_respawn()
		_tick += 1
		return

	# Look (radians this tick) -> yaw/pitch. Body faces yaw (strafe-style). M8.5: the wrap/clamp lives
	# in Recoil.apply_look so recoil tracks the ACTUAL (post-clamp) reticle movement, not raw input
	# (matters at the pitch limit / aiming at the ground); it returns the actual delta for AOP tracking.
	# Look is ALWAYS allowed — even mid-dodge or while shielding.
	var look_res := Recoil.apply_look(_yaw, _pitch, cmd.look, PITCH_LIMIT)
	_yaw = look_res["yaw"]
	_pitch = look_res["pitch"]
	rotation.y = _yaw

	var can_act: bool = _energy.can_use_energy()  # M10: energy actions only in NORMAL

	# M10 dodge: trigger first; once rolling, the roll is uncancellable (only look + ADS honored).
	if not _dodge.active() and (cmd.buttons & InputCommand.BTN_DODGE) != 0 and can_act:
		if _energy.try_spend(Energy.DODGE_COST):
			_dodge.try_start(_dodge_direction(cmd.move_dir))
			_set_shield(false)  # a dodge cancels the shield
	if _dodge.active():
		_tick_dodge(cmd, look_res["delta"])
		return

	# M10 shield (toggle): raise/lower on the press edge; passive drain; drop if it bottoms out.
	_update_shield(cmd, can_act)

	# M10: feed motion/fire a gated command — strip sprint when unpayable / shielding, and strip
	# fire+reload while shielding or stunned. (Walk/jump/crouch always pass; weapon-switch too.)
	var stripped: int = cmd.buttons
	var sprint_ok: bool = (cmd.buttons & InputCommand.BTN_SPRINT) != 0 and can_act and not _shield_up
	if sprint_ok and not _energy.drain(Energy.SPRINT_DRAIN_PER_TICK, Energy.SPRINT_REGEN_DELAY):
		sprint_ok = false  # bottomed out this tick -> stun; sprint ends
	if not sprint_ok:
		stripped &= ~InputCommand.BTN_SPRINT
	if _shield_up or _energy.is_stunned():
		stripped &= ~(InputCommand.BTN_FIRE | InputCommand.BTN_RELOAD)
	var mcmd = cmd
	if stripped != cmd.buttons:
		mcmd = InputCommand.new(cmd.tick, cmd.move_dir, cmd.look, stripped)

	_motion.tick(mcmd, FIXED_DT, is_on_floor(), _yaw)
	velocity = _motion.velocity
	var from_pos := global_position
	move_and_slide()
	_apply_tile_restriction(from_pos)  # M9: stranded standing on a flipped tile applies DoT here
	if _health.is_dead():
		# Stranded DoT just killed us this tick: stop here (don't fire/crouch); the dead branch
		# takes over next tick. The death signal was already emitted in _apply_tile_restriction.
		_tick += 1
		return
	_apply_crouch(_motion.crouching)
	_fire(mcmd, look_res["delta"])  # M8/M8.5: fire decision -> shot (pre-impulse) -> recoil via look channel
	_health.tick()                  # M9: count down spawn invulnerability (alive path)
	_energy.tick()                  # M10: regen / stun / recovery countdown
	_refresh_combat_visual()        # M9/M10: capsule fade (invuln) / stun tint + shield plane
	_update_shield_visual()         # M10.1: drive the shield plane from the post-recoil aim (yaw+pitch)

	if is_local:
		var ads: bool = (cmd.buttons & InputCommand.BTN_ADS) != 0
		_update_camera(ads, FIXED_DT)
	_tick += 1

## M10: world-space dodge direction from camera-relative move input; straight backward (toward the
## camera) when there is no directional input, so a no-input dodge is a back-hop.
func _dodge_direction(move_dir: Vector2) -> Vector3:
	var dir := Vector3(move_dir.x, 0.0, -move_dir.y)
	if dir.length() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)  # local backward
	return dir.rotated(Vector3.UP, _yaw)

## M10: set the shield raised/lowered and keep the placeholder barrier mesh in sync.
func _set_shield(up: bool) -> void:
	_shield_up = up
	if _shield_visual != null:
		_shield_visual.visible = up

## M10: F is a toggle — press raises (pays the deploy cost, NORMAL only) or lowers (free). While up the
## shield drains passively; if that bottoms out the pool it drops (and the drain triggered the stun).
func _update_shield(cmd, can_act: bool) -> void:
	if (cmd.buttons & InputCommand.BTN_SHIELD) != 0:
		if _shield_up:
			_set_shield(false)
		elif can_act and _energy.try_spend(Energy.SHIELD_DEPLOY_COST):
			_set_shield(true)
	if _shield_up and not _energy.drain(Energy.SHIELD_DRAIN_PER_TICK):
		_set_shield(false)

## M10: one tick of an in-progress dodge roll. Uncancellable — only look (already applied) + ADS are
## honored. Motion runs on a neutral command (gravity/floor) with horizontal velocity overridden by the
## dodge burst; the loadout/recoil tick with no fire/reload/switch (recovery only).
func _tick_dodge(cmd, look_delta: Vector2) -> void:
	var ncmd = InputCommand.new(_tick, Vector2.ZERO, Vector2.ZERO, 0)
	_motion.tick(ncmd, FIXED_DT, is_on_floor(), _yaw)
	velocity = _motion.velocity
	var dv := _dodge.velocity()
	velocity.x = dv.x
	velocity.z = dv.z
	var from_pos := global_position
	move_and_slide()
	_apply_tile_restriction(from_pos)
	if _health.is_dead():
		_tick += 1
		return
	_apply_crouch(false)
	_fire(ncmd, look_delta)
	_dodge.tick()
	_health.tick()
	_energy.tick()
	_refresh_combat_visual()
	if is_local:
		var ads: bool = (cmd.buttons & InputCommand.BTN_ADS) != 0
		_update_camera(ads, FIXED_DT)
	_tick += 1

## Bind the tile world so movement is restricted to `team`'s walkable region (M5).
## Called by the tile grid view; scenes without a grid never bind, so the clamp stays
## off there (m1/m2 movement/camera scenes are unaffected). The player holds the pure
## TileGrid sim object, not the view node — keeps the input->sim seam clean.
func bind_world(grid, team: int) -> void:
	_grid = grid
	_team = team

## Reset the actor to a spawn pose for a new round (M7). Clears motion/camera/crouch so
## the round starts byte-identically to match start. The bound grid ref is unchanged.
func reset_to_spawn(pos: Vector3, yaw: float) -> void:
	_spawn_pos = pos       # M9: keep the spawn pose current for mid-round self-respawn
	_spawn_yaw = yaw
	global_position = pos
	_yaw = yaw
	_pitch = 0.0
	rotation.y = _yaw
	velocity = Vector3.ZERO
	_motion.reset()
	_ads_blend = 0.0
	_crouch_blend = 0.0
	_tick = 0
	_loadout.reset()       # M8: fresh weapon / full mags each round
	_pending_shots.clear()
	_recoil.reset()        # M8.5: clear AOP / recovery state for the new round
	_health.reset()        # M9: full HP, alive, NO invuln (a fresh round, not a respawn)
	_energy.reset()        # M10: full pool, NORMAL
	_dodge.reset()         # M10: clear any in-progress roll
	_set_shield(false)     # M10: shield down
	_apply_crouch(false)
	_refresh_combat_visual()
	if is_local:
		_update_camera(false, 0.0)

## M9/M10: take incoming damage from the combat resolver (or any source). `shot_dir` is the shot's
## travel direction and `hit_point` where it struck the body (M10.1) — a raised shield blocks only if
## the shot's path actually crosses the visible shield quad (`Shield.blocks`, ray-vs-quad), absorbing the
## hit into energy (2× the damage) and leaking only the unaffordable remainder to HP. `shot_dir = 0`
## (stranded DoT / debug) is unblockable. On a lethal result, react node-side once (hide the capsule +
## emit `died`). Not gated by is_local — a bot dies the same way, keeping the netcode/replay seam clean.
func take_damage(amount: float, attacker_team: int, shot_dir: Vector3 = Vector3.ZERO, hit_point: Vector3 = Vector3.ZERO) -> void:
	var dmg := amount
	if _shield_up and shot_dir != Vector3.ZERO:
		var eye := global_position + Vector3(0.0, _eye_height(), 0.0)
		if Shield.blocks(eye, look_forward(_yaw, _pitch), hit_point, shot_dir):
			dmg = _energy.absorb(amount)  # leaked (unblockable) remainder continues to HP
	if dmg <= 0.0:
		return
	if _health.take_damage(dmg):
		_die(attacker_team)

## M9: this actor just dropped to 0 HP. Health is already flagged dead; do the node-side reaction.
func _die(killer_team: int) -> void:
	velocity = Vector3.ZERO
	_refresh_combat_visual()       # hide the capsule
	died.emit(killer_team)

## M9: come back at the cached spawn with full HP + firing-broken invulnerability (mid-round respawn).
## reset_to_spawn already restored HP/loadout/recoil/pose; layer the spawn invuln on top.
func _respawn() -> void:
	reset_to_spawn(_spawn_pos, _spawn_yaw)
	_health.respawn()
	_refresh_combat_visual()

## M9: the team this actor fights against (1<->2) — the "killer" credited for a stranded territory death.
func _enemy_team() -> int:
	return 2 if _team == 1 else 1

## M9/M10: placeholder combat visual — dead actors vanish; stunned actors flash yellow; invulnerable
## actors fade translucent; otherwise the solid team tint. Also syncs the shield barrier mesh to the
## raised state. Pure cosmetics (never printed/simulated), so it can't affect determinism.
func _refresh_combat_visual() -> void:
	if _shield_visual != null:
		_shield_visual.visible = _shield_up
	if _body_mat == null:
		return
	if _health.is_dead():
		_mesh.visible = false
		return
	_mesh.visible = true
	if _energy.is_stunned():
		_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_body_mat.albedo_color = Color(1.0, 0.85, 0.2)  # M10 stun indicator (placeholder)
		return
	var inv := _health.is_invulnerable()
	_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if inv else BaseMaterial3D.TRANSPARENCY_DISABLED
	var c := body_color
	c.a = 0.35 if inv else 1.0
	_body_mat.albedo_color = c

## M9: the live health state (for the HUD readout: HP / dead / invuln).
func health():
	return _health

## M10: the live energy state (for the HUD readout: energy / stun / recover / shield).
func energy():
	return _energy

## M10: whether the directional shield is currently raised (HUD readout).
func shield_up() -> bool:
	return _shield_up

## M8: advance the weapon state machine from this tick's command and, if it fired,
## queue a Shot for the combat director to resolve. The muzzle/aim origin is the eye
## (no shoulder parallax — bullets follow the crosshair); spread/ADS resolve centrally.
## Firing is deliberately NOT gated by is_local: a bot is the same actor with a
## different provider (it just emits no fire button yet), keeping the netcode seam clean.
func _fire(cmd, player_delta: Vector2) -> void:
	var fire_held: bool = (cmd.buttons & InputCommand.BTN_FIRE) != 0
	var reload_pressed: bool = (cmd.buttons & InputCommand.BTN_RELOAD) != 0
	var switch_to := -1
	if (cmd.buttons & InputCommand.BTN_WEAPON1) != 0:
		switch_to = WeaponDefs.REVOLVER
	elif (cmd.buttons & InputCommand.BTN_WEAPON2) != 0:
		switch_to = WeaponDefs.BOLT
	elif (cmd.buttons & InputCommand.BTN_WEAPON3) != 0:
		switch_to = WeaponDefs.SMG
	var r: Dictionary = _loadout.step(fire_held, reload_pressed, switch_to)
	# M8.5 first-shot-true: build the shot from the CURRENT (pre-impulse) aim, then apply recoil.
	if r["fired"]:
		_queue_shot(int(r["weapon"]), (cmd.buttons & InputCommand.BTN_ADS) != 0)
		_health.on_fire()  # M9: firing breaks spawn invulnerability
	# M8.5 recoil through the look channel: an impulse on a firing tick, AOP tracking + recovery
	# otherwise. The AOP is credited by ACTUAL post-clamp aim deltas (robust at the pitch limit).
	# Not gated by is_local — a bot would recoil the same way (it just emits no fire/look yet).
	var cur_def := WeaponDefs.get_def(_loadout.current)
	var rc := _recoil.update(player_delta, bool(r["fired"]), cur_def, _loadout.current, Rng.stream("weapon_recoil"), _yaw, _pitch, PITCH_LIMIT)
	_yaw = rc["yaw"]
	_pitch = rc["pitch"]
	rotation.y = _yaw

## M8: queue a Shot for the combat director from the current aim (pre-recoil-impulse, so the first
## shot is true). Two-trace aim: the shot carries the muzzle (eye), the camera/crosshair ray (through
## the rig pivot, along look_forward), and ADS; the combat director converges the muzzle shot onto
## whatever the crosshair covers, killing the third-person muzzle-vs-camera parallax. The pivot uses
## the live ADS-blended rig so it matches what the player sees.
func _queue_shot(weapon: int, ads: bool) -> void:
	var rig := rig_params(_ads_blend)
	# Crouch-lowered pivot height, identical to the rendered camera (see _update_camera) so the
	# crosshair ray (trace #1) starts at the real camera pivot and convergence stays correct.
	var cam_height: float = rig["height"] - _crouch_blend * CROUCH_CAM_DROP
	_pending_shots.append({
		"weapon": weapon,
		"muzzle": _muzzle_origin(),
		"cam_origin": global_position + Vector3(0.0, cam_height, 0.0) + look_right(_yaw) * rig["shoulder"],
		"cam_dir": look_forward(_yaw, _pitch),
		"ads": ads,
		"team": _team,
		"tick": _tick,
	})

## M8: hand the combat director the shots fired this tick (and clear them).
func consume_shots() -> Array:
	var s := _pending_shots
	_pending_shots = []
	return s

## M8: this actor's capsule as an enemy hitbox {pos (feet), radius, height (reflects crouch)}.
func hitbox() -> Dictionary:
	var shape := _col.shape as CapsuleShape3D
	return {"pos": global_position, "radius": shape.radius, "height": shape.height}

## M8: which team this actor fights for (bound via bind_world in M5); 0 if unbound.
func team_id() -> int:
	return _team

## M8: the live weapon loadout (for the HUD readout: current weapon / ammo / reload).
func loadout():
	return _loadout

## M8.5: the live recoil state machine (for the debug HUD readout: state / displacement).
func recoil():
	return _recoil

## Clamp this tick's horizontal move to the team's walkable tiles (M5). No-op until a
## world is bound. The clamp math is pure (MovementRestriction); here we just apply the
## result and kill the into-wall velocity component for a clean hard stop. When
## stranded (current cell illegal after a tile flip) nothing is clamped — free roam — and
## that branch applies the M9 stranded damage-over-time (a "territory" death credits the enemy).
func _apply_tile_restriction(from_pos: Vector3) -> void:
	if _grid == null:
		return
	var walkable := MovementRestriction.walkable_cells(_grid, _team)
	var r := MovementRestriction.clamp_move(from_pos, global_position, walkable, _grid.topology, BODY_MARGIN)
	global_position = r["pos"]
	if r["hit_x"]:
		velocity.x = 0.0
	if r["hit_z"]:
		velocity.z = 0.0
	if r["stranded"]:
		# M9: severe DoT while standing on a tile that flipped out from under us; dying this way is a
		# territory kill for the enemy who captured the ground. (Invuln still protects via take_damage,
		# though you can't strand at your own un-loseable spawn.)
		if _health.take_damage(Health.STRANDED_DOT_PER_TICK):
			_die(_enemy_team())

func _apply_crouch(crouched: bool) -> void:
	var h := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	var shape := _col.shape as CapsuleShape3D
	if shape and not is_equal_approx(shape.height, h):
		shape.height = h
		_col.position.y = h * 0.5
		var m := _mesh.mesh as CapsuleMesh
		if m:
			m.height = h
		_mesh.position.y = h * 0.5
		# Keep the bullet-origin marker pinned to the (now changed) stance height. With a real weapon
		# model the muzzle node would ride the animation instead of this manual update.
		if _muzzle != null:
			_muzzle.position.y = _eye_height()

## Current eye / weapon-muzzle height above the feet, following the crouch — a constant offset below
## the head crown (STAND_HEIGHT-EYE_HEIGHT), so it stays just below the head whether standing or crouched.
func _eye_height() -> float:
	var shape := _col.shape as CapsuleShape3D
	var h: float = shape.height if shape else STAND_HEIGHT
	return h - (STAND_HEIGHT - WeaponDefs.EYE_HEIGHT)

## Bullet origin = the weapon muzzle, read from the $Muzzle marker so it tracks the real muzzle once
## models/animation exist (parent the marker under the weapon then; this script needs no change). The
## placeholder marker's height is kept in sync with the crouch by _apply_crouch. Combat keeps a small
## TRACE_BACK behind this point so a target right up against the muzzle still registers. Falls back to a
## computed eye point if a scene lacks the marker.
func _muzzle_origin() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return global_position + Vector3(0.0, _eye_height(), 0.0)

func _update_camera(ads: bool, dt: float) -> void:
	_ads_blend = move_toward(_ads_blend, 1.0 if ads else 0.0, ADS_BLEND_SPEED * dt)
	_crouch_blend = move_toward(_crouch_blend, 1.0 if _motion.crouching else 0.0, CROUCH_BLEND_SPEED * dt)
	var p := rig_params(_ads_blend)
	# Zoom from FOV only (magnification relative to base FOV); aim direction is
	# unchanged, so the crosshair (screen center) stays centered while ADS shifts
	# the camera laterally right via the larger shoulder offset.
	_camera.fov = lerpf(_base_fov, ads_fov_for(_base_fov, ADS_ZOOM), _ads_blend)
	# Crouch lowers the pivot height (camera-drop only — reticle points lower via parallax; aim angle
	# and recoil AOP are untouched). The shot's cam_origin uses the SAME drop so convergence holds.
	var cam_height: float = p["height"] - _crouch_blend * CROUCH_CAM_DROP
	var cam_pos := camera_position_grounded(global_position, _yaw, _pitch, p["dist"], cam_height, p["shoulder"], CAM_MIN_Y)
	_camera.global_position = cam_pos
	_camera.look_at(cam_pos + look_forward(_yaw, _pitch), Vector3.UP)

# --- pure helpers (deterministic; unit-tested) ---

static func look_forward(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

static func look_right(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

static func camera_position(origin: Vector3, yaw: float, pitch: float, dist: float, height: float, shoulder: float) -> Vector3:
	var pivot := origin + Vector3(0.0, height, 0.0) + look_right(yaw) * shoulder
	return pivot - look_forward(yaw, pitch) * dist

## Like camera_position, but shortens the arm (toward the pivot) so the camera
## never dips below min_y when looking up. A SpringArm-vs-flat-ground for now; real
## collision against walls/terrain arrives with structures (M12). Aim is unchanged.
static func camera_position_grounded(origin: Vector3, yaw: float, pitch: float, dist: float, height: float, shoulder: float, min_y: float) -> Vector3:
	var pivot := origin + Vector3(0.0, height, 0.0) + look_right(yaw) * shoulder
	var fwd := look_forward(yaw, pitch)
	var d := dist
	if fwd.y > 0.0 and pivot.y - fwd.y * d < min_y:
		d = clampf((pivot.y - min_y) / fwd.y, 0.0, dist)
	return pivot - fwd * d

static func clamp_pitch(p: float) -> float:
	return clampf(p, -PITCH_LIMIT, PITCH_LIMIT)

## Blended hip<->ADS rig geometry (dist/height/shoulder). ADS only widens the
## shoulder (camera shifts right); distance/height are unchanged (no pull-in).
static func rig_params(blend: float) -> Dictionary:
	return {
		"dist": lerpf(HIP_DIST, ADS_DIST, blend),
		"height": lerpf(HIP_HEIGHT, ADS_HEIGHT, blend),
		"shoulder": lerpf(HIP_SHOULDER, ADS_SHOULDER, blend),
	}

## ADS FOV derived from a base FOV + on-screen magnification, so the future Config
## FOV slider only sets base FOV and the zoom factor stays constant.
static func ads_fov_for(base_fov: float, zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / zoom))

## Called by the Config FOV slider (later milestone) to set the hip FOV.
func set_base_fov(fov: float) -> void:
	_base_fov = fov
