extends SceneTree
## r187: the same view before and after the still props go into batches (ID=valley) -> /tmp/bs_a.png, /tmp/bs_b.png
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
	# stand by the thickest clutch of plain props
	var best: Node3D = null
	var best_n := 0
	var hs := []
	for c in lv.get_children():
		if lv.prop_batchable(c) and (OS.get_environment("NEAR") == "" or str(c.name).contains(OS.get_environment("NEAR")) or (c as Node).find_child("*" + OS.get_environment("NEAR") + "*", true, false) != null):
			hs.append(c)
	for i in range(0, hs.size(), 7):
		var n := 0
		for h in hs:
			if (h as Node3D).global_position.distance_to((hs[i] as Node3D).global_position) < 14.0:
				n += 1
		if n > best_n:
			best_n = n
			best = hs[i]
	var pl = root.get_tree().get_first_node_in_group("player")
	if best:
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.global_position = best.global_position + Vector3(7, 6, 11)
		cam.look_at(best.global_position + Vector3(0, 1, 0))
		cam.make_current()
		print("SHOT looking at ", best_n, " props at ", best.global_position)
	var hud = root.find_child("HUD", true, false)
	if hud:
		hud.visible = false
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	for c2 in root.find_children("*", "Control", true, false):
		(c2 as Control).visible = false
	for i in 40:
		await process_frame
	print("SHOT player at ", pl.global_position if pl else null)
	root.get_viewport().get_texture().get_image().save_png("/tmp/bs_a.png")
	lv.batch_props_now()
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/bs_b.png")
	print("SHOT props=", lv.props_in_batches, " batches=", lv.prop_batches, " water=", lv.water_in_batches)
	quit(0)
