extends RefCounted
## Minimal deterministic simulation core for M0.
##
## Advances purely from InputCommands + the seeded Rng service, so an identical
## (seed + command stream) always reproduces identical state. Real gameplay
## entities layer on in later milestones; the tick / hash / record contract
## established here stays the same.

const InputCommand = preload("res://input/input_command.gd")

var tick: int = 0
var _accum: int = 0       # demo: RNG-driven accumulator (exercises determinism)
var _pos_x: float = 0.0   # demo: input-driven value (exercises the input pipeline)
var _recording: Array = []

func reset() -> void:
	tick = 0
	_accum = 0
	_pos_x = 0.0
	_recording.clear()

## Advance exactly one fixed tick from a single actor's command.
func step(cmd: InputCommand) -> void:
	var r := Rng.stream("demo")
	_accum = (_accum + (r.randi() % 100)) % 1000000
	_pos_x += cmd.move_dir.x * 0.1
	tick += 1
	_recording.append(cmd)

## Recorded command stream, for replay verification.
func get_recording() -> Array:
	return _recording.duplicate()

## Hash of the full sim state (including RNG stream state) for determinism and
## replay checks. The replay gate compares this across runs.
func state_hash() -> int:
	var s := "%d|%d|%.6f|%d" % [tick, _accum, _pos_x, Rng.stream("demo").state]
	return hash(s)
