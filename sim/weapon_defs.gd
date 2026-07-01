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
const SMG := 2

# M11.5 spread states — index into a weapon's spread_hip / spread_ads arrays. Derived each shot from
# the actor's (already-gated) motion; SPRINT only reachable by future fire_while_sprint weapons.
const SPREAD_STAND := 0
const SPREAD_WALK := 1
const SPREAD_AIR := 2
const SPREAD_CROUCH := 3
const SPREAD_CROUCH_WALK := 4
const SPREAD_SPRINT := 5

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
		"auto": false,             # M11.5: semi-auto — one shot per click (+0.2 s input-queue leniency)
		"fire_while_sprint": false,# M11.5: can't fire mid-sprint (holding fire drops you out of sprint)
		# M11.5 spread half-angle (deg) by state: [stand, walk, air, crouch-still, crouch-walk, sprint].
		"spread_hip": [2.0, 4.0, 7.0, 1.0, 2.5, 8.0],
		"spread_ads": [0.5, 1.5, 3.0, 0.25, 0.5, 0.0],
		"falloff_full_m": 10.0,
		"falloff_min_m": 30.0,
		"falloff_min_factor": 0.40,
		"proj_speed": 0.0,         # n/a (hitscan)
		"proj_radius": 0.0,
		"proj_life_ticks": 0,
		# M8.5 recoil (degrees; converted in recoil.gd). recovery is deg/sec, constant speed.
		"recoil_pitch_deg": 2.0,   # upward kick per shot
		"recoil_yaw_deg": 0.5,     # horizontal pattern magnitude (x the fixed _PATTERN)
		"recoil_recovery_deg": 20.0,
	},
	{
		"name": "Bolt",
		"kind": PROJECTILE,
		"damage": 45.0,
		"headshot_mult": 1.5,
		"fire_ticks": 48,          # 0.8 s
		"mag": 4,
		"reload_ticks": 132,       # 2.2 s
		"auto": false,             # M11.5: semi-auto — one shot per click (+0.2 s input-queue leniency)
		"fire_while_sprint": false,
		# M11.5 spread half-angle (deg) by state: [stand, walk, air, crouch-still, crouch-walk, sprint].
		"spread_hip": [1.5, 3.5, 6.5, 0.75, 2.0, 7.5],
		"spread_ads": [0.3, 1.0, 2.5, 0.15, 0.3, 0.0],
		"falloff_full_m": 15.0,
		"falloff_min_m": 35.0,
		"falloff_min_factor": 0.50,
		"proj_speed": 45.0,        # m/s
		"proj_radius": 0.25,
		"proj_life_ticks": 180,    # 3 s then despawn
		# M8.5 recoil (degrees; converted in recoil.gd). recovery is deg/sec, constant speed.
		"recoil_pitch_deg": 2.6,   # upward kick per shot
		"recoil_yaw_deg": 0.4,     # horizontal pattern magnitude (x the fixed _PATTERN)
		"recoil_recovery_deg": 20.0,
	},
	{
		# Full-auto test weapon (M8.5): hitscan, 900 rpm (= every 4 ticks @ 60 Hz), 30-round mag.
		# Low per-shot damage; STRONG recoil so the spray climbs fast and recovery is easy to see
		# (sustained fire never reaches the recovery delay, so every shot's kick accumulates).
		"name": "SMG",
		"kind": HITSCAN,
		"damage": 12.0,
		"headshot_mult": 1.5,
		"fire_ticks": 4,           # 900 rpm
		"mag": 30,
		"reload_ticks": 120,       # 2.0 s
		"auto": true,              # M11.5: full-auto test weapon — hold to fire
		"fire_while_sprint": false,
		# M11.5 spread half-angle (deg) by state: [stand, walk, air, crouch-still, crouch-walk, sprint].
		"spread_hip": [3.0, 5.0, 8.0, 2.0, 3.5, 6.0],
		"spread_ads": [0.75, 2.0, 3.5, 0.5, 0.75, 0.0],
		"falloff_full_m": 8.0,
		"falloff_min_m": 25.0,
		"falloff_min_factor": 0.35,
		"proj_speed": 0.0,         # n/a (hitscan)
		"proj_radius": 0.0,
		"proj_life_ticks": 0,
		# Strong recoil for testing: ~0.6 deg/shot accumulates to ~18 deg over a held mag, then
		# recovers at 30 deg/sec (~0.6 s) — a clear, obvious recovery demo.
		"recoil_pitch_deg": 0.6,
		"recoil_yaw_deg": 0.5,
		"recoil_recovery_deg": 30.0,
	},
]

static func get_def(weapon_id: int) -> Dictionary:
	return WEAPONS[weapon_id]

## M11.5: spread cone half-angle (degrees) for a weapon given ADS + the firer's movement state. ADS uses
## the smaller spread_ads table. A 0.0 cone yields no spread (Ballistics.sample_spread returns forward).
static func spread_cone(weapon: Dictionary, ads: bool, state: int) -> float:
	var arr: Array = weapon["spread_ads"] if ads else weapon["spread_hip"]
	return arr[state]
