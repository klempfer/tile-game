extends Node
## M9 self-test: the pure health / death / respawn sim (sim/health.gd). Covers damage + lethal
## detection, invulnerability (blocks damage, counts down, broken by firing), the respawn countdown +
## respawn restoring full HP & invuln, the stranded damage-over-time killing in ~3 s, and determinism.
## Prints [TEST] lines then idles (no quit() — get_debug_output scrapes a LIVE process). Timing is in
## integer ticks; no global RNG.

const Health = preload("res://sim/health.gd")

var _results: Array = []

func _ready() -> void:
	_run_suite()
	var failed := 0
	for r in _results:
		print("[TEST] %s: %s %s" % [r["name"], ("PASS" if r["ok"] else "FAIL"), r["detail"]])
		if not r["ok"]:
			failed += 1
	print("[TEST] SUITE m9 RESULT passed=%d failed=%d" % [_results.size() - failed, failed])
	print("[TEST] m9 idle — stop_project to end.")

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	_results.append({"name": test_name, "ok": ok, "detail": detail})

func _approx(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps

func _run_suite() -> void:
	_test_fresh_state()
	_test_damage_reduces_hp()
	_test_lethal_hit_kills_and_arms_respawn()
	_test_no_damage_while_dead()
	_test_invuln_blocks_damage()
	_test_on_fire_breaks_invuln()
	_test_invuln_counts_down_exactly()
	_test_respawn_event_at_exactly_respawn_ticks()
	_test_respawn_restores_full_hp_and_invuln()
	_test_timers_only_advance_on_tick()
	_test_stranded_dot_kills_near_3s()
	_test_hp_int_rounds()
	_test_deterministic()

func _test_fresh_state() -> void:
	var h := Health.new()
	_check("fresh_state",
		_approx(h.hp, Health.MAX_HP) and h.alive and not h.is_dead() and not h.is_invulnerable(),
		"hp=%.1f alive=%s invuln=%s" % [h.hp, h.alive, h.is_invulnerable()])

func _test_damage_reduces_hp() -> void:
	var h := Health.new()
	var killed := h.take_damage(26.0)
	_check("damage_reduces_hp",
		not killed and _approx(h.hp, 74.0) and h.alive,
		"hp=%.1f killed=%s" % [h.hp, killed])

func _test_lethal_hit_kills_and_arms_respawn() -> void:
	var h := Health.new()
	h.take_damage(60.0)
	var killed := h.take_damage(60.0)   # 120 total > 100
	_check("lethal_hit_kills_and_arms_respawn",
		killed and h.is_dead() and _approx(h.hp, 0.0) and h.respawn_ticks() == Health.RESPAWN_TICKS,
		"killed=%s dead=%s hp=%.1f respawn=%d" % [killed, h.is_dead(), h.hp, h.respawn_ticks()])

func _test_no_damage_while_dead() -> void:
	var h := Health.new()
	h.take_damage(200.0)                # dead
	var killed_again := h.take_damage(50.0)
	_check("no_damage_while_dead",
		not killed_again and h.is_dead() and _approx(h.hp, 0.0),
		"killed_again=%s hp=%.1f" % [killed_again, h.hp])

func _test_invuln_blocks_damage() -> void:
	var h := Health.new()
	h.respawn()                         # full HP + invuln
	var killed := h.take_damage(50.0)
	_check("invuln_blocks_damage",
		not killed and _approx(h.hp, Health.MAX_HP) and h.is_invulnerable(),
		"hp=%.1f invuln=%s" % [h.hp, h.is_invulnerable()])

func _test_on_fire_breaks_invuln() -> void:
	var h := Health.new()
	h.respawn()
	h.on_fire()
	var took := h.take_damage(40.0)
	_check("on_fire_breaks_invuln",
		not h.is_invulnerable() and not took and _approx(h.hp, 60.0),
		"invuln=%s hp=%.1f" % [h.is_invulnerable(), h.hp])

func _test_invuln_counts_down_exactly() -> void:
	var h := Health.new()
	h.respawn()
	# Invulnerable for exactly INVULN_TICKS active ticks: still on at TICKS-1, off at TICKS.
	for i in Health.INVULN_TICKS - 1:
		h.tick()
	var still_on := h.is_invulnerable()
	h.tick()
	var off_after := not h.is_invulnerable()
	_check("invuln_counts_down_exactly", still_on and off_after,
		"on@%d=%s off@%d=%s" % [Health.INVULN_TICKS - 1, still_on, Health.INVULN_TICKS, off_after])

func _test_respawn_event_at_exactly_respawn_ticks() -> void:
	var h := Health.new()
	h.take_damage(200.0)                # dead, respawn timer armed
	var event_tick := -1
	for i in Health.RESPAWN_TICKS + 5:
		if h.tick() == "respawn":
			event_tick = i + 1           # 1-indexed tick count
			break
	_check("respawn_event_at_exactly_respawn_ticks", event_tick == Health.RESPAWN_TICKS,
		"event_tick=%d expected=%d" % [event_tick, Health.RESPAWN_TICKS])

func _test_respawn_restores_full_hp_and_invuln() -> void:
	var h := Health.new()
	h.take_damage(200.0)
	h.respawn()
	_check("respawn_restores_full_hp_and_invuln",
		h.alive and _approx(h.hp, Health.MAX_HP) and h.is_invulnerable() and h.respawn_ticks() == 0,
		"hp=%.1f invuln=%s alive=%s" % [h.hp, h.is_invulnerable(), h.alive])

func _test_timers_only_advance_on_tick() -> void:
	# Without tick(), a dead actor never auto-respawns and an invuln actor stays protected.
	var dead := Health.new()
	dead.take_damage(200.0)
	var still_dead := dead.is_dead() and dead.respawn_ticks() == Health.RESPAWN_TICKS
	var inv := Health.new()
	inv.respawn()
	var still_inv := inv.invuln_ticks() == Health.INVULN_TICKS
	_check("timers_only_advance_on_tick", still_dead and still_inv,
		"dead_respawn=%d inv=%d" % [dead.respawn_ticks(), inv.invuln_ticks()])

func _test_stranded_dot_kills_near_3s() -> void:
	# Standing on a flipped tile drains HP at STRANDED_DOT_PER_TICK; a full bar dies in ~180 ticks (3 s).
	var h := Health.new()
	var death_tick := -1
	for i in 200:
		if h.take_damage(Health.STRANDED_DOT_PER_TICK):
			death_tick = i + 1
			break
	# Float accumulation may land on 180 or 181 — assert it's exactly ~3 s (within a tick).
	_check("stranded_dot_kills_near_3s", death_tick >= 180 and death_tick <= 181,
		"death_tick=%d" % death_tick)

func _test_hp_int_rounds() -> void:
	var h := Health.new()
	h.take_damage(26.5)                 # 73.5 -> rounds to 74
	var a := h.hp_int()
	h.take_damage(200.0)                # dead -> 0
	var b := h.hp_int()
	_check("hp_int_rounds", a == 74 and b == 0, "a=%d b=%d" % [a, b])

func _test_deterministic() -> void:
	# Two instances driven by the same scripted sequence stay bit-identical.
	var h1 := Health.new()
	var h2 := Health.new()
	var ident := true
	for i in 400:
		var dmg := 0.0
		if i == 50:
			dmg = 200.0                  # kill both at the same tick
		var k1 := h1.take_damage(dmg)
		var k2 := h2.take_damage(dmg)
		var e1 := h1.tick()
		var e2 := h2.tick()
		if i == 250:                     # respawn both at the same tick
			h1.respawn()
			h2.respawn()
		if k1 != k2 or e1 != e2 or not _approx(h1.hp, h2.hp, 1e-9) or h1.alive != h2.alive \
			or h1.invuln_ticks() != h2.invuln_ticks() or h1.respawn_ticks() != h2.respawn_ticks():
			ident = false
	_check("deterministic", ident, "hp1=%.6f hp2=%.6f" % [h1.hp, h2.hp])
