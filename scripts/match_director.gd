extends Node
## M7 match orchestrator. Owns the deterministic MatchState and drives the world from
## it each fixed tick: freezes/unfreezes both actors and pauses/resumes capture by
## phase, and performs the clean round reset (tiles to match-start + actors to spawn)
## on the one-shot "round_reset" event. Placed FIRST in the scene tree so it gates the
## same tick the view/actors read.
##
## Debug input stands in for M9 kills: F4/F5 award a point to Team 1/2 (3 points wins a
## round, first to 2 rounds wins the match), F6 restarts the match. A minimal on-screen
## Label is a placeholder readout until the real HUD (M15).

const MatchState = preload("res://sim/match_state.gd")
const DefaultBinds = preload("res://input/default_binds.gd")
const WeaponDefs = preload("res://sim/weapon_defs.gd")

@export var view_path: NodePath
@export var player_path: NodePath
@export var bot_path: NodePath
@export var hud_label_path: NodePath
@export var combat_path: NodePath          # M8 combat resolver (optional; null in m7 scene)

var _state
var _view: Node
var _player: Node3D
var _bot: Node3D
var _hud: Label
var _combat: Node                          # M8: CombatDirector, gated like the view
var _p_pos: Vector3
var _p_yaw: float
var _b_pos: Vector3
var _b_yaw: float

func _ready() -> void:
	DefaultBinds.ensure_default_actions()
	_state = MatchState.new()
	_view = get_node(view_path)
	_player = get_node(player_path) as Node3D
	_bot = get_node(bot_path) as Node3D
	_hud = get_node_or_null(hud_label_path) as Label
	_combat = get_node_or_null(combat_path)
	# Record spawn poses (the scene already places actors at match start).
	_p_pos = _player.global_position
	_p_yaw = _player.start_yaw
	_b_pos = _bot.global_position
	_b_yaw = _bot.start_yaw
	_apply_phase()  # freeze for the opening countdown
	_update_hud()

func _physics_process(_dt: float) -> void:
	var ev: String = _state.tick()
	if ev == "round_reset":
		_reset_world()
	_apply_phase()
	_update_hud()

## Freeze/unfreeze actors and pause/resume capture to match the current phase.
func _apply_phase() -> void:
	var active: bool = _state.is_active()
	_player.active = active
	_bot.active = active
	_view.set_capture_active(active)
	if _combat != null:
		_combat.set_active(active)

func _reset_world() -> void:
	_view.reset_world()
	_player.reset_to_spawn(_p_pos, _p_yaw)
	_bot.reset_to_spawn(_b_pos, _b_yaw)
	if _combat != null:
		_combat.reset()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_point_team1"):
		_state.add_point(MatchState.TEAM1)
		_update_hud()
	elif event.is_action_pressed("debug_point_team2"):
		_state.add_point(MatchState.TEAM2)
		_update_hud()
	elif event.is_action_pressed("debug_restart_match"):
		_state.restart()
		_reset_world()
		_apply_phase()
		_update_hud()

func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "%s   round %d\nrounds  T1 %d : %d T2\npoints  T1 %d : %d T2%s%s\n[F4] T1 point  [F5] T2 point  [F6] restart" % [
		_phase_label(), _state.round_index,
		_state.round_wins[MatchState.TEAM1], _state.round_wins[MatchState.TEAM2],
		_state.points[MatchState.TEAM1], _state.points[MatchState.TEAM2],
		_winner_suffix(), _weapon_line(),
	]

## M8 HUD line: local player's selected weapon / ammo / reload + the latest hit. Empty
## in scenes without weapons (m7), so this director stays usable there.
func _weapon_line() -> String:
	if _player == null or not _player.has_method("loadout"):
		return ""
	var lo = _player.loadout()
	var wname: String = WeaponDefs.get_def(lo.current)["name"]
	var status: String = "  RELOADING" if lo.reloading() else ""
	var ev := ""
	if _combat != null and _combat.last_event != "":
		ev = "\nlast hit: %s" % _combat.last_event
	return "\nweapon  %s   ammo %d%s%s" % [wname, lo.ammo(), status, ev]

func _phase_label() -> String:
	match _state.phase:
		MatchState.PHASE_COUNTDOWN:
			return "COUNTDOWN %.1fs" % (_state.time_left_ticks() / 60.0)
		MatchState.PHASE_ACTIVE:
			return "ACTIVE"
		MatchState.PHASE_ROUND_OVER:
			return "ROUND OVER — T%d wins round" % _state.round_winner()
		MatchState.PHASE_MATCH_OVER:
			return "MATCH OVER"
		_:
			return "?"

func _winner_suffix() -> String:
	if _state.phase == MatchState.PHASE_MATCH_OVER:
		return "\nMATCH WINNER: TEAM %d" % _state.match_winner()
	return ""
