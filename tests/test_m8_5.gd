extends Node
## M8.5 self-test: the pure aim-punch / AOP-recovery sim (sim/recoil.gd). Covers the state machine,
## constant-speed recovery that reaches the origin exactly (no overshoot), the asymmetric AOP mouse
## tracking (up/horizontal tracked, down ignored-unless-below — guaranteeing recovery never pulls up),
## spray/AOP persistence across bursts and weapon switches, determinism, and robustness at the pitch
## limit (tracking ACTUAL post-clamp reticle movement, not raw input). Prints [TEST] lines then idles
## (no quit()). Randomness only via a locally-seeded RNG; timing in integer ticks.

const WeaponDefs = preload("res://sim/weapon_defs.gd")
const Recoil = preload("res://sim/recoil.gd")

const LIM := 1.3962634   # deg_to_rad(80) — matches player.gd PITCH_LIMIT

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m8_5 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m8_5 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _rev() -> Dictionary:
	return WeaponDefs.get_def(WeaponDefs.REVOLVER)

func _run_suite() -> void:
	_test_first_impulse_kicks_up()
	_test_recovery_delay_holds()
	_test_recovery_constant_speed()
	_test_recovery_reaches_exactly()
	_test_recovery_no_overshoot()
	_test_origin_tracks_up()
	_test_origin_ignores_down_when_above()
	_test_origin_follows_down_past_aim()
	_test_horizontal_input_preserved()
	_test_refire_continues_spray()
	_test_weapon_switch_keeps_recovery()
	_test_deterministic()
	_test_idle_no_fire_zero()
	_test_bursts_resume_same_aop()
	_test_tracks_actual_not_raw()
	_test_impulse_clamped_at_limit()
	_test_aop_reachable_against_floor()
	_test_smg_recoil_accumulates()

# --- state machine / recovery ---

func _test_first_impulse_kicks_up() -> void:
	var rc := Recoil.new()
	var res := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, _rng(1), 0.0, 0.0, LIM)
	var exp_pitch := deg_to_rad(float(_rev()["recoil_pitch_deg"]))
	var ry: float = res["yaw"]
	var rp: float = res["pitch"]
	# Pattern index 0 has zero horizontal drift, so the first shot is a pure upward kick.
	_check("first_impulse_kicks_up",
		_approx(rp, exp_pitch) and _approx(ry, 0.0) and rc.state_id() == Recoil.STATE_FIRING,
		"pitch=%.5f exp=%.5f yaw=%.5f state=%s" % [rp, exp_pitch, ry, rc.state_name()])

func _test_recovery_delay_holds() -> void:
	var rc := Recoil.new()
	var rng := _rng(2)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	var y: float = a["yaw"]
	var p: float = a["pitch"]
	var moved_at := -1
	for i in 12:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		var ny: float = s["yaw"]
		var np: float = s["pitch"]
		if moved_at < 0 and not (_approx(ny, y) and _approx(np, p)):
			moved_at = i
		y = ny
		p = np
	# The aim is held for exactly RECOVERY_DELAY_TICKS non-fire ticks; recovery moves it on the next.
	_check("recovery_delay_holds", moved_at == Recoil.RECOVERY_DELAY_TICKS,
		"moved_at=%d expected=%d" % [moved_at, Recoil.RECOVERY_DELAY_TICKS])

func _test_recovery_constant_speed() -> void:
	var rc := Recoil.new()
	var rng := _rng(3)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	var y: float = a["yaw"]
	var p: float = a["pitch"]
	var step := deg_to_rad(float(_rev()["recoil_recovery_deg"])) / 60.0
	var moves: Array = []
	for i in 80:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		var ny: float = s["yaw"]
		var np: float = s["pitch"]
		var m := Vector2(ny - y, np - p).length()
		if m > 0.000001:
			moves.append(m)
		y = ny
		p = np
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	# Every recovery step is the same length (distance-independent) except the final snap (<= step).
	var ok: bool = rc.state_id() == Recoil.STATE_IDLE and moves.size() >= 1
	for j in moves.size() - 1:
		if not _approx(moves[j], step, 0.00001):
			ok = false
	if moves.size() >= 1 and float(moves[moves.size() - 1]) > step + 0.00001:
		ok = false
	_check("recovery_constant_speed", ok, "moves=%s step=%.6f" % [str(moves), step])

