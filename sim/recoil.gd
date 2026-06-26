extends RefCounted
## M8.5 aim-punch recoil with Aim-Origin-Point (AOP) recovery. Pure, integer-tick, headlessly
## tested. Firing kicks the player's aim away from the AOP (the intended aim before recoil); after
## firing stops + a delay the aim is pulled back to the AOP at CONSTANT angular speed (no easing /
## spring / lerp). The AOP follows legitimate player input. Referenced via preload (no class_name).
##
## State machine: IDLE -> FIRING -> RECOVERY_DELAY -> RECOVERING -> IDLE.
##
## Representation: instead of an absolute AOP angle we store the DISPLACEMENT
##   _D = current_aim - AOP    (a small Vector2(yaw, pitch) in radians)
## which is behaviourally identical but robust to yaw wrap-around (free 360 turning keeps _D.x tiny,
## never straddling +/-PI) and the pitch clamp (_D stays small/well-defined). The AOP, if needed, is
## current_aim - _D.
##
## Robustness: every change to _D is credited by the ACTUAL, post-clamp aim delta (for both player
## input and the recoil kick), so the AOP always sits at a reachable reticle angle (matters at the
## +/-pitch limit, e.g. aiming straight at the ground) and recovery always reaches it exactly.
##
## Determinism: timing is in integer ticks (the 0.1 s delay = 6 ticks); the recovery step is a fixed
## per-tick increment that SNAPS exactly to the AOP on the final tick (no overshoot). The fixed
## pattern uses no RNG; the injected rng is the seam for a future seeded jitter (see _pattern_offset).

const WeaponDefs = preload("res://sim/weapon_defs.gd")

const FIXED_DT := 1.0 / 60.0
const RECOVERY_DELAY_TICKS := 6        # 0.1 s @ 60 Hz: hold after firing stops before recovery begins

const STATE_IDLE := 0
const STATE_FIRING := 1
const STATE_RECOVERY_DELAY := 2
const STATE_RECOVERING := 3

# Fixed deterministic horizontal-drift pattern (multiplied by the weapon's recoil_yaw_deg). Indexed
# by shot number within a spray; repeats if a spray outlasts it. Vertical kick is constant per weapon.
const _PATTERN := [0.0, 0.35, 0.7, -0.5, -0.85, 0.25, -0.2, 0.55]

var _state: int = STATE_IDLE
var _D: Vector2 = Vector2.ZERO         # current_aim - AOP (radians); (0,0) <=> no active AOP in IDLE
var _delay_left: int = 0
var _shot_index: int = 0               # position in the spray pattern
var _weapon_id: int = -1               # to reset the pattern (only) on a weapon switch

## Fresh state for a new round / spawn.
func reset() -> void:
	_state = STATE_IDLE
	_D = Vector2.ZERO
	_delay_left = 0
	_shot_index = 0
	_weapon_id = -1

## Apply this tick's player look to an aim (yaw wrapped, pitch clamped) and report the ACTUAL applied
## delta. Shared by player.gd and the tests so the "actual reticle movement" math lives in one tested
## place. yaw is continuous (its actual delta == look.x); pitch can be clamped (lossy at the limit).
static func apply_look(yaw: float, pitch: float, look: Vector2, pitch_limit: float) -> Dictionary:
	var new_yaw := wrapf(yaw + look.x, -PI, PI)
	var new_pitch := clampf(pitch + look.y, -pitch_limit, pitch_limit)
	return {"yaw": new_yaw, "pitch": new_pitch, "delta": Vector2(look.x, new_pitch - pitch)}

## One fixed tick. `player_delta` is the ACTUAL input delta (from apply_look); `cur_yaw`/`cur_pitch`
## are the aim AFTER player input was applied (so this only adds the recoil contribution). `fired` is
## whether a shot fired this tick. Returns the final aim {yaw, pitch}.
func update(player_delta: Vector2, fired: bool, def: Dictionary, weapon_id: int, rng: RandomNumberGenerator, cur_yaw: float, cur_pitch: float, pitch_limit: float) -> Dictionary:
	# Weapon switch resets the pattern only — recovery / AOP must continue uninterrupted.
	if weapon_id != _weapon_id:
		_weapon_id = weapon_id
		_shot_index = 0

	# AOP tracking from the player's ACTUAL input (only while an AOP exists). Pure _D bookkeeping —
	# the input is already in cur_yaw/cur_pitch, so this returns no aim change.
	if _state != STATE_IDLE:
		_track_origin(player_delta)

	var out_yaw := cur_yaw
	var out_pitch := cur_pitch

	if fired:
		if _state == STATE_IDLE:
			_D = Vector2.ZERO            # new AOP born at the current (intended) aim
		_state = STATE_FIRING
		var k := _apply_impulse(def, rng, out_yaw, out_pitch, pitch_limit)
		out_yaw = k.x
		out_pitch = k.y
	else:
		match _state:
			STATE_FIRING:
				_state = STATE_RECOVERY_DELAY
				_delay_left = RECOVERY_DELAY_TICKS
				_tick_delay()
			STATE_RECOVERY_DELAY:
				_tick_delay()
			STATE_RECOVERING:
				var rr := _apply_recover(def, out_yaw, out_pitch, pitch_limit)
				out_yaw = rr.x
				out_pitch = rr.y
			# STATE_IDLE: nothing to do

	return {"yaw": out_yaw, "pitch": out_pitch}

