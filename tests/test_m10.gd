extends Node
## M10 self-test: the pure energy / dodge / shield sims. Covers the energy pool (spend/drain/regen with
## the post-spend pause, shield-block absorb full vs partial-leak), the two-phase stun->recovery, the
## dodge kinematic burst, and the +/-45 deg shield arc. Prints [TEST] lines then idles (no quit()).
## Timing is in integer ticks; no global RNG.

const Energy = preload("res://sim/energy.gd")
const Dodge = preload("res://sim/dodge.gd")
const Shield = preload("res://sim/shield.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m10 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m10 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps

func _run_suite() -> void:
	# --- energy: basics ---
	_test_energy_fresh()
	_test_try_spend_affordable()
	_test_try_spend_unaffordable()
	_test_dodge_cost()
	_test_regen_pauses_then_resumes()
	_test_sprint_drain_to_zero_stuns()
	# --- energy: shield absorb ---
	_test_absorb_full_block()
	_test_absorb_partial_leaks_and_stuns()
	# --- energy: two-phase stun -> recovery ---
	_test_two_phase_stun_recovery()
	_test_spends_refused_outside_normal()
	_test_reset()
	_test_energy_deterministic()
	# --- energy: M10.1 per-action regen delays (parallel via max) ---
	_test_sprint_no_regen_delay()
	_test_mixed_delays_parallel()
	# --- dodge ---
	_test_dodge_start_velocity()
	_test_dodge_auto_stops()
	_test_dodge_post_roll_lock()
	_test_dodge_blocked_while_active()
	_test_dodge_zero_dir_refused()
	# --- shield: ray-vs-quad geometry (M10.1) ---
	_test_shield_blocks_head_on()
	_test_shield_blocks_vertical_aim()
	_test_shield_misses_vertical_when_level()
	_test_shield_misses_flank()
	_test_shield_misses_from_behind()
	_test_shield_finite_quad_not_infinite_cone()

# --- energy ---

func _test_energy_fresh() -> void:
	var e := Energy.new()
	_check("energy_fresh",
		_approx(e.energy, Energy.MAX) and e.can_use_energy() and not e.is_stunned(),
		"energy=%.1f normal=%s" % [e.energy, e.can_use_energy()])

func _test_try_spend_affordable() -> void:
	var e := Energy.new()
	var ok := e.try_spend(40.0)
	_check("try_spend_affordable", ok and _approx(e.energy, 160.0), "energy=%.1f ok=%s" % [e.energy, ok])

func _test_try_spend_unaffordable() -> void:
	var e := Energy.new()
	e.try_spend(180.0)              # 200 -> 20
	var ok := e.try_spend(40.0)     # can't afford 40 from 20
	_check("try_spend_unaffordable", not ok and _approx(e.energy, 20.0), "energy=%.1f ok=%s" % [e.energy, ok])

func _test_dodge_cost() -> void:
	var e := Energy.new()
	e.try_spend(Energy.DODGE_COST)
	_check("dodge_cost", _approx(e.energy, Energy.MAX - Energy.DODGE_COST), "energy=%.1f" % e.energy)

func _test_regen_pauses_then_resumes() -> void:
	var e := Energy.new()
	e.try_spend(50.0)               # 200 -> 150, pause armed (60 ticks)
	for i in 60:
		e.tick()
	var still_paused := _approx(e.energy, 150.0)   # no regen during the 1 s pause
	e.tick()                        # pause elapsed -> first regen tick
	var resumed := e.energy > 150.0
	_check("regen_pauses_then_resumes", still_paused and resumed,
		"paused=%s after=%.4f" % [still_paused, e.energy])

func _test_sprint_drain_to_zero_stuns() -> void:
	var e := Energy.new()
	var ticks := 0
	while e.can_use_energy() and ticks < 5000:
		e.drain(Energy.SPRINT_DRAIN_PER_TICK)
		ticks += 1
	# 200 / (15/60 = 0.25) = exactly 800 ticks, then stun.
	_check("sprint_drain_to_zero_stuns", e.is_stunned() and ticks == 800,
		"ticks=%d stunned=%s" % [ticks, e.is_stunned()])

func _test_absorb_full_block() -> void:
	var e := Energy.new()                       # 200 energy
	var leaked := e.absorb(26.0)                # cost 52, affordable
	_check("absorb_full_block",
		_approx(leaked, 0.0) and _approx(e.energy, 200.0 - 52.0) and e.can_use_energy(),
		"leaked=%.1f energy=%.1f" % [leaked, e.energy])

func _test_absorb_partial_leaks_and_stuns() -> void:
	var e := Energy.new()
	e.try_spend(170.0)                          # 200 -> 30
	var leaked := e.absorb(26.0)                # cost 52 > 30; blockable = 30/2 = 15, leak = 11, stun
	_check("absorb_partial_leaks_and_stuns",
		_approx(leaked, 11.0) and _approx(e.energy, 0.0) and e.is_stunned(),
		"leaked=%.2f energy=%.1f stunned=%s" % [leaked, e.energy, e.is_stunned()])

func _test_two_phase_stun_recovery() -> void:
	var e := Energy.new()
	e.try_spend(160.0)                          # 200 -> 40
	e.try_spend(40.0)                           # 40 -> 0  => stun
	var entered_stun := e.is_stunned() and _approx(e.energy, 0.0)
	for i in Energy.STUN_TICKS:
		e.tick()
	var recovering := e.is_recovering() and not e.can_use_energy() and _approx(e.energy, 0.0)
	var rec_ticks := 0
	for i in 600:
		e.tick()
		rec_ticks += 1
		if e.state_id() == Energy.STATE_NORMAL:
			break
	# 200 / (50/60) = 240 ticks (allow +1 for float landing).
	var recovered := e.can_use_energy() and _approx(e.energy, Energy.MAX) and rec_ticks >= 240 and rec_ticks <= 241
	_check("two_phase_stun_recovery", entered_stun and recovering and recovered,
		"stun=%s recover=%s rec_ticks=%d energy=%.2f" % [entered_stun, recovering, rec_ticks, e.energy])

func _test_spends_refused_outside_normal() -> void:
	var e := Energy.new()
	e.try_spend(200.0)                          # -> 0, stun
	var refused_in_stun := not e.try_spend(10.0) and not e.drain(5.0)
	for i in Energy.STUN_TICKS:
		e.tick()                                # now RECOVERING
	var refused_in_recovery := not e.try_spend(10.0) and not e.drain(5.0)
	_check("spends_refused_outside_normal", refused_in_stun and refused_in_recovery,
		"stun=%s recover=%s" % [refused_in_stun, refused_in_recovery])

func _test_reset() -> void:
	var e := Energy.new()
	e.try_spend(200.0)                          # stun
	e.reset()
	_check("reset", _approx(e.energy, Energy.MAX) and e.can_use_energy() and not e.is_stunned(),
		"energy=%.1f normal=%s" % [e.energy, e.can_use_energy()])

func _test_energy_deterministic() -> void:
	var a := Energy.new()
	var b := Energy.new()
	var ident := true
	for i in 1200:
		# Scripted mix of spends, drains, a block, and ticks — drives a full stun/recovery cycle.
		if i == 100:
			a.try_spend(190.0); b.try_spend(190.0)
		if i % 3 == 0:
			a.drain(Energy.SPRINT_DRAIN_PER_TICK); b.drain(Energy.SPRINT_DRAIN_PER_TICK)
		if i == 400:
			a.absorb(20.0); b.absorb(20.0)
		a.tick(); b.tick()
		if a.state_id() != b.state_id() or not _approx(a.energy, b.energy, 1e-9):
			ident = false
	_check("energy_deterministic", ident, "ea=%.6f eb=%.6f" % [a.energy, b.energy])

func _test_sprint_no_regen_delay() -> void:
	# Sprint's delay is 0: regen never runs on the spend tick (so you don't out-regen the drain), but
	# resumes the very next tick after you stop — no 1 s wait.
	var e := Energy.new()
	e.drain(20.0, Energy.SPRINT_REGEN_DELAY)   # sprint spend -> energy 180
	e.tick()                                   # spent-this-tick blocks regen -> still 180
	var held := _approx(e.energy, 180.0)
	e.tick()                                   # next tick, not spending -> regen resumes immediately
	var resumed := e.energy > 180.0
	_check("sprint_no_regen_delay", held and resumed, "held=%s after=%.4f" % [held, e.energy])

func _test_mixed_delays_parallel() -> void:
	# A bigger delay AFTER a smaller one takes over; a smaller delay AFTER a bigger one never shrinks it
	# (single-int max == parallel timers blocked until the latest expiry).
	var a := Energy.new()
	a.try_spend(10.0, 60)
	for i in 30:
		a.tick()                               # pause 60 -> 30
	a.try_spend(10.0, 300)                      # max(30, 300) = 300
	var big_after_small := a.regen_pause_ticks() == 300
	var b := Energy.new()
	b.try_spend(10.0, 300)
	for i in 30:
		b.tick()                               # pause 300 -> 270
	b.try_spend(10.0, 60)                       # max(270, 60) = 270 (unchanged)
	var small_after_big := b.regen_pause_ticks() == 270
	_check("mixed_delays_parallel", big_after_small and small_after_big,
		"big_after_small=%d small_after_big=%d" % [a.regen_pause_ticks(), b.regen_pause_ticks()])

# --- dodge ---

func _test_dodge_start_velocity() -> void:
	var d := Dodge.new()
	var started := d.try_start(Vector3(0, 0, -1))
	var v := d.velocity()
	_check("dodge_start_velocity",
		started and d.active() and _approx(v.z, -Dodge.DODGE_SPEED) and _approx(v.x, 0.0),
		"v=%v active=%s" % [v, d.active()])

func _test_dodge_auto_stops() -> void:
	# M11.5: the full window is the burst + the post-roll lock; active() clears only after BOTH.
	var d := Dodge.new()
	d.try_start(Vector3(1, 0, 0))
	for i in Dodge.DODGE_TICKS + Dodge.LOCK_TICKS:
		d.tick()
	_check("dodge_auto_stops", not d.active() and d.velocity() == Vector3.ZERO,
		"active=%s ticks_left=%d" % [d.active(), d.ticks_left()])

func _test_dodge_post_roll_lock() -> void:
	# M11.5: after the moving burst the roll enters a LOCK_TICKS freeze — still active() (input frozen)
	# but velocity() is zero, and a new dodge is refused. active() clears only after the full window.
	var d := Dodge.new()
	d.try_start(Vector3(1, 0, 0))
	for i in Dodge.DODGE_TICKS:
		d.tick()                                   # burst done -> now in the lock
	var locked_frozen := d.active() and d.velocity() == Vector3.ZERO
	var refused := not d.try_start(Vector3(0, 0, 1))   # can't dodge during the lock
	for i in Dodge.LOCK_TICKS:
		d.tick()
	var freed := not d.active()
	_check("dodge_post_roll_lock", locked_frozen and refused and freed,
		"locked=%s refused=%s freed=%s" % [locked_frozen, refused, freed])

func _test_dodge_blocked_while_active() -> void:
	var d := Dodge.new()
	d.try_start(Vector3(1, 0, 0))
	var second := d.try_start(Vector3(0, 0, 1))   # already rolling -> refused
	_check("dodge_blocked_while_active", not second and d.active(), "second=%s" % second)

func _test_dodge_zero_dir_refused() -> void:
	var d := Dodge.new()
	var started := d.try_start(Vector3(0, 5, 0))   # only vertical -> flattens to ~zero -> refused
	_check("dodge_zero_dir_refused", not started and not d.active(), "started=%s" % started)

# --- shield ray-vs-quad (eye at 1.6; body near origin; quad SHIELD_DIST out along the aim) ---

func _test_shield_blocks_head_on() -> void:
	# Facing -Z; enemy in front fires +Z into the chest. The path crosses the quad -> blocked.
	var blocked: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(0, 0, -1), Vector3(0, 1.0, -0.4), Vector3(0, 0, 1))
	_check("shield_blocks_head_on", blocked, "blocked=%s" % blocked)

