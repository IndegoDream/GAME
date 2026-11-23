extends SceneTree
## r194: per script class -- switch off _process for every node of that script, measure TIME_PROCESS; then physics:
## what collision objects exist, and what physics costs with Areas switched off.  ROB=1 ID=village
func avg(n: int) -> Array:
	var a := 0.0
	var b := 0.0
	for i in 15:
		await process_frame
	for i in n:
		await process_frame
		a += Performance.get_monitor(Performance.TIME_PROCESS)
		b += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return [a / n * 1000.0, b / n * 1000.0]
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
		G.load_game()
		G.save_base = "user://tool_shot"
		G.save_path = "user://tool_shot.json"
	else:
		G.new_game()
	G.go_to(id, "<")
	for i in 900:
		await process_frame
		var lv = root.get_tree().get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == id and lv.stream_left() == 0 and i > 30:
			break
	var hud = root.find_child("HUD", true, false)
	if hud and hud.has_method("close_title"):
		hud.close_title()
	for i in 120:
		await process_frame
	var base: Array = await avg(120)
	print("CPU2 base process=%.2f physics=%.2f" % base)
	var by := {}
	for nd in root.find_children("*", "", true, false):
		var k: String = (nd.get_script().resource_path.get_file() if nd.get_script() else nd.get_class())
		if nd.is_processing() and nd != self:
			if not by.has(k): by[k] = []
			by[k].append(nd)
	var rows := []
	for k in by:
		var saved := 0.0
		for rnd in 4:
			for nd in by[k]:
				if is_instance_valid(nd): nd.set_process(false)
			var off: Array = await avg(30)
			for nd in by[k]:
				if is_instance_valid(nd): nd.set_process(true)
			var on: Array = await avg(30)
			saved += on[0] - off[0]
		rows.append([saved / 4.0, k, by[k].size()])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 14):
		print("CPU2 %-22s x%-3d costs %.2f ms" % [r[1], r[2], r[0]])
	# collision objects
	var cnt := {}
	var areas := []
	var shapes := 0
	for nd in root.find_children("*", "CollisionObject3D", true, false):
		var c: String = nd.get_class()
		cnt[c] = int(cnt.get(c, 0)) + 1
		if nd is Area3D: areas.append(nd)
	for nd in root.find_children("*", "CollisionShape3D", true, false):
		shapes += 1
	print("CPU2 collision objects ", cnt, " shapes ", shapes)
	var mon := 0
	for a in areas:
		if a.monitoring: mon += 1
		a.set_deferred("monitoring", false)
	var r3: Array = await avg(60)
	print("CPU2 areas off (%d of %d monitoring) physics=%.2f process=%.2f" % [mon, areas.size(), r3[1], r3[0]])
	for a in areas: a.set_deferred("monitoring", true)
	NavigationServer3D.set_active(false)
	var r4: Array = await avg(120)
	print("CPU2 navigation server off: physics=%.2f process=%.2f" % [r4[1], r4[0]])
	NavigationServer3D.set_active(true)
	PhysicsServer3D.set_active(false)
	var r5: Array = await avg(120)
	print("CPU2 physics server off: physics=%.2f process=%.2f" % [r5[1], r5[0]])
	PhysicsServer3D.set_active(true)
	print("CPU2 nav maps=%d regions=%d agents=%d" % [NavigationServer3D.get_maps().size(), root.find_children("*", "NavigationRegion3D", true, false).size(), root.find_children("*", "NavigationAgent3D", true, false).size()])
	print("CPU2 engine=%s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("CPU2 physics ticks/s=%d max_steps=%d" % [Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame])
	quit(0)
