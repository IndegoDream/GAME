extends SceneTree
## r198 probe: what each menu page costs to (re)draw on Robert's save. ROB=1
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	G.go_to(OS.get_environment("ID") if OS.get_environment("ID") != "" else "village", "<")
	for i in 240: await process_frame
	var hud = get_first_node_in_group("hud")
	if hud == null:
		for n in root.find_children("*", "CanvasLayer", true, false):
			if n.get("_hub") != null: hud = n; break
	if hud.has_method("close_title"): hud.close_title()
	var hub = hud._hub
	var only := OS.get_environment("PAGES")
	var out := []
	for sec in hub.ORDER:
		if only != "" and not (str(sec) in only.split(",")): continue
		hub.show_page(sec)
		await process_frame
		await process_frame
		var best := 1e9
		var tot := 0.0
		for k in 3:
			var t := Time.get_ticks_usec()
			hub._fill(sec)
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			best = minf(best, ms); tot += ms
			await process_frame
		var pg: Node = hub.pages.get(sec)
		out.append([best, "%s nodes=%d" % [str(sec), pg.find_children("*", "", true, false).size() if pg else 0]])
	out.sort(); out.reverse()
	for o in out: print("HUBFILL %-28s %.1f ms" % [o[1], o[0]])
	quit()
