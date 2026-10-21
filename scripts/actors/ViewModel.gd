extends Node3D
## Round 128: what you hold, seen from inside your own head (first person). The body is hidden from your eyes in first
## person, so without this you swing at things with empty air. It builds the weapon you actually hold (the same
## model other people see on you), a forearm in your robe's colour, and moves like a hand: it bobs when you walk, lags
## behind your look, drops when you sprint, and swings when you strike. Third person never creates it.

const Dress := preload("res://scripts/world/Dress.gd")

var player
var tracked := false              # VR: the hand IS the controller -- no bob, lag or swing animation
const TRACKED_ROT := Vector3(-0.35, PI, 0.0)
var _grip: Node3D
var _arm: MeshInstance3D
var _kind := "#"
var _t := 0.0
var _swing := 0.0             # 0..1 through a blow
var _swing_dur := 0.3
var _heavy := false
var _lag := Vector2.ZERO      # how far the look has run ahead of the hand
var _last_yaw := 0.0
var _last_pitch := 0.0
var _rest := Vector3(0.34, -0.36, -0.62)
var _rest_rot := Vector3(-1.0, PI + 0.12, 0.18)


func setup(p) -> void:
	player = p
	_last_yaw = float(p._yaw)
	_last_pitch = float(p._pitch)
	refresh()


func _held_kind() -> String:
	if Game.weapon == "" or not Game.has_item_def(Game.weapon):
		return ""
	return str(Game.item_def(Game.weapon).get("kind", "sword"))


func refresh() -> void:
	## the weapon in your hand changed (or first time): build it again
	var k := _held_kind()
	if k == _kind and _grip != null:
		return
	_kind = k
	for c in get_children():
		c.queue_free()
	_grip = Node3D.new()
	_grip.scale = Vector3.ONE * 0.8
	add_child(_grip)
	var robe := Color(0.35, 0.4, 0.55)
	var col = player.dress_spec().get("robe", [0.35, 0.4, 0.55])
	robe = Color(col[0], col[1], col[2])
	var skin := Color(0.85, 0.7, 0.58)
	var sk = player.dress_spec().get("skin", null)
	if sk is Array and sk.size() >= 3:
		skin = Color(sk[0], sk[1], sk[2])
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = robe
	sleeve.roughness = 0.9
	var hand_m := StandardMaterial3D.new()
	hand_m.albedo_color = skin
	hand_m.roughness = 0.8
	_arm = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.055
	cm.height = 0.5
	_arm.mesh = cm
	_arm.material_override = sleeve
	_arm.rotation = Vector3(PI / 2 + 0.2, 0, 0)
	_arm.position = Vector3(0, -0.10, -0.26)            # behind the fist, down toward the camera edge
	_grip.add_child(_arm)
	var fist := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.062
	sm.height = 0.124
	fist.mesh = sm
	fist.material_override = hand_m
	_grip.add_child(fist)
	if _kind != "":
		var held := Node3D.new()
		_grip.add_child(held)
		Dress._held_real(held, _kind, null)
	_apply_pose(0.0)
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func swing(heavy: bool) -> void:
	_swing = 0.001
	_heavy = heavy
	_swing_dur = 0.46 if heavy else 0.28


func _process(delta: float) -> void:
	if player == null or _grip == null:
		return
	if tracked:
		position = Vector3.ZERO
		rotation = TRACKED_ROT
		return
	_t += delta
	var dy := wrapf(float(player._yaw) - _last_yaw, -PI, PI)
	var dp := float(player._pitch) - _last_pitch
	_last_yaw = float(player._yaw)
	_last_pitch = float(player._pitch)
	_lag = _lag.lerp(Vector2(clampf(-dy * 2.2, -0.35, 0.35), clampf(dp * 2.0, -0.25, 0.25)), clampf(delta * 14.0, 0.0, 1.0))
	_lag *= clampf(1.0 - delta * 5.0, 0.0, 1.0)
	if _swing > 0.0:
		_swing += delta / _swing_dur
		if _swing >= 1.0:
			_swing = 0.0
	_apply_pose(delta)


func _apply_pose(_delta: float) -> void:
	var sp: float = Vector2(player.velocity.x, player.velocity.z).length() if player != null else 0.0
	var moving := clampf(sp / 5.0, 0.0, 1.4)
	var bob := Vector3(sin(_t * 7.5) * 0.012, absf(sin(_t * 7.5)) * 0.018, 0.0) * moving
	var breathe := Vector3(0, sin(_t * 1.6) * 0.004, 0)
	var drop := Vector3(0, -0.05, 0.03) * clampf(moving - 0.9, 0.0, 1.0) * 2.0        # sprinting lowers it
	var pos := _rest + bob + breathe + drop + Vector3(_lag.x * 0.12, _lag.y * 0.12, 0)
	var rot := _rest_rot + Vector3(_lag.y * 0.5, _lag.x * 0.5, _lag.x * 0.3)
	if _swing > 0.0:
		# wind back for the first third, then cut across and through, then settle
		var t := _swing
		var wind := clampf(t / 0.3, 0.0, 1.0)
		var cut := clampf((t - 0.3) / 0.35, 0.0, 1.0)
		var back := clampf((t - 0.65) / 0.35, 0.0, 1.0)
		var amt := (wind * (1.0 - cut)) * -1.0 + cut * (1.0 - back)
		if _kind in ["spear", "staff", "polearm", "halberd"]:
			pos += Vector3(0, 0, -0.35 * cut * (1.0 - back) + 0.12 * wind * (1.0 - cut))      # a thrust
			rot += Vector3(0.1 * cut, 0, 0)
		else:
			pos += Vector3(-0.30 * cut * (1.0 - back) + 0.10 * wind * (1.0 - cut), 0.04 * amt, -0.10 * cut * (1.0 - back))
			rot += Vector3(-0.5 * cut * (1.0 - back) + 0.25 * wind * (1.0 - cut), 0.0, 1.1 * amt * (1.4 if _heavy else 1.0))
	position = pos
	rotation = rot
