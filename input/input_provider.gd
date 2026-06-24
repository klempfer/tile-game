extends RefCounted
## Base interface: given a tick, return the InputCommand for that tick.
##
## Subclasses (added across milestones):
##   - LocalInputProvider    KB+M / controller -> InputCommand
##   - BotInputProvider       AI -> InputCommand
##   - ScriptedInputProvider  fixed list -> InputCommand (tests + replay)

const InputCommand = preload("res://input/input_command.gd")

func poll(_tick: int):
	return InputCommand.new(_tick)