func _test_shield_blocks_vertical_aim() -> void:
	# Aiming up 45°; a shot coming straight back down the aim line is blocked (vertical coverage works).
	var aim := Vector3(0.0, 0.70710678, -0.70710678)
	var blocked: bool = Shield.blocks(Vector3(0, 1.6, 0), aim, Vector3(0, 1.6, 0), -aim)
	_check("shield_blocks_vertical_aim", blocked, "blocked=%s" % blocked)

func _test_shield_misses_vertical_when_level() -> void:
	# Facing level (-Z); a straight-down shot is parallel to the forward quad -> not blocked.
	var blocked: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(0, 0, -1), Vector3(0, 1.8, 0), Vector3(0, -1, 0))
	_check("shield_misses_vertical_when_level", not blocked, "blocked=%s" % blocked)

func _test_shield_misses_flank() -> void:
	# Facing +X while the shot comes from -Z (the side) -> parallel to the quad -> not blocked.
	var blocked: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(1, 0, 0), Vector3(0, 1.0, -0.4), Vector3(0, 0, 1))
	_check("shield_misses_flank", not blocked, "blocked=%s" % blocked)

func _test_shield_misses_from_behind() -> void:
	# Facing -Z; shot from behind (travels -Z, hits the back). The plane is on the wrong side (s>0).
	var blocked: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(0, 0, -1), Vector3(0, 1.0, 0.4), Vector3(0, 0, -1))
	_check("shield_misses_from_behind", not blocked, "blocked=%s" % blocked)

func _test_shield_finite_quad_not_infinite_cone() -> void:
	# Two shots travelling IDENTICALLY (+Z, 0° off the aim axis) but offset laterally: one hits within the
	# quad (x=0.7 < HALF_W), one misses it (x=0.95 > HALF_W=0.8). An infinite cone blocks BOTH; the finite
	# quad blocks only the first — proving the block is the visible plane, not a cone.
	var inside: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(0, 0, -1), Vector3(0.7, 1.0, -0.4), Vector3(0, 0, 1))
	var outside: bool = Shield.blocks(Vector3(0, 1.6, 0), Vector3(0, 0, -1), Vector3(0.95, 1.0, -0.4), Vector3(0, 0, 1))
	_check("shield_finite_quad_not_infinite_cone", inside and not outside,
		"inside=%s outside=%s" % [inside, outside])
