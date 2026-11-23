extends SceneTree
## r187: the same view before and after the still props go into batches (ID=valley) -> /tmp/seam.png, /tmp/bs_b.png
var G
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_base = "user://tool_shot"      # (never the real account: the test kit would switch itself on there)
	G.save_path = "user://batch_shot.json"
	G.playlog_path = "user://batch_shot.jsonl"
	load("res://scripts/core/Gfx.gd").settings["preset"] = "medium"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.hour_override = 11.0
	if OS.get_environment("FOUND") != "":           # (r188: with a sect founded at the Empty Seat)
		G.realm = 3
		G.gold = 99999
		G.char_name = "Rob"
		G.sys("own_sect").found("Moonwell Sect", "water", 3, "Still water, sharp blade.", [])
		for k in ["hall_lanterns", "hall_statue", "hall_banners"]:
			G.sys("fellowship").owned[k] = true
		for k in 4:
			var cs: Array = G.sys("own_sect").candidates()
			if cs.size() > 0:
				G.sys("own_sect").recruit(str(cs[0]["name"]))
	var want := OS.get_environment("ID") if OS.get_environment("ID") != "" else "valley"
	G.go_to(want, "<")
	var lv = null
	for i in 600:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv and lv.stream_left() == 0 and i > 20:
			break
	lv.set_process(false)
	lv.batch_trees_now()
	var cv := OS.get_environment("CAM").split_floats(",")
	var av := OS.get_environment("AT").split_floats(",")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(cv[0], cv[1], cv[2])
	cam.look_at(Vector3(av[0], av[1], av[2]))
	cam.make_current()
	var hud = root.find_child("HUD", true, false)
	if hud:
		hud.visible = false
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	for c2 in root.find_children("*", "Control", true, false):
		(c2 as Control).visible = false
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/seam.png")
	quit(0)
