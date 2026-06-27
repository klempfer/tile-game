extends Node
## M11 self-test: the pure detection sim (sim/detection.gd). Covers the base-range detect, the
## no-detect-outside case, the WoWS fire-bloom (firing raises your own range to 50 m, then it expires),
## the exact bloom + linger countdowns, and determinism. Prints [TEST] lines then idles (no quit() —
## get_debug_output scrapes a LIVE process). Timing is in integer ticks; no global RNG.

const Detection = preload("res://sim/detection.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m11 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m11 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps

func _run_suite() -> void:
	_test_fresh_state()
	_test_detect_inside_base_range()
	_test_not_detected_outside_range()
	_test_on_fire_raises_range()
	_test_fire_bloom_detects_beyond_base()
	_test_no_fire_no_detect_beyond_base()
	_test_bloom_counts_down_exactly()
	_test_bloom_expires_back_to_base_range()
	_test_linger_counts_down_exactly()
	_test_deterministic()

func _test_fresh_state() -> void:
	var d := Detection.new()
	_check("fresh_state",
		not d.detected and _approx(d.effective_range(), Detection.BASE_RANGE)
		and d.bloom_ticks() == 0 and d.linger_ticks() == 0,
		"detected=%s range=%.1f" % [d.detected, d.effective_range()])

func _test_detect_inside_base_range() -> void:
	var d := Detection.new()
	d.step(Detection.BASE_RANGE - 5.0)   # an enemy within 17.5 m detects you
	_check("detect_inside_base_range",
		d.detected and d.linger_ticks() == Detection.LINGER_TICKS,
		"detected=%s linger=%d" % [d.detected, d.linger_ticks()])

func _test_not_detected_outside_range() -> void:
	var d := Detection.new()
	d.step(Detection.BASE_RANGE + 10.0)  # 27.5 m, no bloom, no prior linger
	_check("not_detected_outside_range",
		not d.detected and d.linger_ticks() == 0,
		"detected=%s linger=%d" % [d.detected, d.linger_ticks()])

func _test_on_fire_raises_range() -> void:
	var d := Detection.new()
	d.on_fire()
	_check("on_fire_raises_range",
		_approx(d.effective_range(), Detection.FIRE_RANGE) and d.bloom_ticks() == Detection.BLOOM_TICKS,
		"range=%.1f bloom=%d" % [d.effective_range(), d.bloom_ticks()])

func _test_fire_bloom_detects_beyond_base() -> void:
	# 35 m is beyond base (17.5) but within fire range (50): firing this tick reveals you.
	var d := Detection.new()
	d.on_fire()
	d.step(35.0)
	_check("fire_bloom_detects_beyond_base", d.detected, "detected=%s" % d.detected)

func _test_no_fire_no_detect_beyond_base() -> void:
	# Same 35 m, but WITHOUT firing -> base range only -> never detected (no stealth penalty unless you shoot).
	var d := Detection.new()
	d.step(35.0)
	_check("no_fire_no_detect_beyond_base", not d.detected, "detected=%s" % d.detected)

func _test_bloom_counts_down_exactly() -> void:
	# Bloomed for exactly BLOOM_TICKS steps: still bloomed at TICKS-1, expired at TICKS. Step far (100 m)
	# so detection stays off and only the bloom countdown is under test.
	var d := Detection.new()
	d.on_fire()
	for i in Detection.BLOOM_TICKS - 1:
		d.step(100.0)
	var still_bloomed := d.bloom_ticks() == 1 and _approx(d.effective_range(), Detection.FIRE_RANGE)
	d.step(100.0)
	var expired := d.bloom_ticks() == 0 and _approx(d.effective_range(), Detection.BASE_RANGE)
	_check("bloom_counts_down_exactly", still_bloomed and expired,
		"bloom@-1=%d expired_bloom=%d" % [1, d.bloom_ticks()])

func _test_bloom_expires_back_to_base_range() -> void:
	# Fire at 35 m: detected while bloomed, then once the bloom expires 35 m is out of base range, so it
	# lingers and finally goes dark. Verify the transition: detected right after firing, dark long after.
	var d := Detection.new()
	d.on_fire()
	d.step(35.0)
	var detected_on_fire := d.detected
	for i in Detection.BLOOM_TICKS + Detection.LINGER_TICKS + 5:
		d.step(35.0)
	_check("bloom_expires_back_to_base_range",
		detected_on_fire and not d.detected,
		"on_fire=%s final=%s" % [detected_on_fire, d.detected])

func _test_linger_counts_down_exactly() -> void:
	# Detected, then leave range: stay visible for exactly LINGER_TICKS more steps, dark on the next.
	var d := Detection.new()
	d.step(10.0)                         # detected, linger full
	var steps := 0
	while d.detected and steps < Detection.LINGER_TICKS + 5:
		d.step(30.0)                     # out of range -> linger ticks down
		steps += 1
	_check("linger_counts_down_exactly", steps == Detection.LINGER_TICKS,
		"steps=%d expected=%d" % [steps, Detection.LINGER_TICKS])

func _test_deterministic() -> void:
	# Two instances driven by the same scripted distance + fire sequence stay bit-identical.
	var d1 := Detection.new()
	var d2 := Detection.new()
	var ident := true
	for i in 500:
		if i == 30 or i == 200:
			d1.on_fire()
			d2.on_fire()
		var dist := 10.0 if (i % 100) < 40 else 40.0   # weave in and out of range
		d1.step(dist)
		d2.step(dist)
		if d1.detected != d2.detected or d1.bloom_ticks() != d2.bloom_ticks() \
			or d1.linger_ticks() != d2.linger_ticks():
			ident = false
	_check("deterministic", ident,
		"detected=%s/%s linger=%d/%d" % [d1.detected, d2.detected, d1.linger_ticks(), d2.linger_ticks()])
