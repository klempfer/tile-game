extends RefCounted
## Registers the GDD §17 default keybinds + reasonable controller defaults at
## runtime (idempotent). These are code defaults until the Config/rebind menu
## (later milestone) takes over. Only LocalInputProvider needs these; headless
## tests feed commands directly and never touch the InputMap.

static func ensure_default_actions() -> void:
	_bind("move_forward", [_key(KEY_W)], [_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind("move_back",    [_key(KEY_S)], [_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind("move_left",    [_key(KEY_A)], [_axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind("move_right",   [_key(KEY_D)], [_axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind("jump",   [_key(KEY_SPACE)], [_btn(JOY_BUTTON_A)])
	_bind("sprint", [_key(KEY_SHIFT)], [_btn(JOY_BUTTON_LEFT_SHOULDER)])
	_bind("crouch", [_key(KEY_CTRL)],  [_btn(JOY_BUTTON_B)])
	# Look (right stick; mouse look is fed in via relative motion, not an action).
	_bind("look_left",  [], [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind("look_right", [], [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_bind("look_up",    [], [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind("look_down",  [], [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	# Aim down sights: Toggle = Right Mouse (GDD §17); Hold unbound by default.
	_bind("ads_toggle", [_mouse(MOUSE_BUTTON_RIGHT)], [])
	_bind("ads_hold",   [], [])
	# Combat (M8): Fire = Left Mouse (GDD §17); Reload = R; weapon select = 1 / 2.
	# Controller bindings land in the dedicated controller pass (actions stay abstracted).
	_bind("fire",     [_mouse(MOUSE_BUTTON_LEFT)], [])
	_bind("reload",   [_key(KEY_R)], [])
	_bind("weapon_1", [_key(KEY_1)], [])
	_bind("weapon_2", [_key(KEY_2)], [])
	_bind("weapon_3", [_key(KEY_3)], [])   # M8.5 SMG (full-auto test weapon)
	# Debug: toggle tile coordinate labels (M3).
	_bind("debug_toggle_labels", [_key(KEY_F1)], [])
	# Debug: collapse Team 1 territory to spawn to test stranded free-roam (M5).
	_bind("debug_strand", [_key(KEY_F2)], [])
	# Debug: toggle the top-down observation camera (M6).
	_bind("debug_cam", [_key(KEY_F3)], [])
	# Debug: deal damage to force a kill (M9 — F4 damages the bot, F5 the player) + restart match (M7).
	_bind("debug_point_team1", [_key(KEY_F4)], [])
	_bind("debug_point_team2", [_key(KEY_F5)], [])
	_bind("debug_restart_match", [_key(KEY_F6)], [])

static func _bind(action: String, keys: Array, joys: Array) -> void:
	if InputMap.has_action(action):
		return  # already set (e.g. by a future rebind/config system)
	InputMap.add_action(action, 0.2)
	for e in keys:
		InputMap.action_add_event(action, e)
	for e in joys:
		InputMap.action_add_event(action, e)

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

static func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

static func _axis(axis: JoyAxis, dirv: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dirv
	return e

static func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e
