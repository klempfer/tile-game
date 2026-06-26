extends Node
## M8/M9 integration smoke test: drives the CombatDirector node-layer pipeline with scripted
## shots against a stub target and confirms hitscan + projectile hits resolve, are gated by phase,
## and (M9) APPLY damage to the victim's HP, with a lethal hit emitting died -> MatchState scoring and
## a stranded death crediting the enemy. Complements the pure test_m8 / test_m9 (sim math) by
## exercising the WIRING: shot dict -> CombatDirector -> Ballistics -> take_damage -> died -> add_point.
## Deterministic (fixed seed, ADS = no spread); prints [TEST] lines then idles (no quit()).

const WeaponDefs = preload("res://sim/weapon_defs.gd")
const CombatDirector = preload("res://scripts/combat_director.gd")
const Health = preload("res://sim/health.gd")

var _results: Array = []

## Minimal stand-in for an actor: just the methods CombatDirector calls on the actors. M9 adds the
## HP surface (take_damage + health) and a `died` signal so the combat->HP->death->score wiring is
## exercised through the node layer the same way the real player.gd is.
class StubActor extends RefCounted:
	signal died(killer_team)
	var _team: int
	var _pos: Vector3
	var _shots: Array
	var hp = Health.new()
	func _init(t: int, pos: Vector3, shots: Array) -> void:
		_team = t
		_pos = pos
		_shots = shots
	func team_id() -> int:
		return _team
	func hitbox() -> Dictionary:
		return {"pos": _pos, "radius": 0.4, "height": 1.8}
	func consume_shots() -> Array:
		var s := _shots
		_shots = []
		return s
	func take_damage(amount: float, attacker_team: int) -> void:
		if hp.take_damage(amount):
			died.emit(attacker_team)
	func health():
		return hp

