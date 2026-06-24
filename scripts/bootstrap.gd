extends Control
## M0 entry scene. Establishes the match seed via the Rng service and reports
## that the foundation booted cleanly. No gameplay yet.

func _ready() -> void:
	var match_seed := Rng.new_match_seed()
	print("[Bootstrap] Tile-Capture Shooter M0 — booted OK. Match seed = %d" % match_seed)
	var label := $Label as Label
	if label:
		label.text = "Tile-Capture Shooter — M0 foundation OK\nMatch seed: %d\n(See console. Run res://tests/test_m0.tscn for the self-test.)" % match_seed
