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

@onready var _col: CollisionShape3D = $Collision
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _camera: Camera3D = $Camera3D
# M8.5: bullet-origin marker. A real node (not a computed point) so that once character + weapon
# models exist it can be parented under the weapon — its global_position then tracks the actual muzzle
# through any animation for free. For the placeholder capsule its height follows the crouch (see
# _apply_crouch). get_node_or_null keeps older scenes safe; _muzzle_origin() falls back to a computed
# eye point if absent.
@onready var _muzzle: Marker3D = get_node_or_null("Muzzle")

func _ready() -> void:
	if is_local:
		_provider = LocalInputProvider.new()
	else:
		_provider = BotInputProvider.new()
	_apply_body_color()
	_yaw = start_yaw
	rotation.y = _yaw
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_camera.current = true   # explicit: win the active-camera race vs. the bot's
		print("[Player] spawned at %v, active camera: %s" % [global_position, _camera.name])
		_update_camera(false, 0.0)
	else:
		_camera.current = false  # avoid two cameras both current=true
		print("[Bot] spawned at %v" % global_position)

func _apply_body_color() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = body_color
	_mesh.material_override = m

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
		# M7 freeze (countdown / round-over / match-over): hold still on the floor.
		velocity = Vector3.ZERO
		move_and_slide()
		_tick += 1
		return

	# Look (radians this tick) -> yaw/pitch. Body faces yaw (strafe-style). M8.5: the wrap/clamp lives
	# in Recoil.apply_look so recoil tracks the ACTUAL (post-clamp) reticle movement, not raw input
	# (matters at the pitch limit / aiming at the ground); it returns the actual delta for AOP tracking.
	var look_res := Recoil.apply_look(_yaw, _pitch, cmd.look, PITCH_LIMIT)
	_yaw = look_res["yaw"]
	_pitch = look_res["pitch"]
	rotation.y = _yaw

	_motion.tick(cmd, FIXED_DT, is_on_floor(), _yaw)
	velocity = _motion.velocity
	var from_pos := global_position
	move_and_slide()
	_apply_tile_restriction(from_pos)
	_apply_crouch(_motion.crouching)
	_fire(cmd, look_res["delta"])  # M8/M8.5: fire decision -> shot (pre-impulse) -> recoil via look channel

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
	_apply_crouch(false)
	if is_local:
		_update_camera(false, 0.0)

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
## stranded (current cell illegal after a tile flip) nothing is clamped — free roam —
## and that branch is where the M9 stranded damage-over-time will later hook in.
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
