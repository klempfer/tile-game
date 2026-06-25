extends Node3D
## M3 tile grid visualization: per-tile tinted fill + outline border built FROM the
## topology's cell polygons (so a hex topology would render correctly too), colored
## by ownership state. Spawn tiles get a distinct marker. F1 toggles (col,row)
## debug labels (off by default).

const TileGrid = preload("res://sim/tile_grid.gd")
const SquareTopology = preload("res://sim/square_topology.gd")
const DefaultBinds = preload("res://input/default_binds.gd")

const OUTLINE_W := 0.1     # world-space border width
const Y_OUTLINE := 0.01
const Y_FILL := 0.02
const Y_MARKER := 0.03
const Y_LABEL := 0.15

# Neutral grey / Team1 blue / Team2 red — subtle fill tint + brighter outline.
const FILL := [Color(0.5, 0.52, 0.55), Color(0.24, 0.34, 0.62), Color(0.6, 0.3, 0.27)]
const OUTLINE := [Color(0.72, 0.74, 0.77), Color(0.3, 0.55, 1.0), Color(0.96, 0.33, 0.28)]

var grid
var _fill_mi: Dictionary = {}     # coord -> MeshInstance3D
var _outline_mi: Dictionary = {}  # coord -> MeshInstance3D
var _mats: Array = []             # [fill0,fill1,fill2, out0,out1,out2]
var _labels_root: Node3D

func _ready() -> void:
	DefaultBinds.ensure_default_actions()
	grid = TileGrid.new(SquareTopology.new(9, 20, 5.0))
	for c in FILL:
		_mats.append(_mat(c))
	for c in OUTLINE:
		_mats.append(_mat(c))
	_build()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _build() -> void:
	var topo = grid.topology
	var s: float = topo.size
	var fill_size := s - 2.0 * OUTLINE_W

	_labels_root = Node3D.new()
	_labels_root.name = "Labels"
	_labels_root.visible = false
	add_child(_labels_root)

	for coord in topo.all_tiles():
		var ctr: Vector3 = topo.tile_to_world_center(coord)

		var outline := MeshInstance3D.new()
		var omesh := PlaneMesh.new()
		omesh.size = Vector2(s, s)
		outline.mesh = omesh
		outline.position = ctr + Vector3(0.0, Y_OUTLINE, 0.0)
		add_child(outline)
		_outline_mi[coord] = outline

		var fill := MeshInstance3D.new()
		var fmesh := PlaneMesh.new()
		fmesh.size = Vector2(fill_size, fill_size)
		fill.mesh = fmesh
		fill.position = ctr + Vector3(0.0, Y_FILL, 0.0)
		add_child(fill)
		_fill_mi[coord] = fill

		var lbl := Label3D.new()
		lbl.text = "%d,%d" % [coord.x, coord.y]
		lbl.position = ctr + Vector3(0.0, Y_LABEL, 0.0)
		lbl.pixel_size = 0.012
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		_labels_root.add_child(lbl)

		_recolor(coord)

	# Distinct marker on the un-loseable spawn tiles.
	for team in [TileGrid.TEAM1, TileGrid.TEAM2]:
		var sc: Vector2i = grid.spawn[team]
		var marker := MeshInstance3D.new()
		var mm := PlaneMesh.new()
		mm.size = Vector2(1.8, 1.8)
		marker.mesh = mm
		marker.position = topo.tile_to_world_center(sc) + Vector3(0.0, Y_MARKER, 0.0)
		marker.material_override = _mat(Color(1, 1, 1, 1))
		add_child(marker)

func _recolor(coord: Vector2i) -> void:
	var st: int = grid.get_owner(coord)
	_fill_mi[coord].material_override = _mats[st]
	_outline_mi[coord].material_override = _mats[3 + st]

## Set a tile's owner and recolor (debug / future sim hook).
func set_tile(coord: Vector2i, team: int) -> void:
	if grid.set_owner(coord, team):
		_recolor(coord)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_labels"):
		_labels_root.visible = not _labels_root.visible
