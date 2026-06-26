extends RefCounted
## M8 weapon stat table + shared combat constants. Pure DATA, no logic, no nodes.
## Indexed by weapon id (0 = revolver hitscan, 1 = bolt projectile). Numbers chosen with
## the user; damage is calibrated to an ASSUMED 100 HP (real base HP lands in M9). Every
## duration is in integer TICKS (60 Hz), never seconds, per the determinism rule.
## Referenced via preload (no class_name) so headless CLI runs resolve it.

const HITSCAN := 0
const PROJECTILE := 1

# Weapon ids.
const REVOLVER := 0
const BOLT := 1

# Shared geometry. Actor capsule: radius 0.4, height 1.8 standing / 1.2 crouched, origin
# at the feet (see player.tscn / player.gd).
const EYE_HEIGHT := 1.6        # muzzle / aim origin height above the actor's feet
const HEAD_BAND := 0.45        # top this-many metres of the capsule = headshot region
const ASSUMED_HP := 100        # placeholder for TTK logging only; real HP is M9

const WEAPONS := [
	{
		"name": "Revolver",
		"kind": HITSCAN,
		"damage": 26.0,
		"headshot_mult": 1.5,
		"fire_ticks": 30,          # 0.5 s @ 60 Hz
		"mag": 6,
		"reload_ticks": 96,        # 1.6 s
		"cone_deg": 3.0,           # hip-fire cone half-angle; ADS = 0
		"falloff_full_m": 10.0,
		"falloff_min_m": 30.0,
		"falloff_min_factor": 0.40,
		"proj_speed": 0.0,         # n/a (hitscan)
		"proj_radius": 0.0,
		"proj_life_ticks": 0,
	},
	{
		"name": "Bolt",
		"kind": PROJECTILE,
		"damage": 45.0,
		"headshot_mult": 1.5,
		"fire_ticks": 48,          # 0.8 s
		"mag": 4,
		"reload_ticks": 132,       # 2.2 s
		"cone_deg": 2.0,           # spread applied to launch direction
		"falloff_full_m": 15.0,
		"falloff_min_m": 35.0,
		"falloff_min_factor": 0.50,
		"proj_speed": 45.0,        # m/s
		"proj_radius": 0.25,
		"proj_life_ticks": 180,    # 3 s then despawn
	},
]

static func get_def(weapon_id: int) -> Dictionary:
	return WEAPONS[weapon_id]
