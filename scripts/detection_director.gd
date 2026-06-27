extends Node3D
## M11 detection resolver. Mirrors combat_director.gd: a scene node gated by the MatchDirector
## (set_active) and cleared on round reset (reset). Each ACTIVE tick it feeds every actor the
## center-to-center distance to its nearest enemy, steps that actor's pure Detection sim, then applies
## per-viewer visuals from the LOCAL player's screen: an enemy is rendered only while detected, a
## friendly always; the local player always renders itself (no overhead outline). Runs AFTER the actors
## in the tree so it sees this tick's positions + fire-bloom (player.gd calls detection().on_fire() in
## _fire()). Determinism: no RNG; Detection durations are integer ticks; positions drive a deterministic
## distance, so the detected/rendered flags are reproducible.

@export var player_path: NodePath
@export var bot_path: NodePath
@export var local_team := 1     # the screen's viewpoint — the team whose detection drives rendering

var _actors: Array = []
var _active := false

func _ready() -> void:
	var p := get_node_or_null(player_path)
	var b := get_node_or_null(bot_path)
	if p != null:
		_actors.append(p)
	if b != null:
		_actors.append(b)
	_apply_visuals()  # hide enemies until the first ACTIVE detection

## MatchDirector phase gate (like the combat/tile-view): detection is live only during ACTIVE.
func set_active(v: bool) -> void:
	_active = v

## Round reset / match restart: actors clear their own Detection in reset_to_spawn; re-hide enemies here.
func reset() -> void:
	_apply_visuals()

func _physics_process(_dt: float) -> void:
	if not _active:
		return
	for a in _actors:
		if a.has_method("detection"):
			a.detection().step(_nearest_enemy_distance(a))
	_apply_visuals()

## Center-to-center distance from `actor` to its nearest enemy actor (INF when there are none).
func _nearest_enemy_distance(actor) -> float:
	var best := INF
	var c: Vector3 = actor.body_center()
	for other in _actors:
		if other == actor or other.team_id() == actor.team_id():
			continue
		best = minf(best, c.distance_to(other.body_center()))
	return best

## Render from the local team's screen: enemies only while detected, friendlies always; the local
## player always renders itself. Extends cleanly to 2v2 (a non-local friendly draws a blue outline).
func _apply_visuals() -> void:
	for a in _actors:
		if a.is_local:
			continue
		var is_enemy: bool = a.team_id() != local_team
		var rendered: bool = a.detection().detected if is_enemy else true
		a.set_detection_visual(rendered, is_enemy)
