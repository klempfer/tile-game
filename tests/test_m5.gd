extends Node
## M5 self-test: walkable-region computation + the movement clamp — margin inset,
## slide along a wall, concave-corner stop, free traversal into legal neighbors,
## map-edge wall, and stranded free-roam. Pure and deterministic (no nodes, no RNG).
## Prints [TEST] lines then idles (get_debug_output only scrapes a live process).

const SquareTopology = preload("res://sim/square_topology.gd")
const TileGrid = preload("res://sim/tile_grid.gd")
const MR = preload("res://sim/movement_restriction.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m5 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m5 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _topo() -> Object:
	return SquareTopology.new(9, 20, 5.0)

func _dset(arr: Array) -> Dictionary:
	var d: Dictionary = {}
	for c in arr:
		d[c] = true
	return d

func _run_suite() -> void:
	var topo := _topo()
	var M := 0.4
	var EPS: float = MR.EPS
	var Y := 0.05

	# --- walkable_cells ---
	var g := TileGrid.new(_topo())
	var w1 := MR.walkable_cells(g, TileGrid.TEAM1)
	# Team 1 owns spawn (5,1) only -> {(5,1)} + edge-neighbors (4,1),(6,1),(5,2).
	var spawn_ok: bool = w1.size() == 4 and w1.has(Vector2i(5, 1)) and w1.has(Vector2i(4, 1)) \
		and w1.has(Vector2i(6, 1)) and w1.has(Vector2i(5, 2))
	var spawn_excl: bool = not w1.has(Vector2i(5, 3)) and not w1.has(Vector2i(3, 1)) and not w1.has(Vector2i(5, 20))
	_check("walkable_spawn_only", spawn_ok and spawn_excl, "(size=%d)" % w1.size())

	g.set_owner(Vector2i(5, 2), TileGrid.TEAM1)
	var w2 := MR.walkable_cells(g, TileGrid.TEAM1)
	# (5,2) owned now also pulls in (4,2),(6,2),(5,3).
	_check("walkable_two_owned", w2.has(Vector2i(5, 3)) and w2.has(Vector2i(4, 2)) and w2.has(Vector2i(6, 2)))

	# --- clamp geometry around cell (5,5): center (0,-27.5), x[-2.5,2.5], z[-30,-25] ---
	var ctr := Vector3(0.0, Y, -27.5)
	var iso := _dset([Vector2i(5, 5)])               # lone legal cell: walled on all 4 sides
	var hi_x: float = 2.5 - M - EPS                 # inset +X boundary
	var hi_z: float = -25.0 - M - EPS               # inset +Z boundary

	# Fully inside -> unchanged.
	var rin := MR.clamp_move(ctr, Vector3(0.5, Y, -27.5), iso, topo, M)
	_check("inside_unchanged", _vapprox(rin["pos"], Vector3(0.5, Y, -27.5)) and not rin["hit_x"] and not rin["hit_z"])

	# Straight into illegal +X neighbor -> x clamped to boundary-margin, z untouched.
	var rx := MR.clamp_move(ctr, Vector3(3.0, Y, -27.5), iso, topo, M)
	_check("wall_pos_x_margin", _approx(rx["pos"].x, hi_x) and _approx(rx["pos"].z, -27.5) and rx["hit_x"] and not rx["hit_z"], "(x=%.4f exp=%.4f)" % [rx["pos"].x, hi_x])
	_check("wall_stays_in_cell", topo.world_to_tile(rx["pos"]) == Vector2i(5, 5))

	# Slide: +X illegal but +Z neighbor (5,6) legal -> X stops, Z advances fully.
	var legal_z := _dset([Vector2i(5, 5), Vector2i(5, 6)])
	var rs := MR.clamp_move(ctr, Vector3(3.0, Y, -24.0), legal_z, topo, M)
	_check("slide_free_axis", _approx(rs["pos"].x, hi_x) and _approx(rs["pos"].z, -24.0) and rs["hit_x"] and not rs["hit_z"])

	# Concave corner: +X and +Z both illegal -> both clamped to the inset inner corner.
	var rc := MR.clamp_move(ctr, Vector3(3.0, Y, -24.0), iso, topo, M)
	_check("concave_corner", _approx(rc["pos"].x, hi_x) and _approx(rc["pos"].z, hi_z) and rc["hit_x"] and rc["hit_z"])

	# Crossing into a legal neighbor is free (this is how you traverse your territory).
	var legal_x := _dset([Vector2i(5, 5), Vector2i(6, 5)])
	var rcross := MR.clamp_move(ctr, Vector3(3.0, Y, -27.5), legal_x, topo, M)
	_check("cross_into_legal", _approx(rcross["pos"].x, 3.0) and not rcross["hit_x"])

	# Margin = 0 (center-point) -> stops at the true boundary minus EPS.
	var r0 := MR.clamp_move(ctr, Vector3(3.0, Y, -27.5), iso, topo, 0.0)
	_check("margin_zero_at_edge", _approx(r0["pos"].x, 2.5 - EPS) and r0["hit_x"])

	# Map edge is a wall. Cell (1,5): x[-22.5,-17.5]; its -X neighbor is out of bounds.
	var edge := _dset([Vector2i(1, 5)])
	var efrom := Vector3(-20.0, Y, -27.5)
	var re := MR.clamp_move(efrom, Vector3(-30.0, Y, -27.5), edge, topo, M)
	_check("map_edge_wall", _approx(re["pos"].x, -22.5 + M + EPS) and re["hit_x"])

	# Stranded: standing on an illegal cell -> no clamp at all, free roam (deeper into
	# illegal ground AND back toward legal), then the clamp re-engages once legal again.
	var in65 := Vector3(5.0, Y, -27.5)              # center of (6,5), illegal in `iso`
	var deeper := MR.clamp_move(in65, Vector3(8.0, Y, -27.5), iso, topo, M)
	_check("stranded_deeper_free", deeper["stranded"] and _vapprox(deeper["pos"], Vector3(8.0, Y, -27.5)) and not deeper["hit_x"])
	var back := MR.clamp_move(in65, Vector3(0.0, Y, -27.5), iso, topo, M)
	_check("stranded_return_free", back["stranded"] and _vapprox(back["pos"], Vector3(0.0, Y, -27.5)))
	var reeng := MR.clamp_move(ctr, Vector3(3.0, Y, -27.5), iso, topo, M)
	_check("strand_reengages", not reeng["stranded"] and reeng["hit_x"])

	# Re-entry no-pushback: after a strand you land inside the margin band of a legal
	# cell (here x=2.45 in (5,5), past the inset bound hi_x=2.099, illegal (6,5) on +X).
	# The clamp must NOT snap you inward — staying/moving inward is unchanged; only
	# pushing further toward the wall is held at your current position.
	var band := Vector3(2.45, Y, -27.5)
	var stay := MR.clamp_move(band, Vector3(2.45, Y, -27.5), iso, topo, M)
	_check("reentry_no_snap", _approx(stay["pos"].x, 2.45) and not stay["hit_x"], "(x=%.4f)" % stay["pos"].x)
	var inward := MR.clamp_move(band, Vector3(2.40, Y, -27.5), iso, topo, M)
	_check("reentry_inward_free", _approx(inward["pos"].x, 2.40) and not inward["hit_x"])
	var outward := MR.clamp_move(band, Vector3(2.49, Y, -27.5), iso, topo, M)
	_check("reentry_outward_held", _approx(outward["pos"].x, 2.45) and outward["hit_x"])

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 1e-5

func _vapprox(a: Vector3, b: Vector3) -> bool:
	return _approx(a.x, b.x) and _approx(a.y, b.y) and _approx(a.z, b.z)
