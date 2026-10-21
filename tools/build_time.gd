extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var L = load("res://scripts/world/Level.gd")
	L.prof = OS.get_environment("PROF") != ""
	L.stream_on = OS.get_environment("STREAM") != ""
	if OS.get_environment("WARM") != "":
		var W = load("res://scripts/core/Warm.gd").new()
		W.start()
		while W.pending() > 0:
			W.tick()
			await process_frame
	for id in OS.get_cmdline_user_args():
		var def: Dictionary = G.load_level_def(id)
		var t := Time.get_ticks_usec()
		var lv = L.new()
		lv.build(def)
		root.add_child(lv)
		print("== %s total %.0f ms, nodes %d" % [id, (Time.get_ticks_usec() - t) / 1000.0, lv.find_children("*", "", true, false).size()])
		lv.free()
	quit()
