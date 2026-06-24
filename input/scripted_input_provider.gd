extends "res://input/input_provider.gd"
## Replays a fixed list of InputCommands (one per tick). Used by self-tests and
## by replay playback. Deterministic by construction. (InputCommand const is
## inherited from the base provider.)

var _commands: Array = []

func _init(commands: Array = []) -> void:
	_commands = commands

func poll(_tick: int):
	if _tick >= 0 and _tick < _commands.size():
		return _commands[_tick]
	return InputCommand.new(_tick)

## Build a deterministic command list from a seeded RNG stream (test helper).
static func from_seeded(count: int, stream_name: String = "scripted_input") -> Array:
	var cmd_script = preload("res://input/input_command.gd")
	var r := Rng.stream(stream_name)
	var out: Array = []
	for i in count:
		out.append(cmd_script.new(i, Vector2(r.randf_range(-1.0, 1.0), r.randf_range(-1.0, 1.0))))
	return out
