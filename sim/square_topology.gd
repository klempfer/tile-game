extends "res://sim/tile_topology.gd"
## Square grid topology: `cols` x `rows` tiles of `size` metres, world origin
## centred. Coord = Vector2i(col, row), 1-indexed from a corner (col 1..cols,
## row 1..rows). Default 9x20 @ 5 m = the 45 x 100 m 1v1 map.

var cols: int
var rows: int
var size: float
var _half_w: float   # half total width  (X)
var _half_l: float   # half total length (Z)

func _init(p_cols: int = 9, p_rows: int = 20, p_size: float = 5.0) -> void:
	cols = p_cols
	rows = p_rows
	size = p_size
	_half_w = cols * size * 0.5
	_half_l = rows * size * 0.5

func tile_count() -> int:
	return cols * rows

func all_tiles() -> Array:
	var out: Array = []
	for r in range(1, rows + 1):
		for c in range(1, cols + 1):
			out.append(Vector2i(c, r))
	return out

func in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 1 and coord.x <= cols and coord.y >= 1 and coord.y <= rows

func world_to_tile(pos: Vector3) -> Vector2i:
	var c := int(floor((pos.x + _half_w) / size)) + 1
	var r := int(floor((pos.z + _half_l) / size)) + 1
	var coord := Vector2i(c, r)
	return coord if in_bounds(coord) else Vector2i(-1, -1)

func tile_to_world_center(coord: Vector2i) -> Vector3:
	var x := (coord.x - 0.5) * size - _half_w
	var z := (coord.y - 0.5) * size - _half_l
	return Vector3(x, 0.0, z)

func cell_polygon(coord: Vector2i) -> PackedVector3Array:
	var ctr := tile_to_world_center(coord)
	var h := size * 0.5
	return PackedVector3Array([
		ctr + Vector3(-h, 0.0, -h),
		ctr + Vector3(h, 0.0, -h),
		ctr + Vector3(h, 0.0, h),
		ctr + Vector3(-h, 0.0, h),
	])

func edge_neighbors(coord: Vector2i) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = coord + d
		if in_bounds(n):
			out.append(n)
	return out
