extends SceneTree
## r195: where the CPU goes, in WALL time per frame (Performance.TIME_PROCESS is the worst frame of each second, not an average). ROB=1 ID=village
func avg(n: int) -> float:
	## average WALL time per frame (Performance.TIME_PROCESS is the worst frame of the last second, not an average)
	for i in 10: await process_frame
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	G.go_to(OS.get_environment("ID") if OS.get_environment("ID") != "" else "village", "<")
	for i in 900:
		await process_frame
		var lv = get_first_node_in_group("level")
		if lv != null and lv.stream_left() == 0 and i > 30: break
	var hud = root.find_child("HUD", true, false)
	if hud and hud.has_method("close_title"): hud.close_title()
	for i in 60: await process_frame
	Engine.set_meta("fxp", {})
	var b0: int = G.fx_builds
	var f0 := Engine.get_process_frames()
	var w := await avg(240)
	var mm: Dictionary = Engine.get_meta("fxp")
	var rr := []
	for k in mm: rr.append([mm[k], k])
	rr.sort_custom(func(a, b): return a[0] > b[0])
	print("UI callers ", rr.slice(0, 12))
	print("UI %s wall ms/frame %.2f, exact effect builds per frame %.2f" % [OS.get_environment("ID"), w, float(G.fx_builds - b0) / (Engine.get_process_frames() - f0)])
	quit(0)
