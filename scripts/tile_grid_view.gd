extends Node3D
## M4 tile world: renders the grid and drives the capture sim each fixed tick from
## the player's tile presence. Fill = owner color (blended toward the capturing
## team's color by progress); outline = frontier category (neutral / team1 / team2
## / blend) via TileGrid.outline_category. All colors come from TeamColors so they
## stay customizable. F1 toggles (col,row) debug labels (off by default).

const TileGrid = preload("res://sim/tile_grid.gd")
const SquareTopology = preload("res://sim/square_topology.gd")
const Capture = preload("res://sim/capture.gd")
const TeamColors = preload("res://sim/team_colors.gd")
const DefaultBinds = preload("res://input/default_binds.gd")

const OUTLINE_W := 0.1
const Y_OUTLINE := 0.01
const Y_FILL := 0.02
const Y_MARKER := 0.03
const Y_LABEL := 0.15
const FIXED_DT := 1.0 / 60.0

@export var player_path: NodePath
@export var bot_path: NodePath                    # M6 Team-2 actor (BotInputProvider)
@export var debug_enemy_patch := false
@export var debug_prowned: Array[Vector2i] = []        # Team-1 pre-owned tiles (M5/M6 head start)
@export var debug_prowned_team2: Array[Vector2i] = []  # Team-2 pre-owned tiles (M6 head start)
@export var overhead_cam_path: NodePath           # M6 top-down observation camera (F3 toggle)
@export var player_cam_path: NodePath             # the local player's shoulder camera

var grid
var capture
var _player: Node3D
var _bot: Node3D
var _overhead_cam: Camera3D
var _player_cam: Camera3D
var _fill_mi: Dictionary = {}     # coord -> MeshInstance3D
var _fill_mat: Dictionary = {}    # coord -> StandardMaterial3D (own, for progress blend)
var _outline_mi: Dictionary = {}  # coord -> MeshInstance3D
var _outline_mats: Array = []     # 4 shared materials indexed by category
var _labels_root: Node3D
var _prev_active: Dictionary = {}
var _start_snapshot: Dictionary = {}  # M7 match-start ownership (incl. head-starts)
var _capture_active := true            # M7: gated off during countdown / round-over

func _ready() -> void:
	DefaultBinds.ensure_default_actions()
	grid = TileGrid.new(SquareTopology.new(9, 20, 5.0))
	capture = Capture.new(grid)
	_player = get_node_or_null(player_path) as Node3D
	_bot = get_node_or_null(bot_path) as Node3D
	_overhead_cam = get_node_or_null(overhead_cam_path) as Camera3D
	_player_cam = get_node_or_null(player_cam_path) as Camera3D
	_build()
	if debug_enemy_patch:
		# Team-2 tiles near the player so neutralizing is testable before the real
		# enemy actor (M6).
		for c in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]:
			grid.set_owner(c, TileGrid.TEAM2)
	# M5/M6: pre-own head-start regions (movement-restriction feel / shorter front).
	for c in debug_prowned:
		grid.set_owner(c, TileGrid.TEAM1)
	for c in debug_prowned_team2:
		grid.set_owner(c, TileGrid.TEAM2)
	# M5/M6: restrict each actor to its team's walkable region.
	if _player != null and _player.has_method("bind_world"):
		_player.bind_world(grid, TileGrid.TEAM1)
	if _bot != null and _bot.has_method("bind_world"):
		_bot.bind_world(grid, TileGrid.TEAM2)
	_start_snapshot = grid.snapshot()  # M7: match-start ownership to restore each round
	_refresh_all()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _build() -> void:
	for i in 4:
		_outline_mats.append(_mat(TeamColors.outline_color(i)))
	var topo = grid.topology
	var s: float = topo.size
	var fs := s - 2.0 * OUTLINE_W
	_labels_root = Node3D.new()
	_labels_root.name = "Labels"
	_labels_root.visible = false
	add_child(_labels_root)
	for coord in topo.all_tiles():
		var ctr: Vector3 = topo.tile_to_world_center(coord)

		var outline := MeshInstance3D.new()
		var om := PlaneMesh.new()
		om.size = Vector2(s, s)
		outline.mesh = om
		outline.position = ctr + Vector3(0.0, Y_OUTLINE, 0.0)
		add_child(outline)
		_outline_mi[coord] = outline

		var fill := MeshInstance3D.new()
		var fm := PlaneMesh.new()
		fm.size = Vector2(fs, fs)
		fill.mesh = fm
		fill.position = ctr + Vector3(0.0, Y_FILL, 0.0)
		var fmat := _mat(TeamColors.fill_color(grid.get_owner(coord)))
		fill.material_override = fmat
		add_child(fill)
		_fill_mi[coord] = fill
		_fill_mat[coord] = fmat

		var lbl := Label3D.new()
		lbl.text = "%d,%d" % [coord.x, coord.y]
		lbl.position = ctr + Vector3(0.0, Y_LABEL, 0.0)
		lbl.pixel_size = 0.012
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		_labels_root.add_child(lbl)

	for team in [TileGrid.TEAM1, TileGrid.TEAM2]:
		var sc: Vector2i = grid.spawn[team]
		var marker := MeshInstance3D.new()
		var mm := PlaneMesh.new()
		mm.size = Vector2(1.8, 1.8)
		marker.mesh = mm
		marker.position = topo.tile_to_world_center(sc) + Vector3(0.0, Y_MARKER, 0.0)
		marker.material_override = _mat(Color(1, 1, 1, 1))
		add_child(marker)

