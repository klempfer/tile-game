extends Node
## M7 self-test: the deterministic match/round state machine (countdown -> active ->
## round-over -> next round / match-over, points->round, rounds->match) and the round
## reset primitives (TileGrid snapshot/restore, Capture.reset). Pure, no nodes; prints
## [TEST] lines then idles.

const SquareTopology = preload("res://sim/square_topology.gd")
const TileGrid = preload("res://sim/tile_grid.gd")
const Capture = preload("res://sim/capture.gd")
const MatchState = preload("res://sim/match_state.gd")

const DT := 1.0 / 60.0

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m7 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m7 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _run_suite() -> void:
	var T1 := MatchState.TEAM1
	var T2 := MatchState.TEAM2

	# Opening state: frozen on the round-1 countdown.
	var s := MatchState.new()
	_check("starts_countdown", s.phase == MatchState.PHASE_COUNTDOWN and s.round_index == 1 \
		and not s.is_active() and s.round_wins[T1] == 0 and s.round_wins[T2] == 0)

	# Countdown ticks down to ACTIVE on exactly COUNTDOWN_TICKS.
	for i in MatchState.COUNTDOWN_TICKS - 1:
		s.tick()
	var pre_active: bool = not s.is_active()
	s.tick()
	_check("countdown_to_active", pre_active and s.is_active())

	# Points are ignored outside ACTIVE.
	var s2 := MatchState.new()
	var ignored: bool = (s2.add_point(T1) == false) and s2.points[T1] == 0
	_check("point_ignored_in_countdown", ignored)

	# Three points win the round: round_wins++, points cleared, enter ROUND_OVER.
	var s3 := MatchState.new()
	_to_active(s3)
	var w1: bool = s3.add_point(T1)
	var w2: bool = s3.add_point(T1)
	var w3: bool = s3.add_point(T1)
	# points stay at 3 during ROUND_OVER (final score shown), then clear at round_reset.
	_check("three_points_win_round", (not w1) and (not w2) and w3 and s3.round_wins[T1] == 1 \
		and s3.points[T1] == MatchState.POINTS_TO_WIN_ROUND and s3.phase == MatchState.PHASE_ROUND_OVER)

	# ROUND_OVER advances to the next round's countdown (one-shot "round_reset" event).
	var ev := ""
	for i in MatchState.ROUND_OVER_TICKS:
		var e: String = s3.tick()
		if e != "":
			ev = e
	_check("round_over_advances", ev == "round_reset" and s3.round_index == 2 \
		and s3.phase == MatchState.PHASE_COUNTDOWN and s3.points[T1] == 0)

	# First to 2 rounds wins the match.
	var s4 := MatchState.new()
	_win_round(s4, T1)
	_finish_round_over(s4)
	_win_round(s4, T1)
	_check("first_to_two_wins_match", s4.phase == MatchState.PHASE_MATCH_OVER \
		and s4.match_winner() == T1 and s4.round_wins[T1] == 2)
	_check("point_ignored_match_over", s4.add_point(T2) == false)

	# A split match (T1, T2, T1) still ends correctly at 2 round wins for T1.
	var s5 := MatchState.new()
	_win_round(s5, T1); _finish_round_over(s5)
	_win_round(s5, T2); _finish_round_over(s5)
	_win_round(s5, T1)
	_check("split_match_winner", s5.phase == MatchState.PHASE_MATCH_OVER and s5.match_winner() == T1 \
		and s5.round_wins[T1] == 2 and s5.round_wins[T2] == 1 and s5.round_index == 3)

	# restart() clears everything back to the opening state.
	s5.restart()
	_check("restart_clears", s5.round_index == 1 and s5.round_wins[T1] == 0 and s5.points[T1] == 0 \
		and s5.phase == MatchState.PHASE_COUNTDOWN and s5.match_winner() == 0)

	# --- reset primitives ---
	# TileGrid snapshot/restore round-trips ownership exactly.
	var g := TileGrid.new(SquareTopology.new(9, 20, 5.0))
	g.set_owner(Vector2i(1, 1), TileGrid.TEAM1)
	var snap := g.snapshot()
	g.set_owner(Vector2i(1, 1), TileGrid.TEAM2)
	g.set_owner(Vector2i(2, 1), TileGrid.TEAM1)
	g.restore(snap)
	_check("grid_snapshot_restore", g.get_owner(Vector2i(1, 1)) == TileGrid.TEAM1 \
		and g.get_owner(Vector2i(2, 1)) == TileGrid.NEUTRAL)

	# Capture.reset() clears in-progress captures.
	var g2 := TileGrid.new(SquareTopology.new(9, 20, 5.0))
	var cap := Capture.new(g2)
	for i in 60:
		cap.step({TileGrid.TEAM1: Vector2i(1, 1)}, DT)
	var mid: bool = cap.progress_fraction(Vector2i(1, 1)) > 0.0
	cap.reset()
	_check("capture_reset_clears", mid and cap.progress_fraction(Vector2i(1, 1)) == 0.0 and cap.active_tiles().is_empty())

func _to_active(state) -> void:
	var guard := 0
	while not state.is_active() and guard < 10000:
		state.tick()
		guard += 1

func _win_round(state, team: int) -> void:
	_to_active(state)
	state.add_point(team)
	state.add_point(team)
	state.add_point(team)

func _finish_round_over(state) -> void:
	var guard := 0
	while state.phase == MatchState.PHASE_ROUND_OVER and guard < 10000:
		state.tick()
		guard += 1
