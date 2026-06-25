extends RefCounted
## Deterministic match/round state machine (M7). Integer-tick timers, no nodes / no
## RNG — headlessly tested. GDD §14: a round is won at 3 points, a match is first to 2
## rounds; on round end the world resets to match-start.
##
## Kills (which award points) arrive in M9 — they will simply call `add_point(team)`;
## everything here (round/match progression, freezes, resets) already works. The owning
## node (MatchDirector) reads `is_active()`/phase each tick and reacts to the one-shot
## events from `tick()`. Referenced via preload (no class_name).

const TEAM1 := 1
const TEAM2 := 2

const PHASE_COUNTDOWN := 0   # frozen pre-round (world already reset); counting down to GO
const PHASE_ACTIVE := 1      # round live; points count, actors move, capture runs
const PHASE_ROUND_OVER := 2  # frozen; showing the round result before the next round
const PHASE_MATCH_OVER := 3  # frozen on the final result until a restart

const POINTS_TO_WIN_ROUND := 3
const ROUNDS_TO_WIN_MATCH := 2
const COUNTDOWN_TICKS := 180    # 3 s @ 60 Hz
const ROUND_OVER_TICKS := 180   # 3 s

var phase: int
var round_index: int
var round_wins: Dictionary
var points: Dictionary
var _timer: int
var _last_round_winner: int
var _match_winner: int

func _init() -> void:
	restart()

## Begin a fresh match: round 1, scores cleared, frozen on the opening countdown.
func restart() -> void:
	round_index = 1
	round_wins = {TEAM1: 0, TEAM2: 0}
	points = {TEAM1: 0, TEAM2: 0}
	_last_round_winner = 0
	_match_winner = 0
	phase = PHASE_COUNTDOWN
	_timer = COUNTDOWN_TICKS

func is_active() -> bool:
	return phase == PHASE_ACTIVE

func round_winner() -> int:
	return _last_round_winner

func match_winner() -> int:
	return _match_winner

func time_left_ticks() -> int:
	return _timer

## Advance one fixed tick. Returns a one-shot event for the director:
##   "round_reset" — a new round's countdown just began; reset the world (tiles+actors).
##   ""            — nothing to act on this tick.
func tick() -> String:
	match phase:
		PHASE_COUNTDOWN:
			_timer -= 1
			if _timer <= 0:
				phase = PHASE_ACTIVE
		PHASE_ROUND_OVER:
			_timer -= 1
			if _timer <= 0:
				round_index += 1
				points = {TEAM1: 0, TEAM2: 0}
				phase = PHASE_COUNTDOWN
				_timer = COUNTDOWN_TICKS
				return "round_reset"
	return ""

## Award a point to `team` (placeholder for an M9 kill). Only counts during ACTIVE.
## Returns true if this point won the round. Winning the match enters MATCH_OVER;
## otherwise the round result freezes for ROUND_OVER_TICKS before the next round.
func add_point(team: int) -> bool:
	if phase != PHASE_ACTIVE:
		return false
	points[team] += 1
	if points[team] < POINTS_TO_WIN_ROUND:
		return false
	round_wins[team] += 1
	_last_round_winner = team
	if round_wins[team] >= ROUNDS_TO_WIN_MATCH:
		_match_winner = team
		phase = PHASE_MATCH_OVER
	else:
		phase = PHASE_ROUND_OVER
		_timer = ROUND_OVER_TICKS
	return true
