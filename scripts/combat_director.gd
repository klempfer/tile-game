extends Node3D
## M8/M9 combat resolver. Each fixed tick (when active) it collects both actors' shots,
## resolves hitscan immediately and advances straight-line projectiles against the ENEMY
## actor's capsule via the pure Ballistics sim, computes falloff + headshot damage and
## (M9) APPLIES it to the victim's HP via victim.take_damage() — the victim owns the death
## reaction (visual + `died` signal that MatchDirector scores). Spawns placeholder
## tracer / in-flight projectile / hitmarker visuals. Holds projectile state across ticks;
## the MatchDirector gates it by phase (set_active) and clears it on round reset, exactly
## like the tile view gates capture. Determinism: spread draws from
## Rng.stream("weapon_spread"); all timing is in integer ticks. Kept at the scene origin
## so shot world-coordinates equal this node's local space (tracers/markers render right).

const WeaponDefs = preload("res://sim/weapon_defs.gd")
const Ballistics = preload("res://sim/ballistics.gd")

const TRACER_LIFE := 6        # ticks a tracer line stays visible
const MARKER_LIFE := 12       # ticks a hitmarker stays visible
const MISS_RANGE := 100.0     # tracer length when a hitscan shot hits nothing
const AIM_FAR := 1000.0       # camera-ray aim distance when the crosshair covers nothing
const TRACE_BACK := 0.5       # hit-test start pulled this far behind the muzzle (gun-through-enemy)

@export var player_path: NodePath
@export var bot_path: NodePath

var _actors: Array = []       # the actors that can fire / be hit
var _active := false
var _projectiles: Array = []  # [{node, pos, vel, weapon, team, origin, age}]
var _transients: Array = []   # [{node, life}] tracers + markers, freed when life hits 0
var last_event := ""          # HUD readout of the most recent hit

func _ready() -> void:
	var p := get_node_or_null(player_path)
	var b := get_node_or_null(bot_path)
	if p != null:
		_actors.append(p)
	if b != null:
		_actors.append(b)

## M7-style phase gate from the MatchDirector: combat is live only during ACTIVE.
func set_active(v: bool) -> void:
	_active = v

## Clear all in-flight projectiles + transient visuals (round reset / match restart).
func reset() -> void:
	for pr in _projectiles:
		pr["node"].queue_free()
	_projectiles.clear()
	for trans in _transients:
		trans["node"].queue_free()
	_transients.clear()
	last_event = ""

func _physics_process(_dt: float) -> void:
	_age_transients()
	if not _active:
		return
	for actor in _actors:
		if actor.has_method("consume_shots"):
			for shot in actor.consume_shots():
				_spawn_shot(shot)
	_step_projectiles()

func _enemy_of(team: int):
	for actor in _actors:
		if actor.has_method("team_id") and actor.team_id() != team:
			return actor
	return null

func _spawn_shot(shot: Dictionary) -> void:
	var w := WeaponDefs.get_def(int(shot["weapon"]))
	var enemy = _enemy_of(int(shot["team"]))
	var target: Dictionary = {}
	if enemy != null:
		target = enemy.hitbox()
	# Two-trace convergence: aim from the muzzle at whatever the crosshair (camera ray)
	# covers, then apply hip-fire spread to that converged direction (ADS = none).
	var dir := Ballistics.aim_direction(shot["muzzle"], shot["cam_origin"], shot["cam_dir"], target, AIM_FAR)
	if not bool(shot["ads"]):
		dir = Ballistics.sample_spread(dir, deg_to_rad(w["cone_deg"]), Rng.stream("weapon_spread"))
	if int(w["kind"]) == WeaponDefs.HITSCAN:
		_resolve_hitscan(shot, w, dir, enemy)
	else:
		_launch_projectile(shot, w, dir)

