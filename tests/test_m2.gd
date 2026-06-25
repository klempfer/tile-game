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

	# --- ADS camera behavior (Fortnite-style right shift + slider-safe zoom) ---
	var hip := PlayerScript.rig_params(0.0)
	var adsp := PlayerScript.rig_params(1.0)
	var hip_cam := PlayerScript.camera_position(Vector3.ZERO, 0.0, 0.0, hip["dist"], hip["height"], hip["shoulder"])
	var ads_cam := PlayerScript.camera_position(Vector3.ZERO, 0.0, 0.0, adsp["dist"], adsp["height"], adsp["shoulder"])
	# ADS shifts the camera to the right (yaw 0 -> +X).
	_check("ads_shifts_camera_right", ads_cam.x > hip_cam.x + 0.2, "(hip_x=%.3f ads_x=%.3f)" % [hip_cam.x, ads_cam.x])
	# Shift is purely lateral: no pull-in (z) and no vertical change (y) -> crosshair stays centered.
	_check("ads_lateral_only", absf(ads_cam.y - hip_cam.y) < 1e-5 and absf(ads_cam.z - hip_cam.z) < 1e-5, "(dy=%.4f dz=%.4f)" % [ads_cam.y - hip_cam.y, ads_cam.z - hip_cam.z])

	# Returning to hip: blend 0 geometry == hip, and FOV at blend 0 == base FOV.
	var fov0 := lerpf(75.0, PlayerScript.ads_fov_for(75.0, PlayerScript.ADS_ZOOM), 0.0)
	var hip_ok: bool = absf(hip["dist"] - PlayerScript.HIP_DIST) < 1e-6 and absf(hip["shoulder"] - PlayerScript.HIP_SHOULDER) < 1e-6
	_check("ads_returns_to_hip", hip_ok and absf(fov0 - 75.0) < 1e-6, "(dist=%.3f shoulder=%.3f fov0=%.3f)" % [hip["dist"], hip["shoulder"], fov0])

	# ADS FOV value at base 75 (~46.2 deg for 1.8x).
	var adsfov75 := PlayerScript.ads_fov_for(75.0, 1.8)
	_check("ads_fov_value", absf(adsfov75 - 46.19) < 0.3, "(ads_fov=%.2f)" % adsfov75)

	# Magnification == zoom factor for ANY base FOV (proves FOV-slider compatibility).
	var mag75 := _magnification(75.0, PlayerScript.ads_fov_for(75.0, 1.8))
	var mag100 := _magnification(100.0, PlayerScript.ads_fov_for(100.0, 1.8))
	_check("ads_zoom_slider_safe", absf(mag75 - 1.8) < 1e-3 and absf(mag100 - 1.8) < 1e-3, "(mag75=%.4f mag100=%.4f)" % [mag75, mag100])

func _magnification(base_fov: float, ads_fov: float) -> float:
	return tan(deg_to_rad(base_fov) * 0.5) / tan(deg_to_rad(ads_fov) * 0.5)
