extends Node
## M8 self-test: the pure weapon/firing sim — the WeaponLoadout fire/ammo/reload/switch
## state machine (integer-tick) and the Ballistics shot math (spread sampling, distance
## falloff, headshot band, ray-vs-capsule hitscan, straight-line projectile). All
## deterministic: randomness only via a locally-seeded RandomNumberGenerator, timing in
## integer ticks. Prints [TEST] lines then idles (no quit()).

const WeaponDefs = preload("res://sim/weapon_defs.gd")
const WeaponLoadout = preload("res://sim/weapon_loadout.gd")
const Ballistics = preload("res://sim/ballistics.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m8 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m8 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps

func _vec_eq(a: Vector3, b: Vector3, eps := 0.0001) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps and absf(a.z - b.z) <= eps

func _run_suite() -> void:
	_test_loadout()
	_test_smg()
	_test_ballistics()
	_test_spread_states()
	_test_aim_convergence()

# --- SMG (M8.5 full-auto test weapon): 900 rpm = every 4 ticks, 30-round mag ---

func _test_smg() -> void:
	var smg := WeaponDefs.get_def(WeaponDefs.SMG)
	var fire_ticks: int = smg["fire_ticks"]   # 4 (900 rpm)
	var mag: int = smg["mag"]                  # 30

	# Fire-rate gating after selecting the SMG: fires on tick 0 then every fire_ticks.
	var lo := WeaponLoadout.new()
	lo.step(false, false, WeaponDefs.SMG)      # select SMG (no fire)
	var hits: Array = []
	for t in 3 * fire_ticks + 1:               # 13 ticks
		var r: Dictionary = lo.step(true, false, -1)
		if r["fired"]:
			hits.append(t)
	_check("smg_fire_rate", hits == [0, fire_ticks, 2 * fire_ticks, 3 * fire_ticks], str(hits))

	# The full 30-round magazine empties at that rate.
	var lo2 := WeaponLoadout.new()
	lo2.step(false, false, WeaponDefs.SMG)
	var fired_count := 0
	for t in (mag - 1) * fire_ticks + 1:
		var r2: Dictionary = lo2.step(true, false, -1)
		if r2["fired"]:
			fired_count += 1
	_check("smg_mag", fired_count == mag and lo2.ammo() == 0, "fired=%d ammo=%d" % [fired_count, lo2.ammo()])

# --- WeaponLoadout (fire-rate / magazine / reload / switch), integer ticks ---

func _test_loadout() -> void:
	var rev := WeaponDefs.get_def(WeaponDefs.REVOLVER)
	var fire_ticks: int = rev["fire_ticks"]   # 30
	var mag: int = rev["mag"]                  # 6

	# M11.5 semi-auto: HOLDING fire fires exactly once (tick 0) — no auto-repeat.
	var lo := WeaponLoadout.new()
	var held_fires: Array = []
	for t in 3 * fire_ticks + 1:
		var r: Dictionary = lo.step(true, false, -1)
		if r["fired"]:
			held_fires.append(t)
	_check("semi_one_shot_per_hold", held_fires == [0], str(held_fires))

	# M11.5 semi-auto: a fresh click (release between) fires each shot once off cooldown.
	var lo_c := WeaponLoadout.new()
	var click_fires: Array = []
	for t in 2 * fire_ticks + 1:
		var held := (t % fire_ticks) == 0      # click on 0, fire_ticks, 2*fire_ticks
		var r: Dictionary = lo_c.step(held, false, -1)
		if r["fired"]:
			click_fires.append(t)
	_check("semi_click_each_shot", click_fires == [0, fire_ticks, 2 * fire_ticks], str(click_fires))

	# M11.5 input queue: a click a few ticks early still fires the instant the cooldown clears.
	var lo_q := WeaponLoadout.new()
	lo_q.step(true, false, -1)                 # shot 0 -> cooldown
	var early := fire_ticks - 5                 # click 5 ticks before the cooldown ends
	var queue_fire := -1
	for i in 2 * fire_ticks:
		var step := i + 1
		var r: Dictionary = lo_q.step(step == early, false, -1)
		if r["fired"]:
			queue_fire = step
			break
	_check("semi_input_queue_fires_early_click", queue_fire == fire_ticks,
		"fired=%d expected=%d" % [queue_fire, fire_ticks])

	# M11.5 input queue expires: a click MORE than FIRE_QUEUE_TICKS early is dropped (no shot).
	var lo_x := WeaponLoadout.new()
	lo_x.step(true, false, -1)                 # shot 0 -> cooldown
	var too_early := fire_ticks - WeaponLoadout.FIRE_QUEUE_TICKS - 3
	var extra_fire := false
	for i in 2 * fire_ticks:
		var step := i + 1
		var r: Dictionary = lo_x.step(step == too_early, false, -1)
		if r["fired"]:
			extra_fire = true
	_check("semi_input_queue_expires", not extra_fire, "extra_fire=%s" % extra_fire)

	# M11.5 swap clears the fire queue: a queued early press doesn't carry over to the new weapon.
	var lo_s := WeaponLoadout.new()
	lo_s.step(true, false, -1)                 # fire revolver -> cooldown
	lo_s.step(false, false, -1)                # release
	lo_s.step(true, false, -1)                 # click during cooldown -> queued
	lo_s.step(false, false, WeaponDefs.BOLT)   # swap -> queue cleared
	var fired_after_swap := false
	for i in 2 * fire_ticks:
		var r: Dictionary = lo_s.step(false, false, -1)   # released; a surviving queue would fire here
		if r["fired"]:
			fired_after_swap = true
	_check("swap_clears_fire_queue", not fired_after_swap and lo_s.current == WeaponDefs.BOLT,
		"fired=%s" % fired_after_swap)

	# M11.5 holding fire THROUGH a swap doesn't auto-fire the new (semi) weapon — no rising edge.
	var lo_h := WeaponLoadout.new()
	lo_h.step(true, false, -1)                 # fire revolver (held)
	var bolt_autofired := false
	for i in WeaponDefs.get_def(WeaponDefs.BOLT)["fire_ticks"] + 5:
		var sw := WeaponDefs.BOLT if i == 0 else -1
		var r: Dictionary = lo_h.step(true, false, sw)    # HOLD fire throughout
		if int(r["weapon"]) == WeaponDefs.BOLT and r["fired"]:
			bolt_autofired = true
	_check("held_fire_through_swap_no_autofire", not bolt_autofired, "autofired=%s" % bolt_autofired)

	# Magazine empties after `mag` clicks; ammo hits 0.
	var lo2 := WeaponLoadout.new()
	var fired_count := 0
	for t in mag * fire_ticks:
		var held := (t % fire_ticks) == 0      # one click per cooldown
		var r2: Dictionary = lo2.step(held, false, -1)
		if r2["fired"]:
			fired_count += 1
	_check("magazine_depletes", fired_count == mag and lo2.ammo() == 0,
		"fired=%d ammo=%d" % [fired_count, lo2.ammo()])

	# Empty-magazine click auto-starts a reload (not a dry fire); releasing lets it refill.
	var reload_ticks: int = rev["reload_ticks"]
	lo2.step(false, false, -1)                 # release so the next click is a fresh edge
	var er: Dictionary = lo2.step(true, false, -1)   # click on empty -> auto reload
	var started_reload: bool = er["reloading"]
	for t in reload_ticks:
		lo2.step(false, false, -1)
	_check("empty_click_auto_reloads", started_reload and lo2.ammo() == mag and not lo2.reloading(),
		"ammo=%d" % lo2.ammo())

	# Manual reload: can't fire while reloading (even spamming clicks); full after exactly reload_ticks.
	var lo3 := WeaponLoadout.new()
	lo3.step(true, false, -1)                  # fire one (ammo mag-1)
	lo3.step(false, true, -1)                  # press reload -> reloading
	var blocked_during_reload := true
	for t in reload_ticks - 1:
		var held := (t % 5) == 0               # spam clicks during the reload
		var r4: Dictionary = lo3.step(held, false, -1)
		if r4["fired"]:
			blocked_during_reload = false
	var was_reloading: bool = lo3.reloading()
	var rdone: Dictionary = lo3.step(false, false, -1)  # the tick reload completes
	_check("manual_reload", blocked_during_reload and was_reloading and not rdone["reloading"]
		and lo3.ammo() == mag, "ammo=%d" % lo3.ammo())

	# Weapon switch selects the other weapon with its own ammo pool, untouched on switch back.
	var lo4 := WeaponLoadout.new()
	lo4.step(false, false, WeaponDefs.BOLT)
	var on_bolt: bool = lo4.current == WeaponDefs.BOLT
	lo4.step(true, false, -1)                  # click -> fire a bolt
	var bolt_mag: int = WeaponDefs.get_def(WeaponDefs.BOLT)["mag"]
	var bolt_ammo_dropped: bool = lo4.ammo() == bolt_mag - 1
	lo4.step(false, false, WeaponDefs.REVOLVER)
	var revolver_full: bool = lo4.current == WeaponDefs.REVOLVER and lo4.ammo() == mag
	_check("weapon_switch", on_bolt and bolt_ammo_dropped and revolver_full,
		"bolt_ammo=%d" % (bolt_mag - 1))

# --- M11.5 state-dependent spread (weapon_defs.spread_cone) ---

func _test_spread_states() -> void:
	var rev := WeaponDefs.get_def(WeaponDefs.REVOLVER)
	var hip_stand := WeaponDefs.spread_cone(rev, false, WeaponDefs.SPREAD_STAND)
	var hip_walk := WeaponDefs.spread_cone(rev, false, WeaponDefs.SPREAD_WALK)
	var hip_air := WeaponDefs.spread_cone(rev, false, WeaponDefs.SPREAD_AIR)
	var hip_crouch := WeaponDefs.spread_cone(rev, false, WeaponDefs.SPREAD_CROUCH)
	var ads_stand := WeaponDefs.spread_cone(rev, true, WeaponDefs.SPREAD_STAND)
	# Ordering: air worst, then walk, then stand, crouch-still tightest; ADS is tighter than hip.
	var ordering := hip_air > hip_walk and hip_walk > hip_stand and hip_stand > hip_crouch
	var ads_tighter := ads_stand < hip_stand
	_check("spread_states_ordering", ordering and ads_tighter,
		"air=%.2f walk=%.2f stand=%.2f crouch=%.2f ads=%.2f" % [hip_air, hip_walk, hip_stand, hip_crouch, ads_stand])

# --- Ballistics (spread, falloff, headshot, hitscan, projectile) ---

func _test_ballistics() -> void:
	var fwd := Vector3(0, 0, -1)
	var rev := WeaponDefs.get_def(WeaponDefs.REVOLVER)
	var half := deg_to_rad(WeaponDefs.spread_cone(rev, false, WeaponDefs.SPREAD_STAND))  # hip stand, 2 deg

	# Spread is reproducible: identical seed -> identical sampled direction.
	var rng_a := RandomNumberGenerator.new(); rng_a.seed = 123
	var rng_b := RandomNumberGenerator.new(); rng_b.seed = 123
	var da := Ballistics.sample_spread(fwd, half, rng_a)
	var db := Ballistics.sample_spread(fwd, half, rng_b)
	_check("spread_reproducible", _vec_eq(da, db), "%v vs %v" % [da, db])

	# ADS (half-angle 0) = no spread: returns forward exactly.
	var rng_c := RandomNumberGenerator.new(); rng_c.seed = 7
	var d_ads := Ballistics.sample_spread(fwd, 0.0, rng_c)
	_check("ads_no_spread", _vec_eq(d_ads, fwd), "%v" % d_ads)

	# Sampled direction stays inside the cone (angle from forward <= half-angle).
	var rng_d := RandomNumberGenerator.new(); rng_d.seed = 99
	var max_angle := 0.0
	for i in 200:
		var s := Ballistics.sample_spread(fwd, half, rng_d)
		max_angle = maxf(max_angle, fwd.angle_to(s))
	_check("spread_within_cone", max_angle <= half + 0.0001, "max=%.4f half=%.4f" % [max_angle, half])

	# Distance falloff: full <= 10 m, min*factor >= 30 m, linear between.
	var dmg_close := Ballistics.damage_at(rev, 5.0)
	var dmg_far := Ballistics.damage_at(rev, 30.0)
	var dmg_mid := Ballistics.damage_at(rev, 20.0)
	_check("falloff_curve", _approx(dmg_close, 26.0) and _approx(dmg_far, 26.0 * 0.4)
		and _approx(dmg_mid, 18.2), "close=%.2f far=%.2f mid=%.2f" % [dmg_close, dmg_far, dmg_mid])

	# Headshot multiplier stacks on the (falloff-adjusted) damage.
	var head_dmg := Ballistics.resolve_damage(rev, 5.0, true)
	var body_dmg := Ballistics.resolve_damage(rev, 5.0, false)
	_check("headshot_multiplier", _approx(head_dmg, 39.0) and _approx(body_dmg, 26.0),
		"head=%.2f body=%.2f" % [head_dmg, body_dmg])

	# Headshot band = top HEAD_BAND metres of the capsule (feet at foot_y, height tall).
	var hs_top: bool = Ballistics.is_headshot(1.5, 0.0, 1.8)
	var hs_chest: bool = Ballistics.is_headshot(1.0, 0.0, 1.8)
	_check("headshot_band", hs_top and not hs_chest)

	# Hitscan ray vs capsule: centered chest ray hits (body), offset ray misses.
	var cap := Vector3(0, 0, 0)            # capsule feet at origin, radius 0.4, height 1.8
	var chest := Ballistics.ray_capsule(Vector3(0, 1.0, -5), Vector3(0, 0, 1), cap, 0.4, 1.8)
	var miss := Ballistics.ray_capsule(Vector3(2.0, 1.0, -5), Vector3(0, 0, 1), cap, 0.4, 1.8)
	_check("hitscan_hit_miss", chest["hit"] and not chest_is_head(chest) and not miss["hit"],
		"chest_y=%.2f" % chest["hit_y"])

	# A ray at head height registers a headshot via the returned hit_y.
	var head := Ballistics.ray_capsule(Vector3(0, 1.6, -5), Vector3(0, 0, 1), cap, 0.4, 1.8)
	_check("hitscan_headshot", head["hit"] and Ballistics.is_headshot(head["hit_y"], 0.0, 1.8),
		"head_y=%.2f" % head["hit_y"])

	# Projectile integrates straight-line per tick and registers contact with the capsule.
	var p0 := Vector3(0, 1.0, -5)
	var vel := Vector3(0, 0, 45)
	var p1 := Ballistics.step_projectile(p0, vel)
	var moved_ok: bool = _vec_eq(p1, Vector3(0, 1.0, -5 + 45.0 / 60.0))
	var hits_at_body: bool = Ballistics.projectile_hits(Vector3(0, 1.0, 0), 0.25, cap, 0.4, 1.8)
	var misses_in_air: bool = not Ballistics.projectile_hits(Vector3(3, 1.0, 0), 0.25, cap, 0.4, 1.8)
	_check("projectile_step_hit", moved_ok and hits_at_body and misses_in_air, "%v" % p1)

func chest_is_head(hit: Dictionary) -> bool:
	return Ballistics.is_headshot(hit["hit_y"], 0.0, 1.8)

# --- Two-trace aim convergence (third-person muzzle-vs-camera parallax fix) ---

func _test_aim_convergence() -> void:
	# Enemy capsule feet at origin (radius 0.4, height 1.8). The crosshair ray (camera) runs
	# straight at chest height; the muzzle/eye sits offset to the left (the shoulder offset).
	var enemy_pos := Vector3(0, 0, 0)
	var target := {"pos": enemy_pos, "radius": 0.4, "height": 1.8}
	var cam_origin := Vector3(0, 1.0, -5)
	var cam_dir := Vector3(0, 0, 1)
	var muzzle := Vector3(-0.5, 1.0, -5)

	# The parallax bug: firing the camera direction straight from the offset muzzle MISSES.
	var naive := Ballistics.ray_capsule(muzzle, cam_dir, enemy_pos, 0.4, 1.8)
	# The fix: converge the muzzle shot onto what the crosshair covers -> HITS.
	var dir := Ballistics.aim_direction(muzzle, cam_origin, cam_dir, target, 1000.0)
	var converged := Ballistics.ray_capsule(muzzle, dir, enemy_pos, 0.4, 1.8)
	_check("aim_convergence", (not naive["hit"]) and converged["hit"],
		"naive_hit=%s converged_hit=%s" % [naive["hit"], converged["hit"]])

	# No target under the crosshair: aim ~straight down the camera ray (a normalized dir).
	var dir_far := Ballistics.aim_direction(muzzle, cam_origin, cam_dir, {}, 1000.0)
	_check("aim_no_target_forward", dir_far.z > 0.99 and _approx(dir_far.length(), 1.0),
		"%v" % dir_far)
