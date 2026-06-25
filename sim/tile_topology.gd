extends RefCounted
## Shape-agnostic tile topology interface.
##
## Square now; a hex impl can drop in later (only a map regeneration needed).
## Coordinates are opaque Vector2i — rules call these methods and never assume
## square geometry. Adjacency always means "shares an edge" (4 for squares, 6 for
## hexes; never diagonal). Subclasses override everything. Referenced via preload
## (no class_name) so headless runs resolve it without the editor class cache.

func tile_count() -> int:
	return 0

func all_tiles() -> Array:
	return []

func in_bounds(_coord: Vector2i) -> bool:
	return false

func world_to_tile(_pos: Vector3) -> Vector2i:
	return Vector2i(-1, -1)

func tile_to_world_center(_coord: Vector2i) -> Vector3:
	return Vector3.ZERO

## CCW boundary polygon of the cell in world XZ at y=0 (4 points for squares).
func cell_polygon(_coord: Vector2i) -> PackedVector3Array:
	return PackedVector3Array()

## Tiles sharing an edge with `coord` (never diagonal).
func edge_neighbors(_coord: Vector2i) -> Array:
	return []
