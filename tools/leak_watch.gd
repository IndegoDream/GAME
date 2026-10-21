extends SceneTree
## fast-forwards the game and prints memory / object counts, to find what grows. godot --headless --path . --script tools/leak_watch.gd -- <time_scale> <seconds>
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var scale := float(a[0]) if a.size() > 0 else 10.0
	var secs := float(a[1]) if a.size() > 1 else 120.0
	var G = root.get_node("Game")
	G.new_game()
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	Engine.time_scale = scale
	var t0 := Time.get_ticks_msec()
	var last := -10.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await process_frame
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if el - last >= 10.0:
			last = el
			print("LEAK t=%3ds game=%4ds mem=%dMB nodes=%d objs=%d res=%d orphans=%d" % [int(el), int(el * scale), OS.get_static_memory_usage() / 1048576,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
	quit()
