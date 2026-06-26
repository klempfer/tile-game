extends RefCounted
## M8 pure ballistics: spread sampling, hitscan ray-vs-capsule, straight-line projectile
## stepping, distance falloff, headshot test. All deterministic — randomness only via an
## injected RandomNumberGenerator (production passes Rng.stream("weapon_spread")). No
## nodes, no Input. Static helpers, unit-tested headlessly. (preload, no class_name.)

const WeaponDefs = preload("res://sim/weapon_defs.gd")

const FIXED_DT := 1.0 / 60.0

## Sample a fire direction inside a cone of `half_angle` (radians) around `forward`,
## uniform over the cone's end disc (GDD §7: "random point on the cone's end face").
## half_angle <= 0 returns `forward` exactly — the ADS / no-spread path. `forward` must
## be normalized; the perpendicular basis is built internally (any basis is fine for a
## symmetric disc, so it stays deterministic).
static func sample_spread(forward: Vector3, half_angle: float, rng: RandomNumberGenerator) -> Vector3:
	if half_angle <= 0.0:
		return forward
	var up_ref := Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up_ref).normalized()
	var up := right.cross(forward).normalized()
	var r := tan(half_angle) * sqrt(rng.randf())
	var th := TAU * rng.randf()
	return (forward + right * (r * cos(th)) + up * (r * sin(th))).normalized()

## Damage after distance falloff: full damage at <= falloff_full_m, linearly down to
## (damage * falloff_min_factor) at >= falloff_min_m.
static func damage_at(weapon: Dictionary, dist: float) -> float:
	var full: float = weapon["falloff_full_m"]
	var minm: float = weapon["falloff_min_m"]
	var base: float = weapon["damage"]
	var min_factor: float = weapon["falloff_min_factor"]
	if dist <= full:
		return base
	if dist >= minm:
		return base * min_factor
	return base * lerpf(1.0, min_factor, (dist - full) / (minm - full))

## Falloff damage with the headshot multiplier applied when `headshot`.
static func resolve_damage(weapon: Dictionary, dist: float, headshot: bool) -> float:
	var d := damage_at(weapon, dist)
	if headshot:
		d *= float(weapon["headshot_mult"])
	return d

## True if a hit at world-height `hit_y` lands in the head band — the top
## WeaponDefs.HEAD_BAND metres of a capsule whose feet are at `foot_y` and is `height` tall.
static func is_headshot(hit_y: float, foot_y: float, height: float) -> bool:
	return hit_y >= foot_y + height - WeaponDefs.HEAD_BAND

## Two-trace aim convergence (third-person). Removes the muzzle-vs-camera parallax so a
## shot lands on what the crosshair covers. Trace #1 = the camera/crosshair ray (from
## `cam_origin` along normalized `cam_dir`): its aim target is the point on `target` it
## covers, else a point `far_dist` down the ray. Trace #2 = the returned fire direction,
## from `muzzle` toward that aim target. `target` is a hitbox dict {pos,radius,height},
## or {} when the crosshair covers nothing. Pure; reuses ray_capsule. The caller applies
## spread to the result and resolves the actual shot from the muzzle.
static func aim_direction(muzzle: Vector3, cam_origin: Vector3, cam_dir: Vector3, target: Dictionary, far_dist: float) -> Vector3:
	var aim_point := cam_origin + cam_dir * far_dist
	if not target.is_empty():
		var res := ray_capsule(cam_origin, cam_dir, target["pos"], target["radius"], target["height"])
		if res["hit"]:
			aim_point = res["point"]
	return (aim_point - muzzle).normalized()

## Hitscan ray vs a vertical capsule (radius `radius`, total `height`, feet at cap_pos).
## `dir` must be normalized. Returns {hit, point, hit_y, dist}: `dist` is the distance
## from `origin` to the closest-approach point (for falloff), `hit_y` is the height on the
## capsule axis where the ray came closest (for headshot classification).
static func ray_capsule(origin: Vector3, dir: Vector3, cap_pos: Vector3, radius: float, height: float) -> Dictionary:
	var a := Vector3(cap_pos.x, cap_pos.y + radius, cap_pos.z)            # capsule core segment
	var b := Vector3(cap_pos.x, cap_pos.y + height - radius, cap_pos.z)
	var cr := _closest_ray_segment(origin, dir, a, b)
	var hit: bool = cr["dist"] <= radius and cr["t"] >= 0.0
	return {
		"hit": hit,
		"point": origin + dir * cr["t"],
		"hit_y": cr["seg_point"].y,
		"dist": cr["t"],
	}

## Advance a projectile one fixed tick (straight line, no gravity).
static func step_projectile(pos: Vector3, vel: Vector3) -> Vector3:
	return pos + vel * FIXED_DT

## True if a projectile sphere (center, proj_radius) overlaps the capsule.
static func projectile_hits(center: Vector3, proj_radius: float, cap_pos: Vector3, radius: float, height: float) -> bool:
	var a := Vector3(cap_pos.x, cap_pos.y + radius, cap_pos.z)
	var b := Vector3(cap_pos.x, cap_pos.y + height - radius, cap_pos.z)
	return _point_segment_dist(center, a, b) <= proj_radius + radius

# --- internal geometry helpers ---

## Closest approach between ray (origin O, normalized dir D, t >= 0) and segment [A,B].
## Returns {dist, t (along the ray), seg_point (closest point on the segment)}.
static func _closest_ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var v := b - a
	var w0 := o - a
	var bb := d.dot(v)
	var cc := v.dot(v)
	var dd := d.dot(w0)
	var ee := v.dot(w0)
	var denom := cc - bb * bb           # d.dot(d) == 1 (normalized)
	var s: float
	if denom > 1e-8:
		s = (ee - bb * dd) / denom      # param along the segment line
	elif cc > 1e-8:
		s = ee / cc
	else:
		s = 0.0
	s = clampf(s, 0.0, 1.0)
	var seg_pt := a + v * s
	var t := maxf((seg_pt - o).dot(d), 0.0)
	var ray_pt := o + d * t
	return {"dist": ray_pt.distance_to(seg_pt), "t": t, "seg_point": seg_pt}

static func _point_segment_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.dot(ab)
	var t := 0.0
	if denom > 1e-8:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)
