extends Node
## M0 self-test suite. Deterministic; prints [TEST] PASS/FAIL lines then quits so
## the Godot MCP can scrape results from debug output. Run via:
##   run_project(scene="res://tests/test_m0.tscn")

const SimWorld = preload("res://sim/world.gd")
const ScriptedInputProvider = preload("res://input/scripted_input_provider.gd")

const SEED := 12345
const STEPS := 600

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m0 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	# Stay alive so the Godot MCP can scrape this output via get_debug_output;
	# the run is ended explicitly with stop_project.
	print("[TEST] m0 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

## Deterministically run the sim for `steps` ticks under `p_seed`.
func _run(p_seed: int, steps: int) -> Dictionary:
	Rng.set_seed(p_seed)
	var cmds := ScriptedInputProvider.from_seeded(steps)
	var provider := ScriptedInputProvider.new(cmds)
	var world := SimWorld.new()
	world.reset()
	for t in steps:
		world.step(provider.poll(t))
	return {"h": world.state_hash(), "tick": world.tick, "rec": world.get_recording()}

func _run_suite() -> void:
	var a := _run(SEED, STEPS)
	var b := _run(SEED, STEPS)
	_check("determinism_same_seed", a["h"] == b["h"], "(A=%d B=%d)" % [a["h"], b["h"]])
	_check("tick_count_fixed", a["tick"] == STEPS, "(tick=%d expected=%d)" % [a["tick"], STEPS])

	var c := _run(99999, STEPS)
	_check("different_seed_differs", a["h"] != c["h"], "(seedA_hash=%d seedC_hash=%d)" % [a["h"], c["h"]])

	# Replay run A's recorded commands under the same seed -> identical end state.
	Rng.set_seed(SEED)
	var replay := ScriptedInputProvider.new(a["rec"])
	var w := SimWorld.new()
	w.reset()
	for t in STEPS:
		w.step(replay.poll(t))
	_check("replay_matches", w.state_hash() == a["h"], "(replay=%d orig=%d)" % [w.state_hash(), a["h"]])
