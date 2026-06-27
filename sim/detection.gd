extends RefCounted
## M11 detection (information mechanic). Pure, integer-tick, headlessly tested (mirrors health.gd /
## energy.gd). No nodes, no Input, no RNG — the owning actor (player.gd) holds an instance and the
## scene-level DetectionDirector feeds it the distance to the nearest enemy each ACTIVE tick + an
## on_fire() on a firing tick; the director reads `detected` to drive rendering. Referenced via preload
## (no class_name). Determinism: `detected` is a bool, all DURATIONS (bloom, linger) are integer ticks,
## the only float is the distance comparison (deterministic from positions).
##
## WoWS model: `detected` means "is THIS actor currently visible to the enemy team". An actor blooms
## its OWN detectability range when IT fires (firing reveals you). An enemy within the effective range
## detects you; once you escape it you LINGER (stay visible) for LINGER_TICKS before going dark again.

const BASE_RANGE := 17.5      # m: an enemy this close detects you (user override of GDD §11's 20 m)
const FIRE_RANGE := 50.0      # m: detectability while the fire-bloom is active (GDD §11)
const BLOOM_TICKS := 60       # 1 s: firing raises your range to FIRE_RANGE for this long (GDD §11)
const LINGER_TICKS := 120     # 2 s: stay visible this long after escaping range (user override of 3 s)

var detected: bool
var _bloom: int               # ticks left of the fire-bloom (range = FIRE_RANGE while > 0)
var _linger: int              # ticks left of post-escape visibility

func _init() -> void:
	reset()

## Round-start / spawn state: not detected, no bloom, no linger.
func reset() -> void:
	detected = false
	_bloom = 0
	_linger = 0

## This actor fired this tick: light up to FIRE_RANGE for BLOOM_TICKS ("firing reveals you").
## Called by player.gd in _fire(), beside _health.on_fire(). Apply before step() on the same tick.
func on_fire() -> void:
	_bloom = BLOOM_TICKS

## Current detectability radius — FIRE_RANGE while the fire-bloom is active, else BASE_RANGE.
func effective_range() -> float:
	return FIRE_RANGE if _bloom > 0 else BASE_RANGE

## One ACTIVE tick. `min_enemy_dist` = center-to-center distance to the nearest enemy that could detect
## this actor (the director computes it; +INF when there are none). In range -> detected, refresh the
## full linger. Out of range -> count the linger down; stay detected until it elapses. Then age the
## bloom. Callers must NOT step during match-phase freezes, so the timers pause then (like health/energy).
func step(min_enemy_dist: float) -> void:
	if min_enemy_dist <= effective_range():
		detected = true
		_linger = LINGER_TICKS
	elif _linger > 0:
		_linger -= 1
		detected = _linger > 0
	else:
		detected = false
	if _bloom > 0:
		_bloom -= 1

# --- introspection (HUD / tests) ---

func bloom_ticks() -> int:
	return _bloom

func linger_ticks() -> int:
	return _linger