func _test_recovery_reaches_exactly() -> void:
	var rc := Recoil.new()
	var rng := _rng(4)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	var y: float = a["yaw"]
	var p: float = a["pitch"]
	for i in 80:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	_check("recovery_reaches_exactly",
		rc.state_id() == Recoil.STATE_IDLE and _approx(y, 0.0) and _approx(p, 0.0)
		and rc.displacement() == Vector2.ZERO,
		"y=%.6f p=%.6f D=%v" % [y, p, rc.displacement()])

func _test_recovery_no_overshoot() -> void:
	var rc := Recoil.new()
	var rng := _rng(5)
	var y := 0.0
	var p := 0.0
	for i in 3:
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	var prev_len := rc.displacement().length()
	var monotonic := true
	for i in 90:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		var ln := rc.displacement().length()
		if ln > prev_len + 0.000001:
			monotonic = false
		prev_len = ln
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	_check("recovery_no_overshoot", monotonic and rc.displacement() == Vector2.ZERO,
		"monotonic=%s final_D=%v" % [monotonic, rc.displacement()])

# --- AOP mouse tracking rules ---

func _test_origin_tracks_up() -> void:
	var rc := Recoil.new()
	var rng := _rng(6)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	var d0 := rc.displacement()
	# Not firing, upward look: aim & AOP both rise -> the displacement is unchanged (input preserved).
	var lr := Recoil.apply_look(a["yaw"], a["pitch"], Vector2(0.0, deg_to_rad(1.0)), LIM)
	rc.update(lr["delta"], false, _rev(), WeaponDefs.REVOLVER, rng, lr["yaw"], lr["pitch"], LIM)
	_check("origin_tracks_up", _approx(rc.displacement().y, d0.y),
		"D.y=%.6f d0.y=%.6f" % [rc.displacement().y, d0.y])

func _test_origin_ignores_down_when_above() -> void:
	var rc := Recoil.new()
	var rng := _rng(7)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	# Aim above the AOP (D.y > 0): a small downward look shrinks the displacement (helps recovery),
	# staying positive (AOP not yet reached).
	var lr := Recoil.apply_look(a["yaw"], a["pitch"], Vector2(0.0, -deg_to_rad(0.5)), LIM)
	rc.update(lr["delta"], false, _rev(), WeaponDefs.REVOLVER, rng, lr["yaw"], lr["pitch"], LIM)
	var expected_dy := deg_to_rad(2.0) - deg_to_rad(0.5)
	_check("origin_ignores_down_when_above",
		_approx(rc.displacement().y, expected_dy) and rc.displacement().y > 0.0,
		"D.y=%.6f exp=%.6f" % [rc.displacement().y, expected_dy])

func _test_origin_follows_down_past_aim() -> void:
	var rc := Recoil.new()
	var rng := _rng(8)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	# A large downward look would drop the aim below the AOP: the AOP follows down so D.y floors at 0
	# (never negative) -> recovery can never pull the aim upward.
	var lr := Recoil.apply_look(a["yaw"], a["pitch"], Vector2(0.0, -deg_to_rad(5.0)), LIM)
	rc.update(lr["delta"], false, _rev(), WeaponDefs.REVOLVER, rng, lr["yaw"], lr["pitch"], LIM)
	_check("origin_follows_down_past_aim",
		_approx(rc.displacement().y, 0.0) and rc.displacement().y >= 0.0,
		"D.y=%.6f" % rc.displacement().y)

func _test_horizontal_input_preserved() -> void:
	var rc := Recoil.new()
	var rng := _rng(9)
	var y := 0.0
	var p := 0.0
	for i in 2:   # two shots so the pattern gives a non-zero horizontal displacement
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	var dx0 := rc.displacement().x
	var lr := Recoil.apply_look(y, p, Vector2(deg_to_rad(10.0), 0.0), LIM)
	rc.update(lr["delta"], false, _rev(), WeaponDefs.REVOLVER, rng, lr["yaw"], lr["pitch"], LIM)
	# Horizontal input moves aim and AOP together -> D.x unchanged (only recoil moves it).
	_check("horizontal_input_preserved", _approx(rc.displacement().x, dx0) and absf(dx0) > 0.0,
		"D.x=%.6f dx0=%.6f" % [rc.displacement().x, dx0])

# --- persistence: bursts & weapon switch ---

