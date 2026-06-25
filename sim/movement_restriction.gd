extends RefCounted
## Deterministic movement restriction (M5). Pure, headlessly tested: no nodes, no
## RNG, no float-dt accumulation.
##
## A team may only stand on tiles it owns OR tiles edge-adjacent to a tile it owns
## (the "walkable region"). `clamp_move` clamps a per-tick horizontal move so the
## player's body (inset by `margin`) stays inside that region — a hard stop that
## slides along the disallowed boundary (locked design decision #5).
##
## Stranded rule: the clamp only engages when the player's CURRENT cell is legal.
## If a tile flip leaves you on an illegal cell you roam freely until you re-enter a
## legal cell, at which point the restriction re-engages (you can never *walk*
## yourself stranded — only ownership changes do). The same bypass path is where a
## future "may travel on illegal tiles" card override and the M9 stranded-DoT hook in.
##
## The clamp is purely horizontal (XZ) with no vertical limit, so it applies at any
## height — jumping into an illegal tile is blocked by the same wall as walking.
##
## Referenced via preload (no class_name) so headless CLI runs resolve it without the
## editor class cache. The axis-aligned inset is correct for SquareTopology (ships
## now); a future HexTopology would supply its own clamp — geometry stays isolated here.

const EPS := 0.001     # keeps the center strictly inside the cell after a clamp
const PROBE := 0.01    # tiny offset to sample the neighbor cell just across an edge
const BIG := 1.0e20    # "no wall on this side" sentinel for clampf

## Set of legal cells for `team`: every owned tile plus each owned tile's edge
## neighbors. Goes through topology.edge_neighbors so it is hex-ready.
static func walkable_cells(grid, team: int) -> Dictionary:
	var out: Dictionary = {}
	var topo = grid.topology
	for coord in topo.all_tiles():
		if grid.get_owner(coord) == team:
			out[coord] = true
			for n in topo.edge_neighbors(coord):
				out[n] = true
	return out

static func is_walkable(walkable: Dictionary, coord: Vector2i) -> bool:
	return walkable.has(coord)

## Clamp a one-tick horizontal move from `from` to `to` against the walkable region.
## `margin` insets the body from walls (= capsule radius for whole-body-inside; 0 for
## center-point). Returns {pos, hit_x, hit_z, stranded}. Vertical (y) is untouched.
static func clamp_move(from: Vector3, to: Vector3, walkable: Dictionary, topology, margin: float) -> Dictionary:
	var cur: Vector2i = topology.world_to_tile(from)
	# Stranded: on an illegal cell (a tile flipped under us) -> no clamp, free roam.
	if not walkable.has(cur):
		return {"pos": to, "hit_x": false, "hit_z": false, "stranded": true}

	# Axis-aligned bounds + center of the current cell from its boundary polygon.
	var poly: PackedVector3Array = topology.cell_polygon(cur)
	var min_x := poly[0].x
	var max_x := poly[0].x
	var min_z := poly[0].z
	var max_z := poly[0].z
	for p in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5

	# Wall an edge only if the cell just across it is NOT walkable (illegal or
	# out-of-bounds). A walkable neighbor is entered freely — that is how you traverse
	# your own territory. Neighbors are probed by geometry, so no col/row assumption.
	var hi_x := BIG
	var lo_x := -BIG
	var hi_z := BIG
	var lo_z := -BIG
	if not walkable.has(topology.world_to_tile(Vector3(max_x + PROBE, from.y, cz))):
		hi_x = max_x - margin - EPS
	if not walkable.has(topology.world_to_tile(Vector3(min_x - PROBE, from.y, cz))):
		lo_x = min_x + margin + EPS
	if not walkable.has(topology.world_to_tile(Vector3(cx, from.y, max_z + PROBE))):
		hi_z = max_z - margin - EPS
	if not walkable.has(topology.world_to_tile(Vector3(cx, from.y, min_z - PROBE))):
		lo_z = min_z + margin + EPS

	# Degenerate guard: margin too large for the cell (inset inverts) -> pin to center.
	if lo_x > hi_x:
		lo_x = cx
		hi_x = cx
	if lo_z > hi_z:
		lo_z = cz
		hi_z = cz

	# No-pushback: widen each bound to include the current position so the clamp can
	# stop you advancing further into a wall but NEVER shoves you back from where you
	# already are. This keeps a stranded re-entry (and a tile flipping illegal right
	# next to you) smooth: you land inside the margin band and walk inward at your own
	# pace — the normal inset re-establishes itself as you move in — instead of being
	# snapped inward the instant the cell becomes legal.
	hi_x = maxf(hi_x, from.x)
	lo_x = minf(lo_x, from.x)
	hi_z = maxf(hi_z, from.z)
	lo_z = minf(lo_z, from.z)

	var nx := clampf(to.x, lo_x, hi_x)
	var nz := clampf(to.z, lo_z, hi_z)
	var hit_x: bool = not is_equal_approx(nx, to.x)
	var hit_z: bool = not is_equal_approx(nz, to.z)
	return {"pos": Vector3(nx, to.y, nz), "hit_x": hit_x, "hit_z": hit_z, "stranded": false}
