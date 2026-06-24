extends RefCounted
## Deterministic player movement model (M1).
##
## Pure velocity update given a command + dt + on_floor flag. The CALLER
## integrates position: the live CharacterBody3D via move_and_slide() (collision),
## the self-test via simple Euler on a flat floor. No raw Input and no global
## random here, so movement is fully testable and reproducible.

const InputCommand = preload("res://input/input_command.gd")

# --- M1 tuning (chosen with the user) ---
const WALK_SPEED := 5.0      # m/s
const SPRINT_MULT := 1.6     # -> ~8 m/s
const CROUCH_MULT := 0.5     # -> ~2.5 m/s
const GRAVITY := 25.0        # m/s^2
const JUMP_APEX := 1.2       # m (jump velocity derived from this + gravity)
const GROUND_ACCEL := 56.25  # m/s^2 ramp toward target (+25% snappier direction changes)
const GROUND_DECEL := 68.75  # m/s^2 ramp toward 0 when no input (+25%)
const AIR_ACCEL := 12.0      # m/s^2 partial air control

var velocity := Vector3.ZERO
var crouching := false
var _prev_buttons := 0
var _jump_velocity := sqrt(2.0 * GRAVITY * JUMP_APEX)  # ~7.746 m/s

func reset() -> void:
	velocity = Vector3.ZERO
	crouching = false
	_prev_buttons = 0

func _target_speed(buttons: int) -> float:
	if crouching:
		return WALK_SPEED * CROUCH_MULT
	if buttons & InputCommand.BTN_SPRINT:
		return WALK_SPEED * SPRINT_MULT
	return WALK_SPEED

## Advance velocity by one fixed tick.
##   cmd      : InputCommand (move_dir local: x = strafe, y = forward; buttons bitmask)
##   dt       : fixed timestep (1/60)
##   on_floor : whether the body is grounded this tick
func tick(cmd: InputCommand, dt: float, on_floor: bool, yaw: float = 0.0) -> void:
	# Crouch is only allowed on the ground: you stand while airborne, cannot newly
	# crouch mid-jump, and resume crouching only after landing.
	crouching = on_floor and (cmd.buttons & InputCommand.BTN_CROUCH) != 0

	# Horizontal: world-space desired direction. M1 has no camera yet, so the
	# command's local move maps straight to world axes (forward = -Z). M2 will
	# rotate this by the camera yaw.
	# Camera-relative: local move (x = strafe, y = forward) rotated by the camera yaw.
	var dir := Vector3(cmd.move_dir.x, 0.0, -cmd.move_dir.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	dir = dir.rotated(Vector3.UP, yaw)
	var target := dir * _target_speed(cmd.buttons)
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	if on_floor and dir.length() < 0.01:
		accel = GROUND_DECEL
	horiz = horiz.move_toward(target, accel * dt)
	velocity.x = horiz.x
	velocity.z = horiz.z

	# Vertical: gravity + edge-triggered jump (holding jump does not re-jump).
	var jump_edge: bool = (cmd.buttons & InputCommand.BTN_JUMP) != 0 and (_prev_buttons & InputCommand.BTN_JUMP) == 0
	if on_floor:
		if velocity.y < 0.0:
			velocity.y = 0.0
		if jump_edge:
			velocity.y = _jump_velocity
	else:
		velocity.y -= GRAVITY * dt

	_prev_buttons = cmd.buttons
