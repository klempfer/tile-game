extends "res://input/input_provider.gd"
## Reads Godot Input (KB+M + controller) into an InputCommand: move, look (radians
## this tick, sensitivity- and ADS-scaled) and buttons. Mouse motion is pushed in
## via add_mouse_motion() from the owning node's _input. The ONLY place raw Input
## is read. (InputCommand const is inherited from the base provider.)

const DefaultBinds = preload("res://input/default_binds.gd")

const DT := 1.0 / 60.0
const MOUSE_SENS := 0.003     # rad per pixel (~0.17 deg/px)
const STICK_RATE := 2.618     # rad/sec (~150 deg/s) at full deflection
const ADS_SENS_MULT := 0.6

var _mouse_accum := Vector2.ZERO
var _ads_toggle := false

func _init() -> void:
	DefaultBinds.ensure_default_actions()

## Called from the owning node's _input with InputEventMouseMotion.relative.
func add_mouse_motion(rel: Vector2) -> void:
	_mouse_accum += rel

func poll(_tick: int):
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if Input.is_action_just_pressed("ads_toggle"):
		_ads_toggle = not _ads_toggle
	var ads_req := _ads_toggle or Input.is_action_pressed("ads_hold")

	# Sprint and ADS are mutually exclusive — the most recently initiated wins.
	var res := resolve_exclusive(Input.is_action_pressed("sprint"), Input.is_action_just_pressed("sprint"), ads_req)
	var ads: bool = res["ads"]
	var sprint: bool = res["sprint"]
	if ads_req and not ads:
		_ads_toggle = false  # a fresh sprint cancelled ADS; don't let the toggle re-pop

	var look := look_delta(_mouse_accum, stick, DT, ads)
	_mouse_accum = Vector2.ZERO
	var buttons := 0
	if Input.is_action_pressed("jump"):
		buttons |= InputCommand.BTN_JUMP
	if sprint:
		buttons |= InputCommand.BTN_SPRINT
	if Input.is_action_pressed("crouch"):
		buttons |= InputCommand.BTN_CROUCH
	if ads:
		buttons |= InputCommand.BTN_ADS
	# M8 combat: Fire auto-repeats (held); reload + weapon select are edge-triggered.
	if Input.is_action_pressed("fire"):
		buttons |= InputCommand.BTN_FIRE
	if Input.is_action_just_pressed("reload"):
		buttons |= InputCommand.BTN_RELOAD
	if Input.is_action_just_pressed("weapon_1"):
		buttons |= InputCommand.BTN_WEAPON1
	if Input.is_action_just_pressed("weapon_2"):
		buttons |= InputCommand.BTN_WEAPON2
	return InputCommand.new(_tick, move, look, buttons)

## Resolve sprint vs ADS mutual exclusion. Most recently initiated action wins: a
## fresh sprint press cancels ADS; otherwise an active ADS suppresses sprint. Pure
## (no Input) so it is unit-tested headlessly.
static func resolve_exclusive(sprint_held: bool, sprint_pressed: bool, ads_in: bool) -> Dictionary:
	var ads := ads_in
	if sprint_pressed and ads:
		ads = false
	var sprint := sprint_held and not ads
	return {"sprint": sprint, "ads": ads}

## Pure look-delta math (radians this tick): mouse px + stick, sensitivity and ADS
## scaling. yaw +: turn left (CCW); pitch +: look up. Unit-tested.
static func look_delta(mouse_px: Vector2, stick: Vector2, dt: float, ads: bool) -> Vector2:
	var mult := ADS_SENS_MULT if ads else 1.0
	var yaw := -(mouse_px.x * MOUSE_SENS + stick.x * STICK_RATE * dt) * mult
	var pitch := (-mouse_px.y * MOUSE_SENS - stick.y * STICK_RATE * dt) * mult
	return Vector2(yaw, pitch)
