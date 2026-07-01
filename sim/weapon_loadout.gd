extends RefCounted
## M8 per-actor weapon state machine: which weapon is selected, ammo per weapon, the
## fire-rate cooldown, and reload — all counted in integer TICKS (60 Hz) so timing lands
## on exact boundaries (determinism rule). Pure: no Input, no nodes, no Rng. One step()
## per fixed tick; the node layer (player.gd) turns a "fired" result into an actual shot.
## Referenced via preload (no class_name).

const WeaponDefs = preload("res://sim/weapon_defs.gd")

const FIRE_QUEUE_TICKS := 12   # M11.5: 0.2 s — a semi-auto click can fire up to this early (queued)

var current: int = WeaponDefs.REVOLVER
var _ammo: Array = []          # ammo per weapon id (parallel to WeaponDefs.WEAPONS)
var _cooldown: int = 0         # ticks until the next shot is allowed
var _reload_left: int = 0      # ticks until reload completes (0 = not reloading)
var _prev_fire_held := false   # M11.5: previous tick's fire bit — for the semi-auto rising edge
var _fire_queued_ticks := 0    # M11.5: a slightly-early semi click stays queued this many ticks

func _init() -> void:
	reset()

## Fresh loadout: revolver selected, every magazine full, no cooldown / reload.
func reset() -> void:
	current = WeaponDefs.REVOLVER
	_ammo = []
	for w in WeaponDefs.WEAPONS:
		_ammo.append(int(w["mag"]))
	_cooldown = 0
	_reload_left = 0
	_prev_fire_held = false
	_fire_queued_ticks = 0

func ammo() -> int:
	return _ammo[current]

func reloading() -> bool:
	return _reload_left > 0

## Advance one fixed tick. `switch_to` selects a weapon id this tick, or -1 for none.
## Returns {fired, weapon, ammo, reloading}. Fire requires: a trigger, off cooldown, not reloading,
## ammo > 0. An empty trigger (ammo 0, off cooldown) auto-starts a reload so the trigger is never dead.
## Switching weapons cancels an in-progress reload (you swapped guns) but keeps the global fire-rate
## cooldown so switch-firing can't beat the cap, and resets the semi-auto fire queue.
##
## M11.5 trigger model: AUTO weapons fire whenever the button is held; SEMI weapons fire on a rising
## edge (one shot per click), with a 0.2 s input queue so a click slightly before the cooldown ends
## still fires as early as possible. All derived from the per-tick `fire_held` bit -> replay/netcode-safe.
func step(fire_held: bool, reload_pressed: bool, switch_to: int) -> Dictionary:
	if switch_to >= 0 and switch_to != current and switch_to < WeaponDefs.WEAPONS.size():
		current = switch_to
		_reload_left = 0
		_fire_queued_ticks = 0   # a swap drops any stale early-press from the old weapon

	var w := WeaponDefs.get_def(current)
	var mag := int(w["mag"])

	# Reload progression / start.
	if _reload_left > 0:
		_reload_left -= 1
		if _reload_left == 0:
			_ammo[current] = mag
	elif reload_pressed and _ammo[current] < mag:
		_reload_left = int(w["reload_ticks"])

	if _cooldown > 0:
		_cooldown -= 1
	if _fire_queued_ticks > 0:
		_fire_queued_ticks -= 1

	var auto: bool = bool(w.get("auto", false))
	var fire_pressed: bool = fire_held and not _prev_fire_held
	var trigger: bool = fire_held if auto else (fire_pressed or _fire_queued_ticks > 0)

	var fired := false
	if trigger and _reload_left == 0:
		if _cooldown == 0:
			if _ammo[current] > 0:
				_ammo[current] -= 1
				_cooldown = int(w["fire_ticks"])
				fired = true
				_fire_queued_ticks = 0
			else:
				# Empty magazine: auto-reload rather than dry-firing.
				_reload_left = int(w["reload_ticks"])
				_fire_queued_ticks = 0
		elif not auto and fire_pressed:
			# Semi click during the cooldown: queue it so it fires the instant the cooldown clears.
			_fire_queued_ticks = FIRE_QUEUE_TICKS

	_prev_fire_held = fire_held
	return {"fired": fired, "weapon": current, "ammo": _ammo[current], "reloading": _reload_left > 0}
