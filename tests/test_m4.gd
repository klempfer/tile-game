extends Node
## M4 self-test: capture timing (exact ticks), neutralize->capture flow, contest
## hold/resume, leave-resets, spawn immunity, and frontier outline categories. All
## deterministic, no nodes. Prints [TEST] lines then idles.

const SquareTopology = preload("res://sim/square_topology.gd")
const TileGrid = preload("res://sim/tile_grid.gd")
const Capture = preload("res://sim/capture.gd")

const DT := 1.0 / 60.0

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m4 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m4 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _new_grid() -> Object:
	return TileGrid.new(SquareTopology.new(9, 20, 5.0))

func _run(capture, presence: Dictionary, ticks: int) -> void:
	for i in ticks:
		capture.step(presence, DT)

func _run_suite() -> void:
	var P := Vector2i(1, 1)  # a neutral working tile (not a spawn)

	# Comeback capture: owner has 1 tile (< 5) -> 2.5 s = 150 ticks.
	var g1 := _new_grid()
	var c1 = Capture.new(g1)
	_run(c1, {TileGrid.TEAM1: P}, 149)
	var pre: bool = g1.get_owner(P) == TileGrid.NEUTRAL
	_run(c1, {TileGrid.TEAM1: P}, 1)
	_check("comeback_capture_150", pre and g1.get_owner(P) == TileGrid.TEAM1)

	# No-comeback capture: owner already holds 5 tiles -> 5 s = 300 ticks.
	var g2 := _new_grid()
	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]:
		g2.set_owner(c, TileGrid.TEAM1)  # + spawn (5,1) = 5 owned
	var c2 = Capture.new(g2)
	var tgt := Vector2i(1, 2)
	_run(c2, {TileGrid.TEAM1: tgt}, 299)
	var pre2: bool = g2.get_owner(tgt) == TileGrid.NEUTRAL
	_run(c2, {TileGrid.TEAM1: tgt}, 1)
	_check("no_comeback_capture_300", pre2 and g2.get_owner(tgt) == TileGrid.TEAM1)

	# Enemy -> neutral (300) -> yours (150 with comeback) in one continuous stand.
	var g3 := _new_grid()
	g3.set_owner(P, TileGrid.TEAM2)
	var c3 = Capture.new(g3)
	_run(c3, {TileGrid.TEAM1: P}, 300)
	var neutralized: bool = g3.get_owner(P) == TileGrid.NEUTRAL
	_run(c3, {TileGrid.TEAM1: P}, 150)
	_check("neutralize_then_capture", neutralized and g3.get_owner(P) == TileGrid.TEAM1, "(neut@300=%s)" % str(neutralized))

	# Neutralize is NOT sped by comeback (still 5 s even though owner has < 5 tiles).
	var g3b := _new_grid()
	g3b.set_owner(P, TileGrid.TEAM2)
	var c3b = Capture.new(g3b)
	_run(c3b, {TileGrid.TEAM1: P}, 299)
	_check("neutralize_not_comeback", g3b.get_owner(P) == TileGrid.TEAM2)

	# Contest holds progress; resumes when one remains.
	var g4 := _new_grid()
	var c4 = Capture.new(g4)
	_run(c4, {TileGrid.TEAM1: P}, 60)
	var frac_before: float = c4.progress_fraction(P)
	_run(c4, {TileGrid.TEAM1: P, TileGrid.TEAM2: P}, 300)
	var held: bool = g4.get_owner(P) == TileGrid.NEUTRAL and absf(c4.progress_fraction(P) - frac_before) < 1e-6
	_run(c4, {TileGrid.TEAM1: P}, 90)
	_check("contest_holds_then_resumes", held and g4.get_owner(P) == TileGrid.TEAM1, "(frac=%.3f)" % frac_before)

	# Leaving resets progress.
	var g5 := _new_grid()
	var c5 = Capture.new(g5)
	_run(c5, {TileGrid.TEAM1: P}, 100)
	var f_before: float = c5.progress_fraction(P)
	_run(c5, {}, 1)
	_check("leave_resets", f_before > 0.5 and c5.progress_fraction(P) == 0.0 and g5.get_owner(P) == TileGrid.NEUTRAL, "(before=%.3f)" % f_before)

	# Spawn tile immune to enemy neutralize.
	var g6 := _new_grid()
	var c6 = Capture.new(g6)
	_run(c6, {TileGrid.TEAM2: Vector2i(5, 1)}, 600)
	_check("spawn_immune", g6.get_owner(Vector2i(5, 1)) == TileGrid.TEAM1)

	# Frontier outline categories.
	var g7 := _new_grid()
	g7.set_owner(Vector2i(3, 3), TileGrid.TEAM1)
	_check("outline_t1_isolated", g7.outline_category(Vector2i(3, 3)) == 1)
	_check("outline_neutral_adj_t1", g7.outline_category(Vector2i(3, 4)) == 1)
	g7.set_owner(Vector2i(4, 3), TileGrid.TEAM2)
	_check("outline_t1_adj_t2_blend", g7.outline_category(Vector2i(3, 3)) == 3)

	var g8 := _new_grid()
	g8.set_owner(Vector2i(3, 3), TileGrid.TEAM1)
	g8.set_owner(Vector2i(5, 3), TileGrid.TEAM2)
	_check("outline_neutral_adj_both_blend", g8.outline_category(Vector2i(4, 3)) == 3)
	_check("outline_neutral_isolated", g8.outline_category(Vector2i(8, 8)) == 0)
	g8.set_owner(Vector2i(9, 9), TileGrid.TEAM2)
	_check("outline_t2_isolated", g8.outline_category(Vector2i(9, 9)) == 2)
