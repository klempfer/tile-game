extends "res://input/input_provider.gd"
## Trivial deterministic bot (M6): emits a constant move command every tick (default =
## forward, in the actor's local space). No `Input`, no `Rng`, so it is reproducible by
## construction. Combined with the M5 movement restriction this is enough to make the
## actor creep its capture frontier forward tile-by-tile — real bot AI is M14. Look and
## buttons are zero (the actor keeps its start_yaw). (InputCommand inherited from base.)

var _move: Vector2

func _init(move_dir: Vector2 = Vector2(0.0, 1.0)) -> void:
	_move = move_dir

func poll(_tick: int):
	return InputCommand.new(_tick, _move, Vector2.ZERO, 0)
