extends Node
## Deterministic seeded RNG service (autoload "Rng").
##
## RULE: no unseeded/global random anywhere in the project. Every random system
## (spread, card draws, bot jitter, ...) pulls a NAMED stream from here so the
## whole match is reproducible from a single match seed — required for future
## online play + replays (GDD §18).

var _master_seed: int = 0
var _streams: Dictionary = {}  # String -> RandomNumberGenerator

## Set the master seed and reset all derived streams. Logged.
func set_seed(p_seed: int) -> void:
	_master_seed = p_seed
	_streams.clear()
	print("[Rng] master seed set: %d" % p_seed)

func get_master_seed() -> int:
	return _master_seed

## Produce (and apply) a per-match seed. Pass override_seed >= 0 to force a
## specific seed for reproducible testing/replays; otherwise one is derived from
## the clock. Either way it is applied and logged so any run can be reproduced.
func new_match_seed(override_seed: int = -1) -> int:
	var s: int
	if override_seed >= 0:
		s = override_seed
		print("[Rng] using override seed")
	else:
		s = abs(int(Time.get_unix_time_from_system() * 1000.0)) % 2147483647
	set_seed(s)
	return s

## Get a deterministic RNG stream for the given name. Each name has a stable,
## independent sequence derived from the master seed, so adding a new random
## system can never desync the existing ones.
func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = _master_seed ^ _name_hash(stream_name)
		_streams[stream_name] = rng
	return _streams[stream_name]

func _name_hash(stream_name: String) -> int:
	return int(hash(stream_name))
