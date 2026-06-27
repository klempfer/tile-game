extends Node
## M7 match orchestrator. Owns the deterministic MatchState and drives the world from
## it each fixed tick: freezes/unfreezes both actors and pauses/resumes capture by
## phase, and performs the clean round reset (tiles to match-start + actors to spawn)
## on the one-shot "round_reset" event. Placed FIRST in the scene tree so it gates the
## same tick the view/actors read.
##
## M9: kills (weapon or stranded) drive scoring via each actor's `died(killer_team)` signal ->
## add_point (3 points wins a round, first to 2 rounds wins the match). Debug keys now deal damage
## to force deaths: F4 damages the bot, F5 damages the player; F6 restarts. A minimal on-screen Label
## is a placeholder readout until the real HUD (M15).

const MatchState = preload("res://sim/match_state.gd")
const DefaultBinds = preload("res://input/default_binds.gd")
const WeaponDefs = preload("res://sim/weapon_defs.gd")

@export var view_path: NodePath
@export var player_path: NodePath
@export var bot_path: NodePath
@export var hud_label_path: NodePath
@export var combat_path: NodePath          # M8 combat resolver (optional; null in m7 scene)
@export var detection_path: NodePath       # M11 detection resolver (optional; null in m7 scene)

var _state
var _view: Node
var _player: Node3D
var _bot: Node3D
var _hud: Label
var _combat: Node                          # M8: CombatDirector, gated like the view
var _detection: Node                       # M11: DetectionDirector, gated like the view
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
	_detection = get_node_or_null(detection_path)
	# Record spawn poses (the scene already places actors at match start).
	_p_pos = _player.global_position
	_p_yaw = _player.start_yaw
	_b_pos = _bot.global_position
	_b_yaw = _bot.start_yaw
	# M9: a kill (weapon or stranded) emits `died(killer_team)`; route both actors' deaths to scoring.
	# Same path the F4/F5 debug keys used in M7 — add_point already drives round/match progression.
	if _player.has_signal("died"):
		_player.connect("died", _on_actor_died)
	if _bot.has_signal("died"):
		_bot.connect("died", _on_actor_died)
	_apply_phase()  # freeze for the opening countdown
	_update_hud()

## M9: an actor died — award the round point to the killer's team. add_point() ignores non-ACTIVE
## phases and handles the round/match transitions; the next-tick _apply_phase() applies the freeze.
func _on_actor_died(killer_team: int) -> void:
	_state.add_point(killer_team)
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
	if _detection != null:
		_detection.set_active(active)

func _reset_world() -> void:
	_view.reset_world()
	_player.reset_to_spawn(_p_pos, _p_yaw)
	_bot.reset_to_spawn(_b_pos, _b_yaw)
	if _combat != null:
		_combat.reset()
	if _detection != null:
		_detection.reset()

func _unhandled_input(event: InputEvent) -> void:
	# M9: real kills now score, so the F4/F5 debug keys deal a chunk of damage instead (forces deaths
	# for playtesting without precise aim). Only during ACTIVE, crediting the killing team on death.
	if event.is_action_pressed("debug_point_team1"):
		if _state.is_active() and _bot != null and _bot.has_method("take_damage"):
			_bot.take_damage(35.0, MatchState.TEAM1)   # damage the bot -> a T1 kill
		_update_hud()
	elif event.is_action_pressed("debug_point_team2"):
		if _state.is_active() and _player != null and _player.has_method("take_damage"):
			_player.take_damage(35.0, MatchState.TEAM2) # damage the player -> a T2 kill
		_update_hud()
	elif event.is_action_pressed("debug_restart_match"):
		_state.restart()
		_reset_world()
		_apply_phase()
		_update_hud()

func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "%s   round %d\nrounds  T1 %d : %d T2\npoints  T1 %d : %d T2%s%s%s%s%s\n[F4] dmg bot  [F5] dmg self  [F6] restart" % [
		_phase_label(), _state.round_index,
		_state.round_wins[MatchState.TEAM1], _state.round_wins[MatchState.TEAM2],
		_state.points[MatchState.TEAM1], _state.points[MatchState.TEAM2],
		_winner_suffix(), _hp_line(), _energy_line(), _weapon_line(), _detection_line(),
	]

## M9 HUD line: both actors' HP + a state tag (DEAD countdown / INVULN). Empty in scenes without HP.
func _hp_line() -> String:
	if _player == null or not _player.has_method("health"):
		return ""
	var p = _player.health()
	var t1 := "%d%s" % [p.hp_int(), _hp_tag(p)]
	var t2 := "--"
	if _bot != null and _bot.has_method("health"):
		var b = _bot.health()
		t2 = "%d%s" % [b.hp_int(), _hp_tag(b)]
	return "\nhp  T1 %s : %s T2" % [t1, t2]

func _hp_tag(h) -> String:
	if h.is_dead():
		return " DEAD %.1fs" % (h.respawn_ticks() / 60.0)
	if h.is_invulnerable():
		return " INVULN"
	return ""

## M10 HUD line: both actors' energy + a state tag (STUN / RECOVER / SHIELD). Empty in scenes without it.
func _energy_line() -> String:
	if _player == null or not _player.has_method("energy"):
		return ""
	var p = _player.energy()
	var t1 := "%d%s" % [p.energy_int(), _energy_tag(p, _player)]
	var t2 := "--"
	if _bot != null and _bot.has_method("energy"):
		var b = _bot.energy()
		t2 = "%d%s" % [b.energy_int(), _energy_tag(b, _bot)]
	return "\nenergy  T1 %s : %s T2" % [t1, t2]

func _energy_tag(e, actor) -> String:
	if e.is_stunned():
		return " STUN %.1fs" % (e.stun_ticks_left() / 60.0)
	if e.is_recovering():
		return " RECOVER"
	if actor.has_method("shield_up") and actor.shield_up():
		return " SHIELD"
	return ""

## M11 HUD line: whether YOU are currently visible to the enemy (the detection indicator) + whether the
## bot is currently rendered. Empty in scenes without detection (m7), so this director stays usable there.
func _detection_line() -> String:
	if _player == null or not _player.has_method("detection"):
		return ""
	var you: String = "DETECTED" if _player.detection().detected else "hidden"
	var bot_s := "--"
	if _bot != null and _bot.has_method("detection"):
		bot_s = "visible" if _bot.detection().detected else "hidden"
	return "\ndetect  YOU %s | bot %s" % [you, bot_s]

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
	# M8.5 debug: recoil state + displacement magnitude (degrees) of the local player.
	var rcl := ""
	if _player.has_method("recoil"):
		var rc = _player.recoil()
		rcl = "\nrecoil  %s   off %.1f°" % [rc.state_name(), rad_to_deg(rc.displacement().length())]
	return "\nweapon  %s   ammo %d%s%s%s" % [wname, lo.ammo(), status, ev, rcl]

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
