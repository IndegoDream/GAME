extends SceneTree
## r198 probe: the first half-minute after arriving on a floor -- the slowest frames, second by second. ROB=1 FROM=floor7 ID=floor24
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	var from := OS.get_environment("FROM") if OS.get_environment("FROM") != "" else "floor7"
	var id := OS.get_environment("ID") if OS.get_environment("ID") != "" else "floor24"
	G.go_to(from, "<")
	for i in 600: await process_frame
	var t0 := Time.get_ticks_msec()
	G.go_to(id, "<")
	var sec := 0
	var worst := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	var out := []
	while Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		n += 1
		var s := int((Time.get_ticks_msec() - t0) / 1000)
		if s != sec:
			var lv = get_first_node_in_group("level")
			out.append("%ds:%d/%.0f%s" % [sec, n, worst, "" if lv == null or lv.stream_left() == 0 else "s"])
			sec = s; worst = 0.0; n = 0
	print("ARRIVE %s->%s  second:frames/worst ms  %s" % [from, id, " ".join(out)])
	quit()
