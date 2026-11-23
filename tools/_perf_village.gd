extends SceneTree
## r186: Robert's own save in the village -- where does the frame time go? (headless: script/CPU side only)
var G
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://perf_playlog.jsonl"
	G.save_path = OS.get_environment("SAVE") if OS.get_environment("SAVE") != "" else "user://perf_fresh.json"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	var ok: bool = G.load_game() if OS.get_environment("SAVE") != "" else false
	if not ok:
		G.new_game()
	print("LOADED ", ok, " level=", G.current_level)
	G.go_to(G.current_level if G.current_level != "" else "village", "<")
	var t0 := Time.get_ticks_msec()
	for i in 600:
		await process_frame
	print("WARM ", Time.get_ticks_msec() - t0, " ms for 600 frames; nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var samples := []
	for i in 120:
		var a := Time.get_ticks_usec()
		await process_frame
		samples.append(Time.get_ticks_usec() - a)
	samples.sort()
	print("FRAME us median=", samples[60], " p90=", samples[108], " max=", samples[119], " process_ms=", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, " physics_ms=", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	# who processes: count nodes by script that have processing on
	var counts := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var key := ""
		var sc = n.get_script()
		key = (sc.resource_path.get_file() if sc else n.get_class())
		var p := n.is_processing() or n.is_physics_processing()
		var e: Array = counts.get(key, [0, 0])
		e[0] += 1
		e[1] += 1 if p else 0
		counts[key] = e
	var rows := []
	for k in counts:
		rows.append([counts[k][0], counts[k][1], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var lights := 0
	var shadow_lights := 0
	for l in root.find_children("*", "OmniLight3D", true, false):
		lights += 1
		if (l as Light3D).shadow_enabled and (l as Light3D).visible:
			shadow_lights += 1
	print("OMNI ", lights, " with shadows ", shadow_lights)
	var shadow_meshes := 0
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		if (mi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (mi as Node3D).is_visible_in_tree():
			shadow_meshes += 1
	print("SHADOW CASTERS ", shadow_meshes)
	var byname := {}
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		var par: Node = (mi as Node).get_parent()
		var k2 := "%s/%s" % [par.name.rstrip("0123456789@"), (mi as Node).name.rstrip("0123456789@")]
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
			k2 += " [" + (mi as MeshInstance3D).mesh.get_class() + "]"
		byname[k2] = int(byname.get(k2, 0)) + 1
	var br := []
	for k in byname:
		br.append([byname[k], k])
	br.sort_custom(func(a, b): return a[0] > b[0])
	for r in br.slice(0, 40):
		print("GEOM ", r[0], "  ", r[1])
	var tris := {}
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		var t := 0
		var mesh: Mesh = null
		var inst := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
			inst = (gi as MultiMeshInstance3D).multimesh.visible_instance_count if (gi as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 else (gi as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
		var k3 := "%s/%s %s" % [(gi as Node).get_parent().name.rstrip("0123456789@"), (gi as Node).name.rstrip("0123456789@"), mesh.resource_path.get_file() if mesh.resource_path != "" else mesh.get_class()]
		var e3: Array = tris.get(k3, [0, 0])
		e3[0] += t * inst
		e3[1] += 1
		tris[k3] = e3
	var tr := []
	for k in tris:
		tr.append([tris[k][0], tris[k][1], k])
	tr.sort_custom(func(a, b): return a[0] > b[0])
	for r in tr.slice(0, 25):
		print("TRIS ", r[0], " in ", r[1], "  ", r[2])
	var mlist := []
	for gi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm3: MultiMesh = (gi as MultiMeshInstance3D).multimesh
		if mm3 == null or mm3.mesh == null:
			continue
		var t3 := 0
		for si in mm3.mesh.get_surface_count():
			var a3 := mm3.mesh.surface_get_arrays(si)
			t3 += (a3[Mesh.ARRAY_INDEX].size() / 3) if a3[Mesh.ARRAY_INDEX] != null else 0
		var mat_n := ""
		var mo = (gi as GeometryInstance3D).material_override
		if mo == null and mm3.mesh.get_surface_count() > 0:
			mo = mm3.mesh.surface_get_material(0)
		if mo is BaseMaterial3D and (mo as BaseMaterial3D).albedo_texture:
			mat_n = (mo as BaseMaterial3D).albedo_texture.resource_path.get_file()
		elif mo is ShaderMaterial:
			mat_n = (mo as ShaderMaterial).shader.resource_path.get_file()
		mlist.append([t3 * mm3.instance_count, mm3.instance_count, t3, (gi as Node).name, mat_n, (gi as MultiMeshInstance3D).global_position])
	mlist.sort_custom(func(a, b): return a[0] > b[0])
	for r in mlist.slice(0, 12):
		print("MM ", r)
	var big := []
	for gi in root.find_children("*", "MeshInstance3D", true, false):
		var mm: Mesh = (gi as MeshInstance3D).mesh
		if mm == null or (gi as Node).get_parent().name != "Level_village":
			continue
		var t := 0
		for si in mm.get_surface_count():
			var a := mm.surface_get_arrays(si)
			t += (a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX].size() / 3)
		var mn := ""
		if mm.get_surface_count() > 0 and mm.surface_get_material(0) is BaseMaterial3D and (mm.surface_get_material(0) as BaseMaterial3D).albedo_texture:
			mn = (mm.surface_get_material(0) as BaseMaterial3D).albedo_texture.resource_path.get_file()
		big.append([t, (gi as Node).name, mn, mm.get_surface_count()])
	big.sort_custom(func(a, b): return a[0] > b[0])
	for r in big.slice(0, 15):
		print("BIG ", r)
	for dl in root.find_children("*", "DirectionalLight3D", true, false):
		var d := dl as DirectionalLight3D
		print("DIR ", d.name, " shadow=", d.shadow_enabled, " mode=", d.directional_shadow_mode, " maxdist=", d.directional_shadow_max_distance, " visible=", d.visible)
	var vr := 0
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		if (gi as GeometryInstance3D).visibility_range_end > 0.0:
			vr += 1
	print("WITH VISIBILITY RANGE ", vr)
	for r in rows.slice(0, 30):
		print("NODES ", r[0], " processing ", r[1], "  ", r[2])
	quit(0)