func _resolve_hitscan(shot: Dictionary, w: Dictionary, dir: Vector3, enemy) -> void:
	var muzzle: Vector3 = shot["muzzle"]
	var end := muzzle + dir * MISS_RANGE
	if enemy != null:
		var hb: Dictionary = enemy.hitbox()
		# Pull the hit-test start slightly behind the muzzle so a target the muzzle already
		# overlaps still registers; falloff is still measured from the true muzzle.
		var start := muzzle - dir * TRACE_BACK
		var res := Ballistics.ray_capsule(start, dir, hb["pos"], hb["radius"], hb["height"])
		if res["hit"]:
			end = res["point"]
			var dist: float = muzzle.distance_to(res["point"])
			var headshot: bool = Ballistics.is_headshot(res["hit_y"], hb["pos"].y, hb["height"])
			_apply_hit(int(shot["team"]), w, dist, headshot, res["point"], enemy)
	_spawn_tracer(muzzle, end)

func _launch_projectile(shot: Dictionary, w: Dictionary, dir: Vector3) -> void:
	var muzzle: Vector3 = shot["muzzle"]
	var node := _make_sphere(float(w["proj_radius"]), Color(1, 0.8, 0.2))
	node.position = muzzle
	add_child(node)
	_projectiles.append({
		"node": node, "pos": muzzle, "vel": dir * float(w["proj_speed"]),
		"weapon": int(shot["weapon"]), "team": int(shot["team"]), "origin": muzzle, "age": 0,
	})

func _step_projectiles() -> void:
	var survivors: Array = []
	for pr in _projectiles:
		var w := WeaponDefs.get_def(int(pr["weapon"]))
		pr["pos"] = Ballistics.step_projectile(pr["pos"], pr["vel"])
		pr["age"] = int(pr["age"]) + 1
		pr["node"].position = pr["pos"]
		var done := false
		var enemy = _enemy_of(int(pr["team"]))
		if enemy != null:
			var hb: Dictionary = enemy.hitbox()
			if Ballistics.projectile_hits(pr["pos"], float(w["proj_radius"]), hb["pos"], hb["radius"], hb["height"]):
				var dist: float = (pr["origin"] as Vector3).distance_to(pr["pos"])
				var headshot: bool = Ballistics.is_headshot((pr["pos"] as Vector3).y, hb["pos"].y, hb["height"])
				_apply_hit(int(pr["team"]), w, dist, headshot, pr["pos"], enemy)
				done = true
		if done or int(pr["age"]) >= int(w["proj_life_ticks"]):
			pr["node"].queue_free()
		else:
			survivors.append(pr)
	_projectiles = survivors

## M9: apply the finalized damage to the victim's HP (was log-only in M8). The victim owns the kill
## reaction (death visual + `died` signal -> scoring); here we just deal damage and report remaining HP.
func _apply_hit(team: int, w: Dictionary, dist: float, headshot: bool, point: Vector3, victim) -> void:
	var dmg := Ballistics.resolve_damage(w, dist, headshot)
	if victim != null and victim.has_method("take_damage"):
		victim.take_damage(dmg, team)
	var zone := "HEAD" if headshot else "body"
	var hp_txt := ""
	if victim != null and victim.has_method("health"):
		hp_txt = " -> %d HP" % victim.health().hp_int()
	last_event = "T%d %s %s %.0f dmg @ %.1fm%s" % [team, w["name"], zone, dmg, dist, hp_txt]
	print("[COMBAT] %s" % last_event)
	_spawn_marker(point)

# --- placeholder visuals ---

func _make_sphere(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	return mi

func _spawn_tracer(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	add_child(mi)
	_transients.append({"node": mi, "life": TRACER_LIFE})

func _spawn_marker(p: Vector3) -> void:
	var mi := _make_sphere(0.15, Color(1, 0.2, 0.2))
	mi.position = p
	add_child(mi)
	_transients.append({"node": mi, "life": MARKER_LIFE})

func _age_transients() -> void:
	var survivors: Array = []
	for trans in _transients:
		trans["life"] = int(trans["life"]) - 1
		if int(trans["life"]) <= 0:
			trans["node"].queue_free()
		else:
			survivors.append(trans)
	_transients = survivors
