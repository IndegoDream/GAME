extends SceneTree
## r186: frame time with a real renderer (xvfb) in Eliet -- before/after comparisons
var G
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_base = "user://tool_shot"      # (never the real account: the test kit would switch itself on there)
	G.save_path = "user://perf_live.json"
	G.playlog_path = "user://perf_live.jsonl"
	load("res://scripts/core/Gfx.gd").settings["preset"] = "medium"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.hour_override = 11.0
	var want := OS.get_environment("ID") if OS.get_environment("ID") != "" else "village"
	G.go_to(want, "<")
	var lv = null
	for i in 400:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv and lv.stream_left() == 0 and i > 20:
			break
	if lv and lv.has_method("batch_trees_now"):
		lv.batch_trees_now()
		lv.batch_props_now()
	for i in 5:
		await process_frame
	var t := Time.get_ticks_msec()
	for i in 20:
		await process_frame
	print("LIVE ", OS.get_environment("ID"), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " FRAME ms avg=", (Time.get_ticks_msec() - t) / 20.0, " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	quit(0)
