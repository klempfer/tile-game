extends RefCounted
## M10 directional-shield geometry. Pure, headlessly tested. The shield is a FLAT QUAD held in front of
## the player, perpendicular to the full aim direction (yaw + pitch), `SHIELD_DIST` out from the eye. A
## shot is blocked only if its straight path actually crosses that quad (ray-vs-quad) — NOT merely if it
## falls inside an infinite angular cone. This makes the block match exactly what the player/opponent
## sees, and naturally handles up/down aim. The same constants drive the `$ShieldVisual` mesh in
## player.gd, so the visible plane and the block stay identical. Referenced via preload (no class_name).

const SHIELD_DIST := 1.5     # metres the quad sits in front of the eye, along the aim (pushed out to
                             # clear the capsule at up/down angles). MUST match player.gd's placement.
const HALF_W := 0.8          # half the quad width  — MUST equal half the QuadMesh size.x in player.tscn
const HALF_H := 0.9          # half the quad height — MUST equal half the QuadMesh size.y in player.tscn

## True iff a shot travelling along `shot_dir` and striking the body at `hit_point` first passes through
## the shield quad. `eye` is the quad's anchor (player eye); `aim` is the look direction it faces.
## Geometry: intersect the shot's line (through `hit_point`, direction `shot_dir`) with the quad's plane
## (centre = eye + aim*SHIELD_DIST, normal = aim); block iff the crossing is within ±HALF_W / ±HALF_H in
## the plane's right/up basis AND on the incoming side (s <= 0 — the shield is crossed before the body,
## which also rejects shots from behind). Returns false for degenerate / parallel inputs.
static func blocks(eye: Vector3, aim: Vector3, hit_point: Vector3, shot_dir: Vector3) -> bool:
	var n := aim
	if n.length() < 0.0001 or shot_dir.length() < 0.0001:
		return false
	n = n.normalized()
	var d := shot_dir.normalized()
	var denom := d.dot(n)
	if absf(denom) < 0.000001:
		return false                       # shot parallel to the quad — never crosses it
	var center := eye + n * SHIELD_DIST
	var s := (center - hit_point).dot(n) / denom
	if s > 0.0:
		return false                       # plane is behind the body along travel (e.g. shot from behind)
	var on_plane := hit_point + d * s
	var right := n.cross(Vector3.UP)
	if right.length() < 0.0001:
		right = n.cross(Vector3.RIGHT)     # aim ~vertical guard (pitch limit keeps this from happening)
	right = right.normalized()
	var up := right.cross(n).normalized()
	var local := on_plane - center
	return absf(local.dot(right)) <= HALF_W and absf(local.dot(up)) <= HALF_H
