extends RefCounted
## M8 per-actor weapon state machine: which weapon is selected, ammo per weapon, the
## fire-rate cooldown, and reload — all counted in integer TICKS (60 Hz) so timing lands
## on exact boundaries (determinism rule). Pure: no Input, no nodes, no Rng. One step()
## per fixed tick; the node layer (player.gd) turns a "fired" result into an actual shot.
## Referenced via preload (no class_name).

const WeaponDefs = preload("res://sim/weapon_defs.gd")

var current: int = WeaponDefs.REVOLVER
var _ammo: Array = []          # ammo per weapon id (parallel to WeaponDefs.WEAPONS)
var _cooldown: int = 0         # ticks until the next shot is allowed
var _reload_left: int = 0      # ticks until reload completes (0 = not reloading)

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

func ammo() -> int:
	return _ammo[current]

func reloading() -> bool:
	return _reload_left > 0

## Advance one fixed tick. `switch_to` selects a weapon id this tick, or -1 for none.
## Returns {fired, weapon, ammo, reloading}. Fire requires: off cooldown, not reloading,
## ammo > 0. An empty trigger pull (ammo 0, off cooldown) auto-starts a reload so the
## trigger is never dead. Switching weapons cancels an in-progress reload (you swapped
## guns) but keeps the global fire-rate cooldown so switch-firing can't beat the cap.
func step(fire_held: bool, reload_pressed: bool, switch_to: int) -> Dictionary:
	if switch_to >= 0 and switch_to != current and switch_to < WeaponDefs.WEAPONS.size():
		current = switch_to
		_reload_left = 0

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

	var fired := false
	if fire_held and _cooldown == 0 and _reload_left == 0:
		if _ammo[current] > 0:
			_ammo[current] -= 1
			_cooldown = int(w["fire_ticks"])
			fired = true
		else:
			# Empty magazine: auto-reload rather than dry-firing.
			_reload_left = int(w["reload_ticks"])

	return {"fired": fired, "weapon": current, "ammo": _ammo[current], "reloading": _reload_left > 0}