func _ready() -> void:
	Rng.set_seed(12345)
	_run()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m8int RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m8int idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _run() -> void:
	var combat = CombatDirector.new()   # not added to the tree: we tick it by hand
	var target := StubActor.new(2, Vector3(0, 0, 0), [])
	var hitscan_shot := {
		"weapon": WeaponDefs.REVOLVER, "muzzle": Vector3(0, 1.6, -5),
		"cam_origin": Vector3(0, 1.6, -5), "cam_dir": Vector3(0, 0, 1),
		"ads": true, "team": 1, "tick": 0,
	}
	var proj_shot := {
		"weapon": WeaponDefs.BOLT, "muzzle": Vector3(0, 0.9, -5),
		"cam_origin": Vector3(0, 0.9, -5), "cam_dir": Vector3(0, 0, 1),
		"ads": true, "team": 1, "tick": 0,
	}
	var shooter := StubActor.new(1, Vector3(0, 0, -5), [hitscan_shot, proj_shot])
	combat._actors = [shooter, target]
	combat.set_active(true)

	# Tick 1: both shots consumed. Hitscan resolves immediately (a headshot at this aim).
	combat._physics_process(0.0)
	_check("hitscan_resolves", combat.last_event.contains("Revolver") and combat.last_event.contains("HEAD"),
		combat.last_event)

	# The bolt is now in flight; step until it reaches the target (~6 ticks for 5 m @ 45 m/s).
	var bolt_ok := false
	for i in 30:
		combat._physics_process(0.0)
		if combat.last_event.contains("Bolt"):
			bolt_ok = true
			break
	_check("projectile_resolves", bolt_ok, combat.last_event)

	# Two-trace convergence: a laterally-offset muzzle still hits what the crosshair (the
	# camera ray) covers — the third-person parallax fix, exercised through the node layer.
	combat.reset()
	combat.set_active(true)
	var converge_shot := {
		"weapon": WeaponDefs.REVOLVER, "muzzle": Vector3(-0.5, 1.0, -5),
		"cam_origin": Vector3(0, 1.0, -5), "cam_dir": Vector3(0, 0, 1),
		"ads": true, "team": 1, "tick": 0,
	}
	var s3 := StubActor.new(1, Vector3(0, 0, -5), [converge_shot])
	combat._actors = [s3, target]
	combat._physics_process(0.0)
	_check("offset_muzzle_converges", combat.last_event.contains("Revolver"), combat.last_event)

	# A projectile that MISSES does not live forever: after proj_life_ticks it despawns
	# (its node is queue_free()d and its entry dropped from the sim list).
	combat.reset()
	combat.set_active(true)
	var miss_shot := {
		"weapon": WeaponDefs.BOLT, "muzzle": Vector3(0, 1.0, -5),
		"cam_origin": Vector3(0, 1.0, -5), "cam_dir": Vector3(0, 0, 1),
		"ads": true, "team": 1, "tick": 0,
	}
	var lone := StubActor.new(1, Vector3(0, 0, -5), [miss_shot])   # no enemy: nothing to hit
	combat._actors = [lone]
	combat._physics_process(0.0)                                   # launch (and step once)
	var in_flight: bool = combat._projectiles.size() == 1
	var life: int = WeaponDefs.get_def(WeaponDefs.BOLT)["proj_life_ticks"]
	for i in life + 2:
		combat._physics_process(0.0)
	_check("projectile_despawns_on_miss", in_flight and combat._projectiles.is_empty()
		and combat.last_event == "", "in_flight=%s remaining=%d" % [in_flight, combat._projectiles.size()])

	# Phase gate: while inactive, shots are not consumed/resolved.
	combat.reset()
	combat.set_active(false)
	var s2 := StubActor.new(1, Vector3(0, 0, -5), [hitscan_shot.duplicate()])
	combat._actors = [s2, target]
	combat._physics_process(0.0)
	_check("inactive_no_resolve", combat.last_event == "", combat.last_event)

	# Muzzle (bullet origin) tracks the crouch: a real player instance, crouched/uncrouched, moves its
	# $Muzzle marker down/up with the stance instead of leaving it pinned at standing eye height.
	var PlayerScene := preload("res://scenes/player.tscn")
	var p = PlayerScene.instantiate()
	p.is_local = false   # bot: no mouse capture / camera grab in a headless test
	add_child(p)
	var stand_muzzle: float = p._muzzle_origin().y - p.global_position.y
	p._apply_crouch(true)
	var crouch_muzzle: float = p._muzzle_origin().y - p.global_position.y
	p._apply_crouch(false)
	var restand_muzzle: float = p._muzzle_origin().y - p.global_position.y
	p.queue_free()
	# Standing eye = 1.6; crouched drops by (STAND-CROUCH) = 0.6 -> 1.0; uncrouch restores 1.6.
	_check("muzzle_follows_crouch",
		is_equal_approx(stand_muzzle, 1.6) and is_equal_approx(crouch_muzzle, 1.0)
		and crouch_muzzle < stand_muzzle and is_equal_approx(restand_muzzle, 1.6),
		"stand=%.2f crouch=%.2f restand=%.2f" % [stand_muzzle, crouch_muzzle, restand_muzzle])

	# Crouch lowers the shot's convergence pivot (cam_origin) by CROUCH_CAM_DROP, identical to the
	# rendered camera height — this is what keeps aim convergence correct while crouched. The recoil
	# AOP is untouched (crouch is a camera translation, not an aim-angle change).
	var pc = PlayerScene.instantiate()
	pc.is_local = false
	add_child(pc)
	pc._queue_shot(WeaponDefs.REVOLVER, false)
	var stand_cam: float = pc.consume_shots()[0]["cam_origin"].y - pc.global_position.y
	pc._crouch_blend = 1.0   # fully crouched
	pc._queue_shot(WeaponDefs.REVOLVER, false)
	var crouch_cam: float = pc.consume_shots()[0]["cam_origin"].y - pc.global_position.y
	pc.queue_free()
	# Standing cam pivot = HIP_HEIGHT (1.6); crouched drops by CROUCH_CAM_DROP (0.6) -> 1.0.
	_check("crouch_lowers_cam_origin",
		is_equal_approx(stand_cam, 1.6) and is_equal_approx(crouch_cam, 1.0) and crouch_cam < stand_cam,
		"stand=%.2f crouch=%.2f" % [stand_cam, crouch_cam])

	# M9: a hit now SUBTRACTS HP from the victim (log-only in M8). One revolver body shot = 26 dmg.
	combat.reset()
	combat.set_active(true)
	var dmg_target := StubActor.new(2, Vector3(0, 0, 0), [])
	var body_shot := {
		"weapon": WeaponDefs.REVOLVER, "muzzle": Vector3(0, 0.9, -5),
		"cam_origin": Vector3(0, 0.9, -5), "cam_dir": Vector3(0, 0, 1),
		"ads": true, "team": 1, "tick": 0,
	}
	var dmg_shooter := StubActor.new(1, Vector3(0, 0, -5), [body_shot])
	combat._actors = [dmg_shooter, dmg_target]
	combat._physics_process(0.0)
	_check("combat_applies_damage",
		is_equal_approx(dmg_target.health().hp, Health.MAX_HP - 26.0) and dmg_target.health().alive,
		"hp=%.1f alive=%s" % [dmg_target.health().hp, dmg_target.health().alive])

	# M9: a LETHAL hit emits died(killer_team), and a connected MatchState awards that team the point.
	var MatchState := preload("res://sim/match_state.gd")
	var ms = MatchState.new()
	ms.phase = MatchState.PHASE_ACTIVE   # add_point only counts while ACTIVE
	combat.reset()
	combat.set_active(true)
	var kill_target := StubActor.new(2, Vector3(0, 0, 0), [])
	kill_target.died.connect(ms.add_point)
	# Four revolver body shots in one tick (4 x 26 = 104 > 100) -> the 4th kills.
	var volley: Array = []
	for i in 4:
		volley.append(body_shot.duplicate())
	var kill_shooter := StubActor.new(1, Vector3(0, 0, -5), volley)
	combat._actors = [kill_shooter, kill_target]
	combat._physics_process(0.0)
	_check("lethal_hit_scores_via_matchstate",
		kill_target.health().is_dead() and ms.points[MatchState.TEAM1] == 1,
		"dead=%s T1pts=%d" % [kill_target.health().is_dead(), ms.points[MatchState.TEAM1]])

	# M9: a STRANDED death (tile flipped out from under you) credits the ENEMY team. Drive the real
	# player's restriction path on a grid where team 1 owns nothing near the player's cell.
	var TileGrid := preload("res://sim/tile_grid.gd")
	var grid = TileGrid.new()                 # team 1 owns only spawn (5,1) + neighbours
	var sp = PlayerScene.instantiate()
	sp.is_local = false
	add_child(sp)
	sp.bind_world(grid, 1)
	sp.global_position = Vector3.ZERO          # map centre — far from team-1 territory -> stranded
	var stranded_killer := [-1]
	sp.died.connect(func(team): stranded_killer[0] = team)
	for i in 200:                              # ~180 ticks of DoT then death
		sp._apply_tile_restriction(sp.global_position)
		if sp.health().is_dead():
			break
	sp.queue_free()
	_check("stranded_death_credits_enemy",
		stranded_killer[0] == 2,
		"killer_team=%d" % stranded_killer[0])
