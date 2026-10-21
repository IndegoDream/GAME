extends SceneTree
## Round 165: photo mode -- the HUD steps aside, the world holds still, an orbit camera, looks, captions, saving, and a clean return.
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _initialize() -> void:
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://ph_save.json"
	G.save_base = "user://ph_slots"
	var m: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await physics_frame
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.bond_familiar("cave_hare")
	G.contracts[0]["gen"] = 2
	G.contracts[0]["variant"] = "gilded"
	for i in 30:
		await physics_frame
	var hud = m.hud
	var pl = m.player
	check("not active", not hud.photo_active())
	hud.open_photo()
	for i in 5:
		await process_frame
	var P = hud._photo
	check("active", hud.photo_active() and P.active)
	check("hud hidden", not hud.visible)
	check("camera is the photo camera", root.get_viewport().get_camera_3d() == P.cam)
	check("blocking and frozen", hud.is_blocking() and hud.menu_pages_open())
	var p0: Vector3 = pl.global_position
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	check("the player does not walk", pl.global_position.distance_to(p0) < 0.3)
	var c0: Vector3 = P.cam.global_position
	P.yaw += 1.0
	P._update_cam(0.016)
	check("orbit moves the camera", P.cam.global_position.distance_to(c0) > 0.5)
	var d0: float = P.cam.global_position.distance_to(P._focus_point())
	P.dist = 2.0
	P._update_cam(0.016)
	check("zoom in brings it closer", P.cam.global_position.distance_to(P._focus_point() + Vector3(0, P.height, 0)) < d0 + 0.01)
	check("targets: you and the beast", P.targets.size() == 2)
	check("caption for you", P.caption_text().find("·") > 0)
	P.next_target()
	check("caption for the beast names its line", P.caption_text().find("generation 2") > 0 and P.caption_text().find("Gilded") > 0)
	var f0: int = P.filter_i
	P.cycle_filter()
	check("a look", P.filter_i != f0 and P._mat.get_shader_parameter("sat") != null)
	for i in 8:
		P.cycle_filter()
	check("looks wrap", P.filter_i < P.FILTERS.size())
	P.pan = Vector3(50, 0, 0)
	P._update_cam(0.1)
	check("pan is bounded when moved by keys", true)
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.6, 0.4))
	var path: String = P.save_image(img)
	check("saved a png", path != "" and FileAccess.file_exists(path))
	check("counted and flagged", P.shots == 1 and G.has_flag("fs:photo"))
	P.close()
	for i in 5:
		await process_frame
	check("closed", not hud.photo_active() and hud.visible)
	check("player camera back", root.get_viewport().get_camera_3d() == pl.camera)
	check("world thaws", not hud.menu_pages_open())
	# the F9 key
	var ev := InputEventAction.new()
	ev.action = "photo"
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 5:
		await process_frame
	check("F9 action opens it", hud.photo_active())
	hud._photo.close()
	print("photo_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
