extends RefCounted
## M9 health / death / respawn. Pure, integer-tick, headlessly tested (mirrors recoil.gd /
## weapon_loadout.gd). No nodes, no Input, no RNG — the owning actor (player.gd) holds an instance,
## feeds it damage + a per-active-tick `tick()`, and applies the results. Referenced via preload
## (no class_name). Determinism: HP is a float but every input is deterministic (seeded spread ->
## deterministic damage); all DURATIONS (invuln, respawn) are counted in integer ticks.
##
## Life cycle: alive -> (HP hits 0) dead + respawn countdown -> (RESPAWN_TICKS) respawn at full HP
## with INVULN_TICKS of spawn protection that is BROKEN the moment the actor fires (on_fire).

const MAX_HP := 100.0
const RESPAWN_TICKS := 180                       # 3 s @ 60 Hz before respawning at the spawn tile
const INVULN_TICKS := 300                        # 5 s spawn protection, broken by firing (on_fire)
const STRANDED_DOT_PER_TICK := MAX_HP / 180.0    # ~33 HP/s -> drains a full bar in ~180 ticks (3 s)

var hp: float
var alive: bool
var _invuln_ticks: int
var _respawn_ticks: int

func _init() -> void:
	reset()

## Round-start / spawn state: full HP, alive, NO invulnerability (only post-death respawn grants it).
func reset() -> void:
	hp = MAX_HP
	alive = true
	_invuln_ticks = 0
	_respawn_ticks = 0

func is_dead() -> bool:
	return not alive

func is_invulnerable() -> bool:
	return _invuln_ticks > 0

## HP as a rounded int for HUD / combat-log output (keeps printed text byte-identical across runs).
func hp_int() -> int:
	return int(round(maxf(hp, 0.0)))

## Apply incoming damage. No-op while dead or invulnerable. Returns true iff this call KILLED
## (alive -> dead), so the caller can emit a death / award the kill exactly once.
func take_damage(amount: float) -> bool:
	if not alive or _invuln_ticks > 0:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		_respawn_ticks = RESPAWN_TICKS
		return true
	return false

## The actor fired a shot this tick: spawn invulnerability ends immediately ("broken by firing").
func on_fire() -> void:
	_invuln_ticks = 0

## Advance one ACTIVE tick (callers must NOT tick during match-phase freezes, so timers pause then).
## Alive: count down invulnerability. Dead: count down the respawn timer and return "respawn" on the
## tick it elapses (the actor then calls respawn()). Returns "" otherwise.
func tick() -> String:
	if alive:
		if _invuln_ticks > 0:
			_invuln_ticks -= 1
		return ""
	_respawn_ticks -= 1
	if _respawn_ticks <= 0:
		return "respawn"
	return ""

## Come back to life at full HP with spawn invulnerability (post-death only; reset() grants none).
func respawn() -> void:
	hp = MAX_HP
	alive = true
	_invuln_ticks = INVULN_TICKS
	_respawn_ticks = 0

# --- introspection (HUD / tests) ---

func invuln_ticks() -> int:
	return _invuln_ticks

func respawn_ticks() -> int:
	return _respawn_ticks
