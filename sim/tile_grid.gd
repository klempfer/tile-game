extends RefCounted
## Tile ownership state over a TileTopology. M3 is DATA ONLY — capture timing and
## the movement restriction layer on in M4/M5. Coordinates stay opaque (Vector2i)
## and all geometry goes through the topology, so a hex swap needs no rule changes.

const SquareTopology = preload("res://sim/square_topology.gd")

enum { NEUTRAL = 0, TEAM1 = 1, TEAM2 = 2 }

var topology
var _owner: Dictionary = {}       # Vector2i -> team int
var _unloseable: Dictionary = {}  # Vector2i -> true
var spawn: Dictionary = {}        # team int -> Vector2i

func _init(p_topology = null) -> void:
	topology = p_topology if p_topology != null else SquareTopology.new(9, 20, 5.0)
	for coord in topology.all_tiles():
		_owner[coord] = NEUTRAL
	# Spawn tiles: centre column of each end row, pre-owned + un-loseable.
	var mid_col := int(ceil(topology.cols / 2.0))
	var t1 := Vector2i(mid_col, 1)
	var t2 := Vector2i(mid_col, topology.rows)
	spawn[TEAM1] = t1
	spawn[TEAM2] = t2
	_owner[t1] = TEAM1
	_owner[t2] = TEAM2
	_unloseable[t1] = true
	_unloseable[t2] = true

func get_owner(coord: Vector2i) -> int:
	return _owner.get(coord, NEUTRAL)

func is_unloseable(coord: Vector2i) -> bool:
	return _unloseable.has(coord)

## Set ownership (debug/sim). Un-loseable spawn tiles are immutable -> returns false.
func set_owner(coord: Vector2i, team: int) -> bool:
	if not _owner.has(coord):
		return false
	if _unloseable.has(coord):
		return false
	_owner[coord] = team
	return true

## Stable hash of all ownership, for determinism checks.
func owners_hash() -> int:
	var s := ""
	for coord in topology.all_tiles():
		s += "%d,%d:%d|" % [coord.x, coord.y, _owner[coord]]
	return hash(s)

## Frontier outline category for a tile: 0 neutral, 1 team1, 2 team2, 3 blend.
## A team "touches" a tile if it owns it OR owns an edge-neighbor; both -> blend.
func outline_category(coord: Vector2i) -> int:
	var t1 := get_owner(coord) == TEAM1
	var t2 := get_owner(coord) == TEAM2
	for n in topology.edge_neighbors(coord):
		var no := get_owner(n)
		if no == TEAM1:
			t1 = true
		elif no == TEAM2:
			t2 = true
	if t1 and t2:
		return 3
	if t1:
		return 1
	if t2:
		return 2
	return 0
