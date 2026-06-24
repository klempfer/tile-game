extends Node
## M2 self-test: pure camera-orbit math, look-delta sensitivity/ADS scaling, pitch
## clamp, and camera-relative movement (all deterministic, no nodes/Input). Prints
## [TEST] lines then idles (stop_project to end).

const InputCommand = preload("res://input/input_command.gd")
const PlayerMotion = preload("res://sim/player_motion.gd")
const PlayerScript = preload("res://scripts/player.gd")
const LocalInput = preload("res://input/local_input_provider.gd")

const DT := 1.0 / 60.0

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m2 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m2 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

## Horizontal velocity direction after holding forward under a given camera yaw.
func _forward_dir(yaw: float) -> Vector3:
	var m = PlayerMotion.new()
	for i in 60:
		m.tick(InputCommand.new(i, Vector2(0, 1), Vector2.ZERO, 0), DT, true, yaw)
	return Vector3(m.velocity.x, 0.0, m.velocity.z).normalized()

func _run_suite() -> void:
	# Default camera pose (yaw=0, pitch=0): looking -Z, right +X, cam behind+up+right.
	var fwd := PlayerScript.look_forward(0.0, 0.0)
	var rgt := PlayerScript.look_right(0.0)
	var cpos := PlayerScript.camera_position(Vector3.ZERO, 0.0, 0.0, 3.0, 1.6, 0.5)
	_check("cam_forward_default", fwd.distance_to(Vector3(0, 0, -1)) < 0.001, "(fwd=%v)" % fwd)
	_check("cam_right_default", rgt.distance_to(Vector3(1, 0, 0)) < 0.001, "(right=%v)" % rgt)
	_check("cam_pos_default", cpos.distance_to(Vector3(0.5, 1.6, 3.0)) < 0.001, "(cpos=%v)" % cpos)

	# Look-delta: mouse right -> turn right (negative yaw); mouse up -> look up (+pitch).
	var ld := LocalInput.look_delta(Vector2(100, 0), Vector2.ZERO, DT, false)
	_check("look_yaw_mouse_right", absf(ld.x - (-0.3)) < 1e-4, "(yaw=%.4f)" % ld.x)
	var ldp := LocalInput.look_delta(Vector2(0, -100), Vector2.ZERO, DT, false)
	_check("look_pitch_mouse_up", absf(ldp.y - 0.3) < 1e-4, "(pitch=%.4f)" % ldp.y)

	# ADS scales look sensitivity by 0.6.
	var lda := LocalInput.look_delta(Vector2(100, 0), Vector2.ZERO, DT, true)
	_check("look_ads_scaled", absf(lda.x - (-0.18)) < 1e-4, "(yaw=%.4f)" % lda.x)

	# Pitch clamp at +-80 degrees.
	var p := 0.0
	for i in 100:
		p = PlayerScript.clamp_pitch(p + 0.3)
	_check("pitch_clamped_up", absf(p - PlayerScript.PITCH_LIMIT) < 1e-5, "(p=%.5f lim=%.5f)" % [p, PlayerScript.PITCH_LIMIT])

	# Camera-relative movement: with yaw, forward follows the camera, not world -Z.
	var dir := _forward_dir(PI / 2.0)
	var expected := Vector3(0, 0, -1).rotated(Vector3.UP, PI / 2.0)
	_check("camera_relative_dir", dir.distance_to(expected) < 0.01, "(dir=%v exp=%v)" % [dir, expected])
	_check("yaw_changes_dir", dir.distance_to(Vector3(0, 0, -1)) > 0.5, "(dir=%v)" % dir)

	# Determinism: same yaw -> identical velocity.
	var a := _forward_dir(PI / 3.0)
	var b := _forward_dir(PI / 3.0)
	_check("determinism", ("%v" % a) == ("%v" % b), "(a=%v b=%v)" % [a, b])
