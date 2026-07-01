extends RefCounted
## M10 dodge roll. Pure, integer-tick, headlessly tested. A short directional burst: on start it locks
## a flattened XZ direction and outputs a constant horizontal velocity for DODGE_TICKS, then idles. No
## i-frames (it never touches combat) and — by the caller's contract — uncancellable once started. The
## energy cost lives in energy.gd; this is purely the kinematics. Referenced via preload (no class_name).

const DODGE_TICKS := 18      # 0.3 s @ 60 Hz — the moving burst phase
const LOCK_TICKS := 12       # M11.5: 0.2 s post-roll action lock (frozen, no move/act) after the burst
const DODGE_SPEED := 17.5    # m/s burst (~5.25 m over the roll); +25% over the M10 14.0 for stronger
                             # repositioning since the roll has no i-frames. Tunable in playtest.

# M11.5: one timer spans BOTH phases — burst while _ticks_left > LOCK_TICKS, then the post-roll lock for
# the final LOCK_TICKS. active() stays true across the whole window, so the caller keeps the player frozen
# through the lock; velocity() supplies the burst only during the first phase (zero during the lock).
var _ticks_left: int = 0
var _dir: Vector3 = Vector3.ZERO   # locked, flattened, normalized roll direction

func reset() -> void:
	_ticks_left = 0
	_dir = Vector3.ZERO

## True through BOTH the moving burst and the post-roll lock — the caller freezes input the whole time.
func active() -> bool:
	return _ticks_left > 0

## Begin a roll along `dir` (flattened to XZ + normalized) if idle. Returns whether it started (false if
## already rolling/locked, or `dir` is ~zero — the caller passes a forward fallback so it never gets zero).
func try_start(dir: Vector3) -> bool:
	if _ticks_left > 0:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		return false
	_dir = flat.normalized()
	_ticks_left = DODGE_TICKS + LOCK_TICKS   # M11.5: burst then the post-roll lock, one timer
	return true

## Horizontal burst velocity during the burst phase only (zero during the post-roll lock and when idle).
## The caller keeps the vertical component (gravity / floor) from the motion model, so an air-dodge still
## falls — and during the lock the player is frozen-in-place horizontally (still subject to gravity).
func velocity() -> Vector3:
	if _ticks_left > LOCK_TICKS:
		return _dir * DODGE_SPEED
	return Vector3.ZERO

func tick() -> void:
	if _ticks_left > 0:
		_ticks_left -= 1

func ticks_left() -> int:
	return _ticks_left
