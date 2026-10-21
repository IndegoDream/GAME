extends SceneTree
## loads every script in scripts/ so a parse error anywhere shows up. godot --headless --path . --script tools/compile_all.gd
func _initialize() -> void:
	await process_frame
	var bad := 0
	var n := 0
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				n += 1
				var s = load(d + "/" + f)
				if s == null or not (s is GDScript) or not s.can_instantiate() and not s.is_abstract():
					bad += 1
					print("COMPILE FAIL ", d, "/", f)
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
	print("COMPILE ALL %d scripts, %d failed" % [n, bad])
	quit()
