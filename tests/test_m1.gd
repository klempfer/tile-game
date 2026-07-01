extends Node
## M1 self-test: drives the deterministic PlayerMotion model directly (no physics
## server) with scripted commands and a flat-floor Euler integrator, asserting the
## chosen movement feel. Prints [TEST] lines then idles (stop_project to end).

const InputCommand = preload("res://input/input_command.gd")
const PlayerMotion = preload("res://sim/player_motion.gd")

const DT := 1.0 / 60.0

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m1 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m1 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _hold(n: int, move: Vector2, buttons: int = 0) -> Array:
	var out: Array = []
	for i in n:
		out.append(InputCommand.new(i, move, Vector2.ZERO, buttons))
	return out

## Simulate a flat floor at y=0: PlayerMotion updates velocity, we Euler-integrate
## position and clamp to the floor (same contract the live CharacterBody3D obeys).
func _simulate(cmds: Array) -> Dictionary:
	var m = PlayerMotion.new()
	var pos := Vector3.ZERO
	var on_floor := true
	var max_h := 0.0
	for cmd in cmds:
		m.tick(cmd, DT, on_floor)
		pos += m.velocity * DT
		if pos.y <= 0.0 and m.velocity.y <= 0.0:
			pos.y = 0.0
			on_floor = true
		else:
			on_floor = false
		max_h = max(max_h, pos.y)
	return {
		"pos": pos,
		"vel": m.velocity,
		"speed": Vector2(m.velocity.x, m.velocity.z).length(),
		"max_h": max_h,
		"on_floor": on_floor,
	}

func _run_suite() -> void:
	# Determinism: identical command stream -> identical end state.
	var a := _simulate(_hold(60, Vector2(0, 1)))
	var b := _simulate(_hold(60, Vector2(0, 1)))
	var sa := "%v|%v" % [a["pos"], a["vel"]]
	var sb := "%v|%v" % [b["pos"], b["vel"]]
	_check("determinism", sa == sb, "(a=%s b=%s)" % [sa, sb])

	# Walk speed ~5, moving in -Z (forward).
	_check("walk_speed", abs(a["speed"] - 5.0) < 0.05, "(speed=%.3f)" % a["speed"])
	_check("walk_direction_forward", a["pos"].z < -1.0 and absf(a["pos"].x) < 0.001, "(pos=%v)" % a["pos"])

	# Sprint ~8.
	var s := _simulate(_hold(60, Vector2(0, 1), InputCommand.BTN_SPRINT))
	_check("sprint_speed", abs(s["speed"] - 8.0) < 0.05, "(speed=%.3f)" % s["speed"])

	# Crouch ~2.5.
	var c := _simulate(_hold(60, Vector2(0, 1), InputCommand.BTN_CROUCH))
	_check("crouch_speed", abs(c["speed"] - 2.5) < 0.05, "(speed=%.3f)" % c["speed"])

	# M11.5: ADS slows the walk to 0.75x (~3.75).
	var aw := _simulate(_hold(60, Vector2(0, 1), InputCommand.BTN_ADS))
	_check("ads_walk_speed", abs(aw["speed"] - 3.75) < 0.05, "(speed=%.3f)" % aw["speed"])

	# M11.5: crouch + ADS stack -> 0.5 * 0.75 = 0.375x (~1.875).
	var ca := _simulate(_hold(60, Vector2(0, 1), InputCommand.BTN_CROUCH | InputCommand.BTN_ADS))
	_check("crouch_ads_speed", abs(ca["speed"] - 1.875) < 0.05, "(speed=%.3f)" % ca["speed"])

	# Jump apex ~1.2 m, then lands back on the floor.
	var jc: Array = [InputCommand.new(0, Vector2.ZERO, Vector2.ZERO, InputCommand.BTN_JUMP)]
	for i in range(1, 160):
		jc.append(InputCommand.new(i))
	var j := _simulate(jc)
	_check("jump_apex", j["max_h"] > 1.1 and j["max_h"] < 1.35, "(max_h=%.3f)" % j["max_h"])
	_check("jump_lands", j["on_floor"] and j["pos"].y < 0.001, "(y=%.4f on_floor=%s)" % [j["pos"].y, str(j["on_floor"])])

	# Holding jump must not re-jump mid-air (edge-triggered): same apex, not higher.
	var hj := _simulate(_hold(160, Vector2.ZERO, InputCommand.BTN_JUMP))
	_check("no_double_jump", hj["max_h"] < 1.35, "(max_h=%.3f)" % hj["max_h"])

	_run_air_crouch_test()

## Jump while holding crouch, then keep crouch (and forward) held through the air:
## must never be crouched while airborne, but must resume crouching after landing.
func _run_air_crouch_test() -> void:
	var m = PlayerMotion.new()
	var pos := Vector3.ZERO
	var on_floor := true
	var crouched_in_air := false
	for i in range(0, 120):
		var was_on_floor := on_floor
		var buttons := InputCommand.BTN_CROUCH
		if i == 0:
			buttons |= InputCommand.BTN_JUMP  # jump on the first tick while crouched
		m.tick(InputCommand.new(i, Vector2(0, 1), Vector2.ZERO, buttons), DT, on_floor)
		if not was_on_floor and m.crouching:
			crouched_in_air = true
		pos += m.velocity * DT
		if pos.y <= 0.0 and m.velocity.y <= 0.0:
			pos.y = 0.0
			on_floor = true
		else:
			on_floor = false
	_check("no_crouch_in_air", not crouched_in_air, "(crouched_in_air=%s)" % str(crouched_in_air))
	_check("crouch_resumes_after_landing", on_floor and m.crouching, "(on_floor=%s crouching=%s)" % [str(on_floor), str(m.crouching)])
