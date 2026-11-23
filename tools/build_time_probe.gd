extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var LS = load("res://scripts/world/Level.gd")
	var out := []
	LS.prof = true
	LS.stream_on = true
	for id in ["floor25"]:
		var def = G.load_level_def(id)
		if def.is_empty(): continue
		var t0 := Time.get_ticks_usec()
		var lv = LS.new()
		lv.build(def)
		root.add_child(lv)
		var t1 := Time.get_ticks_usec()
		out.append("%s build %.0f ms" % [id, (t1 - t0) / 1000.0])
		lv.free()
	print("BUILDTIMES ", " | ".join(out))
	quit()
