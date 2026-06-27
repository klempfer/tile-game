extends RefCounted
## M10 energy economy. Pure, integer-tick, headlessly tested (mirrors health.gd / recoil.gd). One 200
## pool backs sprint / dodge / shield (and build, M12). No nodes, no Input, no RNG. The owning actor
## (player.gd) spends/drains it and ticks it once per ACTIVE tick. Referenced via preload (no class_name).
##
## States: NORMAL -> (pool hits 0) STUNNED (2 s, no actions/fire/reload) -> RECOVERING (refills fast,
## energy actions still locked, but fire/reload allowed) -> NORMAL once full. Energy actions are only
## permitted in NORMAL. Determinism: energy is float but every input is deterministic; all DURATIONS
## (regen pause, stun) are integer ticks.

const MAX := 200.0
const REGEN_PER_TICK := 40.0 / 60.0          # normal regen, once the post-spend pause elapses
const REGEN_PAUSE_TICKS := 60                # default post-spend regen delay (1 s); dodge/shield use it
const SPRINT_REGEN_DELAY := 0                # sprint has NO post-spend delay (regen resumes the next tick)
const RECOVER_PER_TICK := 50.0 / 60.0        # post-stun recovery refill (faster than normal: ~4 s to full)
const SPRINT_DRAIN_PER_TICK := 15.0 / 60.0   # while sprinting
const DODGE_COST := 40.0                      # per roll
const SHIELD_DEPLOY_COST := 20.0             # to raise the shield
const SHIELD_DRAIN_PER_TICK := 20.0 / 60.0   # passive, while the shield is up
const SHIELD_BLOCK_MULT := 2.0               # energy spent per point of damage the shield blocks
const STUN_TICKS := 120                       # 2 s: no fire/reload/energy

const STATE_NORMAL := 0
const STATE_STUNNED := 1
const STATE_RECOVERING := 2

var energy: float
var _state: int
var _stun_left: int
var _regen_pause: int      # ticks until normal regen may resume = remaining of the LATEST-expiring
                           # per-action delay (parallel timers collapsed to one int via maxi on each spend)
var _spent_this_tick: bool # any energy spent this tick — blocks same-tick regen (so a 0-delay sprint
                           # can't out-regen its own drain); cleared at the end of tick()

func _init() -> void:
	reset()

## Round-start / spawn state: full pool, NORMAL, no pause.
func reset() -> void:
	energy = MAX
	_state = STATE_NORMAL
	_stun_left = 0
	_regen_pause = 0
	_spent_this_tick = false

func is_stunned() -> bool:
	return _state == STATE_STUNNED

func is_recovering() -> bool:
	return _state == STATE_RECOVERING

## Energy actions (sprint/dodge/shield) are only allowed in NORMAL.
func can_use_energy() -> bool:
	return _state == STATE_NORMAL

func energy_int() -> int:
	return int(round(maxf(energy, 0.0)))

## Discrete spend (dodge, shield deploy). Spends only in NORMAL and only if affordable; arms the
## per-action regen delay; landing exactly on 0 enters the stun. Returns whether the spend happened.
func try_spend(cost: float, regen_delay: int = REGEN_PAUSE_TICKS) -> bool:
	if _state != STATE_NORMAL:
		return false
	if cost <= 0.0:
		return true
	if energy < cost:
		return false
	energy -= cost
	_note_spend(regen_delay)
	if energy <= 0.0:
		_enter_stun()
	return true

## Continuous drain (sprint, shield passive). Only in NORMAL; arms the per-action regen delay. Returns
## false on the tick it bottoms out (the caller ends the action) — that tick also enters the stun.
func drain(per_tick: float, regen_delay: int = REGEN_PAUSE_TICKS) -> bool:
	if _state != STATE_NORMAL:
		return false
	if per_tick <= 0.0:
		return true
	energy -= per_tick
	_note_spend(regen_delay)
	if energy <= 0.0:
		_enter_stun()
		return false
	return true

## Shield block: consume SHIELD_BLOCK_MULT x the damage. Fully block if affordable (return 0 leaked);
## otherwise block what the remaining energy covers, zero the pool, stun, and return the LEAKED damage
## (which the caller applies to HP). Only reached while shielding, i.e. in NORMAL. Arms the shield delay.
func absorb(damage: float) -> float:
	if damage <= 0.0:
		return 0.0
	_note_spend(REGEN_PAUSE_TICKS)
	var cost := damage * SHIELD_BLOCK_MULT
	if energy >= cost:
		energy -= cost
		if energy <= 0.0:
			_enter_stun()
		return 0.0
	var blockable := energy / SHIELD_BLOCK_MULT
	energy = 0.0
	_enter_stun()
	return damage - blockable

## Record a spend: block same-tick regen, and extend the regen pause to the LATEST of the running delay
## and this action's delay (parallel timers via maxi — a shorter delay never shrinks a longer one).
func _note_spend(regen_delay: int) -> void:
	_spent_this_tick = true
	_regen_pause = maxi(_regen_pause, regen_delay)

## One ACTIVE tick: advance the stun/recovery phases and the normal regen (callers must not tick during
## match-phase freezes, so the economy pauses then).
func tick() -> void:
	match _state:
		STATE_STUNNED:
			_stun_left -= 1
			if _stun_left <= 0:
				_state = STATE_RECOVERING
		STATE_RECOVERING:
			energy = minf(energy + RECOVER_PER_TICK, MAX)
			if energy >= MAX:
				energy = MAX
				_state = STATE_NORMAL
				_regen_pause = 0
		STATE_NORMAL:
			if _regen_pause > 0:
				_regen_pause -= 1
			elif not _spent_this_tick and energy < MAX:
				energy = minf(energy + REGEN_PER_TICK, MAX)
	_spent_this_tick = false  # cleared each tick: only blocks regen on a tick that actually spent

func _enter_stun() -> void:
	energy = 0.0
	_state = STATE_STUNNED
	_stun_left = STUN_TICKS

# --- introspection (HUD / tests) ---

func state_id() -> int:
	return _state

func stun_ticks_left() -> int:
	return _stun_left

func regen_pause_ticks() -> int:
	return _regen_pause