func _test_refire_continues_spray() -> void:
	var rc := Recoil.new()
	var rng := _rng(10)
	var y := 0.0
	var p := 0.0
	for i in 3:
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	for i in 8:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	var idx_before := rc.shot_index()
	var recovering: bool = rc.state_id() == Recoil.STATE_RECOVERING
	var d_before := rc.displacement()
	rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
	# Firing again mid-recovery resumes the SAME spray (index advances, AOP not recreated).
	_check("refire_continues_spray",
		idx_before == 3 and recovering and d_before != Vector2.ZERO
		and rc.shot_index() == 4 and rc.state_id() == Recoil.STATE_FIRING,
		"idx %d->%d state=%s" % [idx_before, rc.shot_index(), rc.state_name()])

func _test_weapon_switch_keeps_recovery() -> void:
	var rc := Recoil.new()
	var rng := _rng(11)
	var bolt := WeaponDefs.get_def(WeaponDefs.BOLT)
	var y := 0.0
	var p := 0.0
	for i in 2:
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	for i in 8:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	var st_before: bool = rc.state_id() == Recoil.STATE_RECOVERING
	var d_before := rc.displacement().length()
	rc.update(Vector2.ZERO, false, bolt, WeaponDefs.BOLT, rng, y, p, LIM)
	var d_after := rc.displacement().length()
	# Switching weapons resets only the pattern index; recovery (D / state) continues uninterrupted.
	_check("weapon_switch_keeps_recovery",
		st_before and rc.shot_index() == 0 and rc.state_id() == Recoil.STATE_RECOVERING
		and d_after < d_before and d_after > 0.0,
		"idx=%d state=%s D:%.5f->%.5f" % [rc.shot_index(), rc.state_name(), d_before, d_after])

# --- determinism & no-op ---

func _test_deterministic() -> void:
	var rc1 := Recoil.new()
	var rc2 := Recoil.new()
	var rng1 := _rng(42)
	var rng2 := _rng(42)
	var y1 := 0.0
	var p1 := 0.0
	var y2 := 0.0
	var p2 := 0.0
	var ident := true
	for i in 50:
		var fired: bool = (i % 7) < 3
		var look := Vector2(deg_to_rad(0.3) * (1.0 if i % 2 == 0 else -1.0), deg_to_rad(0.2) * (1.0 if i % 3 == 0 else -1.0))
		var lr1 := Recoil.apply_look(y1, p1, look, LIM)
		var lr2 := Recoil.apply_look(y2, p2, look, LIM)
		var s1 := rc1.update(lr1["delta"], fired, _rev(), WeaponDefs.REVOLVER, rng1, lr1["yaw"], lr1["pitch"], LIM)
		var s2 := rc2.update(lr2["delta"], fired, _rev(), WeaponDefs.REVOLVER, rng2, lr2["yaw"], lr2["pitch"], LIM)
		if not (_approx(s1["yaw"], s2["yaw"], 1e-9) and _approx(s1["pitch"], s2["pitch"], 1e-9)):
			ident = false
		y1 = s1["yaw"]
		p1 = s1["pitch"]
		y2 = s2["yaw"]
		p2 = s2["pitch"]
	_check("deterministic",
		ident and rc1.displacement() == rc2.displacement() and rc1.state_id() == rc2.state_id(),
		"ident=%s D1=%v D2=%v" % [ident, rc1.displacement(), rc2.displacement()])

func _test_idle_no_fire_zero() -> void:
	var rc := Recoil.new()
	var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, _rng(13), 0.5, -0.3, LIM)
	_check("idle_no_fire_zero",
		_approx(s["yaw"], 0.5) and _approx(s["pitch"], -0.3)
		and rc.state_id() == Recoil.STATE_IDLE and rc.displacement() == Vector2.ZERO,
		"yaw=%.5f pitch=%.5f state=%s" % [s["yaw"], s["pitch"], rc.state_name()])

func _test_bursts_resume_same_aop() -> void:
	var rc := Recoil.new()
	var rng := _rng(17)
	var y := 0.0
	var p := 0.0
	for i in 2:   # burst 1
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	for i in 10:  # gap (partial recovery; AOP persists)
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	var still_active: bool = rc.state_id() != Recoil.STATE_IDLE
	for i in 2:   # burst 2 (same AOP)
		var s := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
	for i in 140:  # full idle
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	# Both bursts share one AOP born at (0,0); after full recovery the aim returns there exactly.
	_check("bursts_resume_same_aop",
		still_active and rc.state_id() == Recoil.STATE_IDLE and _approx(y, 0.0) and _approx(p, 0.0)
		and rc.displacement() == Vector2.ZERO,
		"y=%.6f p=%.6f D=%v" % [y, p, rc.displacement()])

