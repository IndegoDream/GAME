extends SceneTree
## r190: where the CPU goes in a place, headless (no drawing): script _process / _physics_process per frame,
## who processes, physics bodies. ID=village|valley|floor1   -> prints CPU lines
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"
	G.save_path = "user://tool_shot.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	var id := OS.get_environment("ID") if OS.get_environment("ID") != "" else "village"
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"
		G.use_slot(2)
		print("CPU loaded rob save: ", G.load_game(), " realm ", G.realm)
		G.save_base = "user://tool_shot"
		G.save_path = "user://tool_shot.json"
	else:
		G.new_game()
	G.go_to(id, "<")
	var lv = null
	for i in 900:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == id and lv.stream_left() == 0 and i > 30:
			break
	var hud = root.find_child("HUD", true, false)
	if hud and hud.has_method("close_title"):
		hud.close_title()
	for i in 120:
		await process_frame
	var tp := 0.0
	var tph := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	for i in 300:
		await process_frame
		tp += Performance.get_monitor(Performance.TIME_PROCESS)
		tph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1
	var wall := (Time.get_ticks_usec() - t0) / 1e6 / n
	print("CPU %s frame=%.2fms process=%.2fms physics=%.2fms nodes=%d objects=%d bodies=%d" % [id, wall * 1000.0, tp / n * 1000.0, tph / n * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
	# switch each suspect off in turn and measure again
	var pl = root.get_tree().get_first_node_in_group("player")
	var suspects := {
		"player_physics": [pl, "physics"], "player_process": [pl, "process"],
		"game_process": [G, "process"], "hud_process": [hud, "process"], "level_process": [lv, "process"],
		"main_process": [m, "process"],
	}
	for sname in suspects:
		var node = suspects[sname][0]
		var kind: String = suspects[sname][1]
		if node == null:
			continue
		if kind == "physics":
			node.set_physics_process(false)
		else:
			node.set_process(false)
		for i in 20:
			await process_frame
		var a := 0.0
		var b := 0.0
		var t1 := Time.get_ticks_usec()
		for i in 120:
			await process_frame
			a += Performance.get_monitor(Performance.TIME_PROCESS)
			b += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		print("CPU off %-16s frame=%.2fms process=%.2fms physics=%.2fms" % [sname, (Time.get_ticks_usec() - t1) / 1000.0 / 120, a / 120 * 1000.0, b / 120 * 1000.0])
		if kind == "physics":
			node.set_physics_process(true)
		else:
			node.set_process(true)
	var who := {}
	var whop := {}
	for nd in root.find_children("*", "", true, false):
		var k: String = (nd.get_script().resource_path.get_file() if nd.get_script() else nd.get_class())
		if nd.is_processing():
			who[k] = int(who.get(k, 0)) + 1
		if nd.is_physics_processing():
			whop[k] = int(whop.get(k, 0)) + 1
	var rows := []
	for k in who:
		rows.append([who[k], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("CPU processing: ", rows.slice(0, 25))
	rows = []
	for k in whop:
		rows.append([whop[k], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("CPU physics: ", rows.slice(0, 25))
	quit(0)
