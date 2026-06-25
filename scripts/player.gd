extends CharacterBody3D
## M2 player: third-person over-the-shoulder camera, mouse + stick look, ADS zoom,
## camera-relative movement. One InputCommand per fixed tick; look + ADS travel in
## the command (netcode/replay-friendly). Motion stays in the pure PlayerMotion
## model; the camera orbit + look math are pure static helpers (unit-tested).

const InputCommand = preload("res://input/input_command.gd")
const PlayerMotion = preload("res://sim/player_motion.gd")
const LocalInputProvider = preload("res://input/local_input_provider.gd")

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

@export var start_yaw := 0.0     # initial facing (radians); set per scene

var _motion = PlayerMotion.new()
var _provider = LocalInputProvider.new()
var _tick := 0
var _yaw := 0.0
var _pitch := 0.0
var _ads_blend := 0.0
var _base_fov := 75.0           # hip FOV; later driven by the Config FOV slider

@onready var _col: CollisionShape3D = $Collision
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_yaw = start_yaw
	rotation.y = _yaw
	print("[Player] spawned at %v, active camera: %s" % [global_position, _camera.name])
	_update_camera(false, 0.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_provider.add_mouse_motion((event as InputEventMouseMotion).relative)
	elif event.is_action_pressed("ui_cancel"):
		# Free / recapture the mouse for testing.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
	var cmd = _provider.poll(_tick)

	# Look (radians this tick) -> yaw/pitch. Body faces yaw (strafe-style).
	_yaw = wrapf(_yaw + cmd.look.x, -PI, PI)
	_pitch = clampf(_pitch + cmd.look.y, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = _yaw

	_motion.tick(cmd, FIXED_DT, is_on_floor(), _yaw)
	velocity = _motion.velocity
	move_and_slide()
	_apply_crouch(_motion.crouching)

	var ads: bool = (cmd.buttons & InputCommand.BTN_ADS) != 0
	_update_camera(ads, FIXED_DT)
	_tick += 1

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

func _update_camera(ads: bool, dt: float) -> void:
	_ads_blend = move_toward(_ads_blend, 1.0 if ads else 0.0, ADS_BLEND_SPEED * dt)
	var p := rig_params(_ads_blend)
	# Zoom from FOV only (magnification relative to base FOV); aim direction is
	# unchanged, so the crosshair (screen center) stays centered while ADS shifts
	# the camera laterally right via the larger shoulder offset.
	_camera.fov = lerpf(_base_fov, ads_fov_for(_base_fov, ADS_ZOOM), _ads_blend)
	var cam_pos := camera_position_grounded(global_position, _yaw, _pitch, p["dist"], p["height"], p["shoulder"], CAM_MIN_Y)
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
