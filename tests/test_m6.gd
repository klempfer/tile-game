extends Node
## M6 self-test: the trivial BotInputProvider (deterministic constant command) and an
## integrated two-actor tile war — two bots advancing toward each other along column 5,
## driving PlayerMotion + MovementRestriction + Capture headlessly (simple Euler on a
## flat floor, per M1). Proves the second-actor pipeline is deterministic and that a
## "hold forward" command creeps a capture frontier (the M5 keystone payoff). Pure, no
## nodes; prints [TEST] lines then idles.

const SquareTopology = preload("res://sim/square_topology.gd")
const TileGrid = preload("res://sim/tile_grid.gd")
const Capture = preload("res://sim/capture.gd")
const PlayerMotion = preload("res://sim/player_motion.gd")
const MR = preload("res://sim/movement_restriction.gd")
const BotInputProvider = preload("res://input/bot_input_provider.gd")

const DT := 1.0 / 60.0
const MARGIN := 0.4

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m6 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m6 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _run_suite() -> void:
	# --- BotInputProvider: constant forward, zero look/buttons, deterministic ---
	var bp = BotInputProvider.new()
	var const_ok := true
	for t in 5:
		var c = bp.poll(t)
		if not (c.move_dir == Vector2(0.0, 1.0) and c.look == Vector2.ZERO and c.buttons == 0 and c.tick == t):
			const_ok = false
	_check("bot_forward_constant", const_ok)
	var bp2 = BotInputProvider.new(Vector2(1.0, 0.0))
	_check("bot_custom_dir", bp2.poll(3).move_dir == Vector2(1.0, 0.0))

	# --- Integrated two-bot war along column 5 (bare spawns) ---
	var topo := SquareTopology.new(9, 20, 5.0)
	var grid := TileGrid.new(topo)
	var cap := Capture.new(grid)
	var m1 := PlayerMotion.new()
	var m2 := PlayerMotion.new()
	var b1 := BotInputProvider.new()
	var b2 := BotInputProvider.new()
	# Team 1 at (5,1) faces +Z (yaw PI) -> advances up; Team 2 at (5,20) faces -Z (yaw 0).
	var p1: Vector3 = topo.tile_to_world_center(Vector2i(5, 1))
	var p2: Vector3 = topo.tile_to_world_center(Vector2i(5, 20))
	for t in 1500:
		p1 = _advance(m1, b1.poll(t), p1, grid, TileGrid.TEAM1, PI, topo)
		p2 = _advance(m2, b2.poll(t), p2, grid, TileGrid.TEAM2, 0.0, topo)
		var presence := {}
		var t1: Vector2i = topo.world_to_tile(p1)
		var t2: Vector2i = topo.world_to_tile(p2)
		if topo.in_bounds(t1):
			presence[TileGrid.TEAM1] = t1
		if topo.in_bounds(t2):
			presence[TileGrid.TEAM2] = t2
		cap.step(presence, DT)

	var n1 := _count(grid, TileGrid.TEAM1)
	var n2 := _count(grid, TileGrid.TEAM2)
	_check("both_advanced", n1 >= 4 and n2 >= 4, "(t1=%d t2=%d)" % [n1, n2])
	_check("t1_captured_forward", grid.get_owner(Vector2i(5, 2)) == TileGrid.TEAM1 and grid.get_owner(Vector2i(5, 3)) == TileGrid.TEAM1)
	_check("t2_captured_forward", grid.get_owner(Vector2i(5, 19)) == TileGrid.TEAM2 and grid.get_owner(Vector2i(5, 18)) == TileGrid.TEAM2)
	var t1_max := _edge_row(grid, TileGrid.TEAM1, true)
	var t2_min := _edge_row(grid, TileGrid.TEAM2, false)
	_check("fronts_meet_not_cross", t1_max < t2_min, "(t1_max=%d t2_min=%d)" % [t1_max, t2_min])

## One headless tick for an actor: ramp velocity (PlayerMotion), Euler-integrate the
## horizontal move on a flat floor, then clamp to the team's walkable region (M5).
func _advance(motion, cmd, pos: Vector3, grid, team: int, yaw: float, topo) -> Vector3:
	motion.tick(cmd, DT, true, yaw)
	var to := pos + Vector3(motion.velocity.x, 0.0, motion.velocity.z) * DT
	var walkable := MR.walkable_cells(grid, team)
	var r := MR.clamp_move(pos, to, walkable, topo, MARGIN)
	return r["pos"]

func _count(grid, team: int) -> int:
	var n := 0
	for c in grid.topology.all_tiles():
		if grid.get_owner(c) == team:
			n += 1
	return n

## Highest (max=true) or lowest (max=false) owned row for a team — to check the fronts
## advanced toward center without passing through each other.
func _edge_row(grid, team: int, want_max: bool) -> int:
	var best := -1 if want_max else 9999
	for c in grid.topology.all_tiles():
		if grid.get_owner(c) == team:
			best = maxi(best, c.y) if want_max else mini(best, c.y)
	return best
