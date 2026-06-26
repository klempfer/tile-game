extends RefCounted
## One tick of intent for a single actor.
##
## Produced by an InputProvider (local player, bot, or scripted/replay) and
## consumed by the sim — the sim NEVER reads raw Input. This is the seam that
## future authoritative netcode and replays plug into (GDD §18).
##
## Referenced elsewhere via preload (no class_name) so headless CLI runs resolve
## it without depending on the editor's global class cache.

# Button bitmask flags (grows over milestones).
const BTN_JUMP := 1 << 0
const BTN_SPRINT := 1 << 1
const BTN_CROUCH := 1 << 2
const BTN_ADS := 1 << 3
const BTN_FIRE := 1 << 4       # M8
const BTN_RELOAD := 1 << 5     # M8
const BTN_WEAPON1 := 1 << 6    # M8: select weapon 1 this tick
const BTN_WEAPON2 := 1 << 7    # M8: select weapon 2 this tick
const BTN_WEAPON3 := 1 << 8    # M8.5: select weapon 3 this tick (SMG)

var tick: int = 0
var move_dir: Vector2 = Vector2.ZERO  # local-space intended move (x = strafe, y = forward)
var look: Vector2 = Vector2.ZERO      # yaw/pitch delta this tick
var buttons: int = 0                  # bitmask: jump/fire/etc. (grows in later milestones)

func _init(p_tick: int = 0, p_move: Vector2 = Vector2.ZERO, p_look: Vector2 = Vector2.ZERO, p_buttons: int = 0) -> void:
	tick = p_tick
	move_dir = p_move
	look = p_look
	buttons = p_buttons
