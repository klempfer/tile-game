extends Node
## M8 integration smoke test: drives the CombatDirector node-layer pipeline with scripted
## shots against a stub target and confirms hitscan + projectile hits resolve, log, and are
## gated by phase. Complements the pure test_m8 (sim math) by exercising the WIRING:
## shot dict -> CombatDirector -> Ballistics -> hit event. Deterministic (fixed seed, ADS =
## no spread); prints [TEST] lines then idles (no quit()).

const WeaponDefs = preload("res://sim/weapon_defs.gd")
const CombatDirector = preload("res://scripts/combat_director.gd")

var _results: Array = []

## Minimal stand-in for an actor: just the methods CombatDirector calls on the actors.
class StubActor extends RefCounted:
	var _team: int
	var _pos: Vector3
	var _shots: Array
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
