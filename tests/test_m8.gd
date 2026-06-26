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
	_test_ballistics()
	_test_aim_convergence()

# --- WeaponLoadout (fire-rate / magazine / reload / switch), integer ticks ---

func _test_loadout() -> void:
	var rev := WeaponDefs.get_def(WeaponDefs.REVOLVER)
	var fire_ticks: int = rev["fire_ticks"]   # 30
	var mag: int = rev["mag"]                  # 6

	# Fire-rate gating: holding fire fires on tick 0 then every fire_ticks.
	var lo := WeaponLoadout.new()
	var fire_ticks_hit: Array = []
	for t in 3 * fire_ticks + 1:               # 91 ticks
		var r: Dictionary = lo.step(true, false, -1)
		if r["fired"]:
			fire_ticks_hit.append(t)
	_check("fire_rate_gating", fire_ticks_hit == [0, fire_ticks, 2 * fire_ticks, 3 * fire_ticks],
		str(fire_ticks_hit))

	# Magazine empties after `mag` shots; ammo hits 0 and no further fire until reload.
	var lo2 := WeaponLoadout.new()
	var fired_count := 0
	for t in (mag - 1) * fire_ticks + 1:       # exactly enough ticks for `mag` shots
		var r2: Dictionary = lo2.step(true, false, -1)
		if r2["fired"]:
			fired_count += 1
	_check("magazine_depletes", fired_count == mag and lo2.ammo() == 0,
		"fired=%d ammo=%d" % [fired_count, lo2.ammo()])

	# Empty trigger auto-starts a reload; releasing it lets the magazine refill cleanly.
	var reload_ticks: int = rev["reload_ticks"]
	var started_reload := false
	for t in fire_ticks + 1:                    # drain cooldown; empty pull triggers reload
		var r3: Dictionary = lo2.step(true, false, -1)
		if r3["reloading"]:
			started_reload = true
	for t in reload_ticks:                       # release fire and let the reload complete
		lo2.step(false, false, -1)
	_check("auto_reload_refills", started_reload and lo2.ammo() == mag and not lo2.reloading(),
		"ammo=%d" % lo2.ammo())

	# Manual reload: can't fire while reloading; magazine full after exactly reload_ticks.
	var lo3 := WeaponLoadout.new()
	lo3.step(true, false, -1)                  # fire one (ammo mag-1)
	lo3.step(false, true, -1)                  # press reload -> reloading
	var blocked_during_reload := true
	for t in reload_ticks - 1:                 # still reloading on these ticks
		var r4: Dictionary = lo3.step(true, false, -1)
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
	lo4.step(true, false, -1)                  # fire a bolt
	var bolt_mag: int = WeaponDefs.get_def(WeaponDefs.BOLT)["mag"]
	var bolt_ammo_dropped: bool = lo4.ammo() == bolt_mag - 1
	lo4.step(false, false, WeaponDefs.REVOLVER)
	var revolver_full: bool = lo4.current == WeaponDefs.REVOLVER and lo4.ammo() == mag
	_check("weapon_switch", on_bolt and bolt_ammo_dropped and revolver_full,
		"bolt_ammo=%d" % (bolt_mag - 1))

# --- Ballistics (spread, falloff, headshot, hitscan, projectile) ---

func _test_ballistics() -> void:
	var fwd := Vector3(0, 0, -1)
	var rev := WeaponDefs.get_def(WeaponDefs.REVOLVER)
	var half := deg_to_rad(rev["cone_deg"])    # 3 deg

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