## M11.5: an actor influences tiles only while alive. Older scenes whose actors lack health() count as alive.
func _actor_alive(actor) -> bool:
	return not actor.has_method("alive") or actor.alive()

## M7: the MatchDirector pauses capture during countdown / round-over / match-over.
func set_capture_active(v: bool) -> void:
	_capture_active = v

## M7: restore the board to match-start ownership and clear capture progress.
func reset_world() -> void:
	grid.restore(_start_snapshot)
	capture.reset()
	_prev_active.clear()
	_refresh_all()

func _physics_process(_dt: float) -> void:
	if not _capture_active:
		return
	var presence := {}
	# M11.5: a DEAD actor stops influencing tiles immediately (dropping it from presence resets its
	# in-progress capture and lets a contesting enemy resume). Scenes without health treat actors as alive.
	if _player != null and _actor_alive(_player):
		var coord: Vector2i = grid.topology.world_to_tile(_player.global_position)
		if grid.topology.in_bounds(coord):
			presence[TileGrid.TEAM1] = coord
	if _bot != null and _actor_alive(_bot):
		var bcoord: Vector2i = grid.topology.world_to_tile(_bot.global_position)
		if grid.topology.in_bounds(bcoord):
			presence[TileGrid.TEAM2] = bcoord
	var changed: bool = capture.step(presence, FIXED_DT)

	var act := {}
	for c in capture.active_tiles():
		act[c] = true
	if changed:
		_refresh_all()
	else:
		# Refresh fills that are or just stopped being captured.
		for c in _prev_active.keys():
			if not act.has(c):
				_refresh_fill(c)
		for c in act.keys():
			_refresh_fill(c)
	_prev_active = act

func _refresh_all() -> void:
	for coord in grid.topology.all_tiles():
		_refresh_fill(coord)
		_outline_mi[coord].material_override = _outline_mats[grid.outline_category(coord)]

func _refresh_fill(coord: Vector2i) -> void:
	var col := TeamColors.fill_color(grid.get_owner(coord))
	var team: int = capture.progress_team(coord)
	if team != 0:
		var target := TeamColors.fill_color(TileGrid.NEUTRAL) if capture.progress_phase(coord) == Capture.PHASE_NEUTRALIZE else TeamColors.fill_color(team)
		col = col.lerp(target, capture.progress_fraction(coord))
	_fill_mat[coord].albedo_color = col

## Set a tile's owner and refresh (debug / future sim hook).
func set_tile(coord: Vector2i, team: int) -> void:
	if grid.set_owner(coord, team):
		_refresh_all()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_labels"):
		_labels_root.visible = not _labels_root.visible
	elif event.is_action_pressed("debug_strand"):
		# M5 playtest: collapse Team 1's territory to spawn so a player out in the
		# field is left on an illegal tile -> stranded free-roam back to base.
		for coord in grid.topology.all_tiles():
			if grid.get_owner(coord) == TileGrid.TEAM1:
				grid.set_owner(coord, TileGrid.NEUTRAL)  # spawn is un-loseable -> ignored
		_refresh_all()
	elif event.is_action_pressed("debug_cam"):
		# M6: toggle the top-down observation camera <-> the player's shoulder camera.
		if _overhead_cam != null and _player_cam != null:
			if _overhead_cam.current:
				_player_cam.current = true
			else:
				_overhead_cam.current = true