# --- robustness at the pitch limit (track ACTUAL reticle movement) ---

func _test_tracks_actual_not_raw() -> void:
	# At the +limit, raw upward input is clamped away: apply_look reports a ZERO actual delta.
	var lr := Recoil.apply_look(0.0, LIM, Vector2(0.0, deg_to_rad(0.5)), LIM)
	_check("tracks_actual_not_raw",
		_approx(lr["delta"].y, 0.0) and _approx(lr["pitch"], LIM),
		"delta.y=%.6f pitch=%.6f" % [lr["delta"].y, lr["pitch"]])

func _test_impulse_clamped_at_limit() -> void:
	var rc := Recoil.new()
	var rng := _rng(15)
	var start_pitch := LIM - deg_to_rad(0.5)   # half a degree below the limit
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, start_pitch, LIM)
	# The 2 deg kick clamps at the limit: D is credited only by the ACTUAL 0.5 deg, so the AOP stays
	# at start_pitch and recovery returns there EXACTLY (no overshoot to limit - 2 deg).
	var clamped_ok: bool = _approx(a["pitch"], LIM) and _approx(rc.displacement().y, deg_to_rad(0.5))
	var y: float = a["yaw"]
	var p: float = a["pitch"]
	for i in 80:
		var s := rc.update(Vector2.ZERO, false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	_check("impulse_clamped_at_limit",
		clamped_ok and rc.state_id() == Recoil.STATE_IDLE and _approx(p, start_pitch),
		"clamped=%s final_p=%.5f start=%.5f" % [clamped_ok, p, start_pitch])

func _test_aop_reachable_against_floor() -> void:
	var rc := Recoil.new()
	var rng := _rng(16)
	var a := rc.update(Vector2.ZERO, true, _rev(), WeaponDefs.REVOLVER, rng, 0.0, 0.0, LIM)
	var y: float = a["yaw"]
	var p: float = a["pitch"]
	var ok := true
	for i in 80:
		var lr := Recoil.apply_look(y, p, Vector2(0.0, -deg_to_rad(1.0)), LIM)  # slam aim into the floor
		y = lr["yaw"]
		p = lr["pitch"]
		var s := rc.update(lr["delta"], false, _rev(), WeaponDefs.REVOLVER, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		# AOP = aim - displacement; it must never sit below the reachable -limit.
		if (p - rc.displacement().y) < -LIM - 0.0001:
			ok = false
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	_check("aop_reachable_against_floor",
		ok and rc.state_id() == Recoil.STATE_IDLE and rc.displacement() == Vector2.ZERO,
		"ok=%s state=%s D=%v" % [ok, rc.state_name(), rc.displacement()])

# --- SMG (M8.5 full-auto test weapon): strong recoil accumulates during sustained fire ---

func _test_smg_recoil_accumulates() -> void:
	var smg := WeaponDefs.get_def(WeaponDefs.SMG)
	var rc := Recoil.new()
	var rng := _rng(20)
	var y := 0.0
	var p := 0.0
	# Sustained full-auto: while firing, recovery never runs, so every shot's kick accumulates and
	# the displacement climbs monotonically.
	var prev_off := -1.0
	var climbs := true
	for i in 10:
		var s := rc.update(Vector2.ZERO, true, smg, WeaponDefs.SMG, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		var off := rc.displacement().length()
		if off <= prev_off:
			climbs = false
		prev_off = off
	var climbed := rc.displacement().length()
	var strong := climbed > deg_to_rad(float(smg["recoil_pitch_deg"]))   # more than one shot's kick
	# Release: recovery returns the aim to the origin exactly.
	for i in 200:
		var s := rc.update(Vector2.ZERO, false, smg, WeaponDefs.SMG, rng, y, p, LIM)
		y = s["yaw"]
		p = s["pitch"]
		if rc.state_id() == Recoil.STATE_IDLE:
			break
	_check("smg_recoil_accumulates",
		climbs and strong and rc.state_id() == Recoil.STATE_IDLE and _approx(y, 0.0) and _approx(p, 0.0)
		and rc.displacement() == Vector2.ZERO,
		"climbed=%.4f final_p=%.6f D=%v" % [climbed, p, rc.displacement()])