# --- internals ---

func _tick_delay() -> void:
	_delay_left -= 1
	if _delay_left <= 0:
		_state = STATE_RECOVERING

## AOP follows legitimate player input (pure _D update, credited by the ACTUAL input delta):
##  - horizontal: tracked fully -> _D.x unchanged.
##  - vertical up (>= 0): tracked fully -> _D.y unchanged.
##  - vertical down (< 0): shrink the upward displacement toward 0 (the AOP follows the aim down so it
##    is never ABOVE the current aim), guaranteeing _D.y >= 0 and so recovery never pulls the aim up.
func _track_origin(player_delta: Vector2) -> void:
	if player_delta.y < 0.0:
		_D.y = maxf(_D.y + player_delta.y, 0.0)

## Aim punch: displace the aim away from the AOP by this shot's kick, clamped, crediting _D by the
## ACTUAL applied delta (so the AOP stays reachable even at the pitch limit). Advances the pattern.
func _apply_impulse(def: Dictionary, rng: RandomNumberGenerator, yaw: float, pitch: float, pitch_limit: float) -> Vector2:
	var kick := _pattern_offset(def, _shot_index, rng)
	_shot_index += 1
	var new_yaw := wrapf(yaw + kick.x, -PI, PI)
	var new_pitch := clampf(pitch + kick.y, -pitch_limit, pitch_limit)
	_D += Vector2(kick.x, new_pitch - pitch)   # yaw is continuous (actual == kick.x); pitch post-clamp
	return Vector2(new_yaw, new_pitch)

## Move the aim toward the AOP at constant angular speed; SNAP exactly on the final tick (no
## overshoot) and return to IDLE. No easing / spring / lerp.
func _apply_recover(def: Dictionary, yaw: float, pitch: float, pitch_limit: float) -> Vector2:
	var step := deg_to_rad(float(def["recoil_recovery_deg"])) * FIXED_DT
	var dist := _D.length()
	if dist <= step or dist == 0.0:
		var move := -_D
		_D = Vector2.ZERO
		_state = STATE_IDLE
		_shot_index = 0
		return Vector2(wrapf(yaw + move.x, -PI, PI), clampf(pitch + move.y, -pitch_limit, pitch_limit))
	var rmove := -_D.normalized() * step
	var new_yaw := wrapf(yaw + rmove.x, -PI, PI)
	var new_pitch := clampf(pitch + rmove.y, -pitch_limit, pitch_limit)
	_D += Vector2(rmove.x, new_pitch - pitch)  # credit by actual (recovery targets an in-range AOP)
	return Vector2(new_yaw, new_pitch)

## This shot's kick (yaw, pitch) in radians. FIXED deterministic pattern: constant upward pitch + a
## fixed horizontal drift sequence. To switch to seeded jitter later, replace the `yaw` line with
## `deg_to_rad(float(def["recoil_yaw_deg"])) * rng.randf_range(-1.0, 1.0)` (rng already plumbed in).
static func _pattern_offset(def: Dictionary, index: int, _rng: RandomNumberGenerator) -> Vector2:
	var pitch := deg_to_rad(float(def["recoil_pitch_deg"]))
	var yaw := deg_to_rad(float(def["recoil_yaw_deg"])) * float(_PATTERN[index % _PATTERN.size()])
	return Vector2(yaw, pitch)

# --- introspection (HUD / tests) ---

func state_id() -> int:
	return _state

func state_name() -> String:
	match _state:
		STATE_IDLE:
			return "IDLE"
		STATE_FIRING:
			return "FIRING"
		STATE_RECOVERY_DELAY:
			return "DELAY"
		STATE_RECOVERING:
			return "RECOVERING"
	return "?"

func displacement() -> Vector2:
	return _D

func shot_index() -> int:
	return _shot_index
