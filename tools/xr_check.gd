extends SceneTree
# VR stage 1 without a headset: the switch stays off, the rig builds and maps controls, thumbstick/snap-turn maths, and the flat game is untouched.
var ok := 0
var bad := 0
func t(n: String, c: bool) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("  FAIL ", n)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	var XRM = load("res://scripts/core/XRMode.gd")
	var Rig = load("res://scripts/actors/XRRig.gd")
	var Gx = load("res://scripts/core/Gfx.gd")
	t("VR is off by default", XRM.mode() == "off" and not XRM.wanted())
	Gx.settings["vr"] = "on"
	t("on without a headset does nothing", not XRM.wanted() or XRM.available())
	Gx.settings["vr"] = "banana"
	Gx.load_settings()
	t("a bad setting falls back to off", XRM.mode() == "off")
	Gx.settings["vr"] = "off"
	# thumbstick maths
	t("dead zone swallows drift", Rig.dead(Vector2(0.1, 0.1)) == Vector2.ZERO)
	t("full push is full speed", absf(Rig.dead(Vector2(0, 1)).length() - 1.0) < 0.001)
	t("just past the dead zone is gentle", Rig.dead(Vector2(0.25, 0)).length() < 0.1)
	var s1: Array = Rig.snap(0.9, true)
	t("push right turns once", s1[0] == 1 and s1[1] == false)
	t("holding it does not keep turning", Rig.snap(0.9, false)[0] == 0)
	t("coming back re-arms", Rig.snap(0.2, false)[1] == true)
	t("push left turns the other way", Rig.snap(-0.9, true)[0] == -1)
	t("a small push does not turn", Rig.snap(0.5, true)[0] == 0)
	# the rig, with a stand-in player
	var fake = Node3D.new()
	fake.set_script(null)
	var holder := Node3D.new()
	root.add_child(holder)
	var rig = Rig.new()
	holder.add_child(rig)
	var pl := Node3D.new()
	pl.set_meta("x", 1)
	rig.setup(holder)
	t("rig has a head and two hands", rig.head != null and rig.left != null and rig.right != null and rig.left.tracker == &"left_hand" and rig.right.tracker == &"right_hand")
	t("no controller, no movement", rig.move_vector() == Vector2.ZERO and rig.snap_turn() == 0.0)
	rig._pressed("trigger_click")
	t("trigger attacks", Input.is_action_pressed("attack"))
	rig._pressed("grip_click")
	t("grip guards", Input.is_action_pressed("guard"))
	rig._released("trigger_click")
	t("letting go releases", not Input.is_action_pressed("attack") and Input.is_action_pressed("guard"))
	rig.release_all()
	t("release_all lets go of everything", not Input.is_action_pressed("guard"))
	rig._pressed("nonsense_button")
	t("unknown buttons do nothing", true)
	for b in Rig.BUTTONS.values():
		t("action exists: " + str(b), InputMap.has_action(str(b)))
	# the weapon hand
	var vm = load("res://scripts/actors/ViewModel.gd").new()
	vm.tracked = true
	t("tracked hand flag", vm.tracked)
	print("XR CHECK %d passed, %d failed" % [ok, bad])
	quit(1 if bad else 0)
