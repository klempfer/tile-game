extends RefCounted
## M10 dodge roll. Pure, integer-tick, headlessly tested. A short directional burst: on start it locks
## a flattened XZ direction and outputs a constant horizontal velocity for DODGE_TICKS, then idles. No
## i-frames (it never touches combat) and — by the caller's contract — uncancellable once started. The
## energy cost lives in energy.gd; this is purely the kinematics. Referenced via preload (no class_name).

const DODGE_TICKS := 18      # 0.3 s @ 60 Hz
const DODGE_SPEED := 17.5    # m/s burst (~5.25 m over the roll); +25% over the M10 14.0 for stronger
                             # repositioning since the roll has no i-frames. Tunable in playtest.

var _ticks_left: int = 0
var _dir: Vector3 = Vector3.ZERO   # locked, flattened, normalized roll direction

func reset() -> void:
	_ticks_left = 0
	_dir = Vector3.ZERO

func active() -> bool:
	return _ticks_left > 0

## Begin a roll along `dir` (flattened to XZ + normalized) if idle. Returns whether it started (false
## if already rolling or `dir` is ~zero — the caller passes a backward fallback so it never gets zero).
func try_start(dir: Vector3) -> bool:
	if _ticks_left > 0:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		return false
	_dir = flat.normalized()
	_ticks_left = DODGE_TICKS
	return true

## Horizontal burst velocity while active (zero otherwise). The caller keeps the vertical component
## (gravity / floor) from the motion model, so an air-dodge still falls.
func velocity() -> Vector3:
	if _ticks_left <= 0:
		return Vector3.ZERO
	return _dir * DODGE_SPEED

func tick() -> void:
	if _ticks_left > 0:
		_ticks_left -= 1

func ticks_left() -> int:
	return _ticks_left
