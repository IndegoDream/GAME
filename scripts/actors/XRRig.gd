extends Node3D
## VR rig (round 135, stage 1): a headset camera, two hand controllers, thumbstick walking and snap turning.
## It rides on the Player. The game's own actions do the rest: the trigger attacks, the grip guards, A jumps, B uses, the menu button pauses.
## Comfort first: no smooth turning (snap), walking follows where your HEAD faces, the world never rolls.

const SNAP_DEG := 30.0
const SNAP_ARM := 0.75            # push the stick past this to turn...
const SNAP_REARM := 0.35          # ...and bring it back below this before the next turn
const DEADZONE := 0.2
const BUTTONS := {"trigger_click": "attack", "grip_click": "guard", "ax_button": "jump", "by_button": "interact", "menu_button": "pause"}

var player
var origin: XROrigin3D
var head: XRCamera3D
var left: XRController3D
var right: XRController3D
var _armed := true
var _held := {}                    # which of our actions we are holding down (so we can let go cleanly)


func setup(p) -> void:
	player = p
	origin = XROrigin3D.new()
	origin.name = "Origin"
	add_child(origin)
	head = XRCamera3D.new()
	head.name = "Head"
	origin.add_child(head)
	left = XRController3D.new()
	left.name = "LeftHand"
	left.tracker = &"left_hand"
	origin.add_child(left)
	right = XRController3D.new()
	right.name = "RightHand"
	right.tracker = &"right_hand"
	origin.add_child(right)
	for c in [left, right]:
		(c as XRController3D).button_pressed.connect(_pressed)
		(c as XRController3D).button_released.connect(_released)
	head.current = true


func _pressed(name: String) -> void:
	var a := str(BUTTONS.get(name, ""))
	if a == "" or _held.has(a):
		return
	_held[a] = true
	Input.action_press(a)


func _released(name: String) -> void:
	var a := str(BUTTONS.get(name, ""))
	if a == "" or not _held.has(a):
		return
	_held.erase(a)
	Input.action_release(a)


func release_all() -> void:
	for a in _held.keys():
		Input.action_release(str(a))
	_held.clear()


static func dead(v: Vector2) -> Vector2:
	## a thumbstick with a dead zone that eases out of it (no jump at the edge)
	var l := v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	return v.normalized() * clampf((l - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)


static func snap(x: float, armed: bool) -> Array:
	## one snap-turn step: returns [turn: -1/0/+1, armed_after]. Push right past SNAP_ARM to turn once; release below SNAP_REARM to turn again.
	if armed and absf(x) >= SNAP_ARM:
		return [1 if x > 0.0 else -1, false]
	if not armed and absf(x) <= SNAP_REARM:
		return [0, true]
	return [0, armed]


func move_vector() -> Vector2:
	## left thumbstick: x right, y back (like the keys), already dead-zoned
	if left == null or not left.get_is_active():
		return Vector2.ZERO
	var v: Vector2 = left.get_vector2("primary")
	return dead(Vector2(v.x, -v.y))


func snap_turn() -> float:
	## radians to add to the body's yaw this frame (positive = turn left, like the keys' +yaw)
	if right == null or not right.get_is_active():
		return 0.0
	var r := snap(right.get_vector2("primary").x, _armed)
	_armed = bool(r[1])
	return -float(r[0]) * deg_to_rad(SNAP_DEG)


func head_yaw() -> float:
	## which way the head faces, relative to the body
	return head.rotation.y if head != null else 0.0


func _process(_d: float) -> void:
	if player != null and origin != null and "_yaw" in player:
		origin.rotation.y = float(player._yaw)         # the body's turn carries the whole rig round
		if player.camera != null and head != null and head.is_inside_tree():
			player.camera.global_transform = head.global_transform     # (the flat camera is off, but aiming and prompts still read it)
