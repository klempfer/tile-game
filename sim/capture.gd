extends RefCounted
## Deterministic tile-capture simulation over a TileGrid (M4). Driven each fixed
## tick by the teams' tile presence. Progress is counted in integer TICKS (the sim
## is fixed 60 Hz), so completion lands on exact tick boundaries with no float drift.
##
## Rules: neutral -> capture (2.5 s if the capturer owns < 5 tiles, else 5 s);
## enemy -> neutralize (always 5 s) then, if you keep standing, continues into
## capture (the 10 s enemy->yours flow); both teams present pauses/holds; leaving
## or death (absence) resets progress to 0; spawn tiles are immune.

const TileGrid = preload("res://sim/tile_grid.gd")

const COMEBACK_THRESHOLD := 5
const CAPTURE_TICKS := 300      # 5.0 s @ 60 Hz
const COMEBACK_TICKS := 150     # 2.5 s
const NEUTRALIZE_TICKS := 300   # 5.0 s

const PHASE_NONE := 0
const PHASE_CAPTURE := 1
const PHASE_NEUTRALIZE := 2

var grid
var _progress: Dictionary = {}   # coord -> int ticks
var _pteam: Dictionary = {}      # coord -> team making progress
var _pphase: Dictionary = {}     # coord -> PHASE_*

func _init(p_grid) -> void:
	grid = p_grid

func progress_team(coord: Vector2i) -> int:
	return _pteam.get(coord, 0)

func progress_phase(coord: Vector2i) -> int:
	return _pphase.get(coord, PHASE_NONE)

func progress_fraction(coord: Vector2i) -> float:
	var team: int = _pteam.get(coord, 0)
	if team == 0:
		return 0.0
	return clampf(float(_progress.get(coord, 0)) / float(_duration(_pphase[coord], team)), 0.0, 1.0)

func active_tiles() -> Array:
	return _progress.keys()

## Advance one fixed tick. presence = {TileGrid.TEAM1: Vector2i|null, TEAM2: ...}.
## Returns true if any tile changed ownership this tick. (dt is unused — one call
## is exactly one fixed tick.)
func step(presence: Dictionary, _dt: float) -> bool:
	var p1 = presence.get(TileGrid.TEAM1, null)
	var p2 = presence.get(TileGrid.TEAM2, null)

	var tiles := {}
	if p1 != null:
		tiles[p1] = true
	if p2 != null:
		tiles[p2] = true
	for c in _progress.keys():
		tiles[c] = true

	var changed := false
	for coord in tiles.keys():
		if grid.is_unloseable(coord):
			_reset(coord)
			continue
		var here1: bool = (p1 == coord)
		var here2: bool = (p2 == coord)
		if here1 and here2:
			continue  # contested -> hold progress
		if not here1 and not here2:
			_reset(coord)
			continue
		var team: int = TileGrid.TEAM1 if here1 else TileGrid.TEAM2
		var owner: int = grid.get_owner(coord)
		if owner == team:
			_reset(coord)
			continue
		var phase: int = PHASE_NEUTRALIZE if owner != TileGrid.NEUTRAL else PHASE_CAPTURE
		if _pteam.get(coord, 0) != team or _pphase.get(coord, PHASE_NONE) != phase:
			_progress[coord] = 0
			_pteam[coord] = team
			_pphase[coord] = phase
		_progress[coord] += 1
		if _progress[coord] >= _duration(phase, team):
			grid.set_owner(coord, team if phase == PHASE_CAPTURE else TileGrid.NEUTRAL)
			_reset(coord)
			changed = true
	return changed

func _reset(coord: Vector2i) -> void:
	_progress.erase(coord)
	_pteam.erase(coord)
	_pphase.erase(coord)

func _duration(phase: int, team: int) -> int:
	if phase == PHASE_NEUTRALIZE:
		return NEUTRALIZE_TICKS
	return COMEBACK_TICKS if _owned_count(team) < COMEBACK_THRESHOLD else CAPTURE_TICKS

func _owned_count(team: int) -> int:
	var n := 0
	for coord in grid.topology.all_tiles():
		if grid.get_owner(coord) == team:
			n += 1
	return n
