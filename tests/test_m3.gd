extends Node
## M3 self-test: coordinate round-trip, adjacency, and tile-grid state — all
## deterministic, no nodes. Prints [TEST] lines then idles (stop_project to end).

const SquareTopology = preload("res://sim/square_topology.gd")
const TileGrid = preload("res://sim/tile_grid.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m3 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m3 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _run_suite() -> void:
	var topo := SquareTopology.new(9, 20, 5.0)

	_check("tile_count", topo.tile_count() == 180 and topo.all_tiles().size() == 180, "(count=%d)" % topo.tile_count())

	# Round-trip every tile center.
	var rt_ok := true
	for coord in topo.all_tiles():
		if topo.world_to_tile(topo.tile_to_world_center(coord)) != coord:
			rt_ok = false
			break
	_check("coord_roundtrip_all_180", rt_ok)

	# Specific centers (origin centered).
	_check("center_5_1", topo.tile_to_world_center(Vector2i(5, 1)).is_equal_approx(Vector3(0, 0, -47.5)), "(%v)" % topo.tile_to_world_center(Vector2i(5, 1)))
	_check("center_1_1", topo.tile_to_world_center(Vector2i(1, 1)).is_equal_approx(Vector3(-20, 0, -47.5)), "(%v)" % topo.tile_to_world_center(Vector2i(1, 1)))
	_check("center_9_20", topo.tile_to_world_center(Vector2i(9, 20)).is_equal_approx(Vector3(20, 0, 47.5)), "(%v)" % topo.tile_to_world_center(Vector2i(9, 20)))

	# Bounds.
	_check("out_of_bounds", topo.world_to_tile(Vector3(1000, 0, 0)) == Vector2i(-1, -1) and not topo.in_bounds(Vector2i(0, 1)) and not topo.in_bounds(Vector2i(10, 1)))

	# Cell polygon (square = 4 CCW corners).
	var poly := topo.cell_polygon(Vector2i(5, 1))
	_check("cell_polygon_square", poly.size() == 4 and poly[0].is_equal_approx(Vector3(-2.5, 0, -50.0)), "(%s)" % str(poly))

	# Edge-neighbor adjacency (never diagonal).
	var nc := topo.edge_neighbors(Vector2i(1, 1))
	_check("neighbors_corner", nc.size() == 2 and (Vector2i(2, 1) in nc) and (Vector2i(1, 2) in nc), "(%s)" % str(nc))
	_check("neighbors_edge", topo.edge_neighbors(Vector2i(5, 1)).size() == 3, "(%s)" % str(topo.edge_neighbors(Vector2i(5, 1))))
	_check("neighbors_interior", topo.edge_neighbors(Vector2i(5, 10)).size() == 4, "(%s)" % str(topo.edge_neighbors(Vector2i(5, 10))))
	_check("no_diagonal_neighbor", not (Vector2i(2, 2) in topo.edge_neighbors(Vector2i(1, 1))))

	# Tile grid state.
	var grid := TileGrid.new(topo)
	_check("spawn_owners", grid.get_owner(Vector2i(5, 1)) == TileGrid.TEAM1 and grid.get_owner(Vector2i(5, 20)) == TileGrid.TEAM2)
	_check("default_neutral", grid.get_owner(Vector2i(1, 1)) == TileGrid.NEUTRAL)
	_check("spawn_unloseable", grid.is_unloseable(Vector2i(5, 1)) and grid.is_unloseable(Vector2i(5, 20)) and not grid.is_unloseable(Vector2i(1, 1)))

	var ok1 := grid.set_owner(Vector2i(1, 1), TileGrid.TEAM1)
	_check("set_owner_neutral", ok1 and grid.get_owner(Vector2i(1, 1)) == TileGrid.TEAM1)
	var ok2 := grid.set_owner(Vector2i(5, 1), TileGrid.TEAM2)  # spawn = immutable
	_check("set_owner_blocked_on_spawn", (not ok2) and grid.get_owner(Vector2i(5, 1)) == TileGrid.TEAM1)

	# Deterministic build.
	var h1 := TileGrid.new(SquareTopology.new(9, 20, 5.0)).owners_hash()
	var h2 := TileGrid.new(SquareTopology.new(9, 20, 5.0)).owners_hash()
	_check("deterministic_build", h1 == h2, "(h1=%d h2=%d)" % [h1, h2])
