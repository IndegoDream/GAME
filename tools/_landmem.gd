extends SceneTree
## what a level holds after it's built: nodes by kind, enemies, meshes, memory
var _f := 0
var _level
var _id := "frontier:frostmere"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _id = a[0]

func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		var game = root.get_node("Game")
		game.playlog_path = "user://tool_playlog.jsonl"
		game.save_path = "user://landmem_save.json"
		game.new_game()
		_level = load("res://scripts/world/Level.gd").new()
		_level.name = "Level"
		_level.build(game.load_level_def(_id))
		root.add_child(_level)
	if _f == 6 or _f == 40:
		var kinds := {}
		var scripts := {}
		var meshes := {}
		for n in _level.find_children("*", "", true, false):
			kinds[n.get_class()] = int(kinds.get(n.get_class(), 0)) + 1
			var s = n.get_script()
			if s:
				var sp: String = s.resource_path.get_file()
				scripts[sp] = int(scripts.get(sp, 0)) + 1
			if n is MeshInstance3D and n.mesh:
				meshes[n.mesh.get_instance_id()] = true
		var ks := kinds.keys()
		ks.sort_custom(func(x, y): return kinds[x] > kinds[y])
		var top := []
		for k in ks.slice(0, 8):
			top.append("%s=%d" % [k, kinds[k]])
		var ss := scripts.keys()
		ss.sort_custom(func(x, y): return scripts[x] > scripts[y])
		var stop := []
		for k in ss.slice(0, 10):
			stop.append("%s=%d" % [k, scripts[k]])
		print("LANDMEM %s f%d size %dx%d nodes %d unique_meshes %d static_MB %.0f objects %d" % [_id, _f, _level.width, _level.height,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), meshes.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT)])
		print("LANDMEM kinds ", " ".join(top))
		print("LANDMEM scripts ", " ".join(stop))
		# meshes and lights by the top-level child of the level they hang under
		var owners := {}
		var lights := {}
		for n in _level.find_children("*", "MeshInstance3D", true, false) + _level.find_children("*", "OmniLight3D", true, false):
			var top_n: Node = n
			while top_n.get_parent() != _level and top_n.get_parent() != null:
				top_n = top_n.get_parent()
			var key: String = top_n.get_script().resource_path.get_file() if top_n.get_script() else top_n.name.rstrip("0123456789_@")
			if n is OmniLight3D:
				lights[key] = int(lights.get(key, 0)) + 1
			else:
				owners[key] = int(owners.get(key, 0)) + 1
		var os := owners.keys()
		os.sort_custom(func(x, y): return owners[x] > owners[y])
		var o2 := []
		for k in os.slice(0, 14):
			o2.append("%s=%d" % [k, owners[k]])
		print("LANDMEM meshes_under ", " ".join(o2))
		print("LANDMEM lights_under ", lights)
		var sub := {}
		for c in _level.get_children():
			if c.get_script() == null and c is Node3D:
				var nm: String = c.scene_file_path.get_file() if c.scene_file_path != "" else str(c.name).rstrip("0123456789_@")
				var cnt: int = c.find_children("*", "MeshInstance3D", true, false).size() + (1 if c is MeshInstance3D else 0)
				sub[nm] = int(sub.get(nm, 0)) + cnt
		var ss2 := sub.keys()
		ss2.sort_custom(func(x, y): return sub[x] > sub[y])
		var o3 := []
		for k in ss2.slice(0, 18):
			o3.append("%s=%d" % [k, sub[k]])
		print("LANDMEM inside ", " ".join(o3))
		var anon := []
		for c in _level.get_children():
			if c.get_script() == null and c is Node3D and c.scene_file_path == "" and str(c.name).begins_with("@Node3D"):
				anon.append(c)
		anon.sort_custom(func(x, y): return x.get_child_count() > y.get_child_count())
		print("LANDMEM anon count ", anon.size())
		var firsts := {}
		for c in anon:
			var fk := "empty"
			if c.get_child_count() > 0:
				var f0: Node = c.get_child(0)
				fk = (f0.scene_file_path.get_file() if f0.scene_file_path != "" else str(f0.name).rstrip("0123456789_@")) + "/" + str(c.find_children("*", "MeshInstance3D", true, false).size())
			firsts[fk] = int(firsts.get(fk, 0)) + 1
		print("LANDMEM anon_first ", firsts)
		for c in anon.slice(0, 3):
			var names := {}
			for g in c.get_children():
				var gn: String = g.scene_file_path.get_file() if g.scene_file_path != "" else str(g.name).rstrip("0123456789_@")
				names[gn] = int(names.get(gn, 0)) + 1
			print("LANDMEM anon ", c.name, " kids ", c.get_child_count(), " ", names)
	return _f > 41
