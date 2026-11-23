extends SceneTree
## r198 probe: what a floor's foes cost each frame when nobody is fighting them. ROB=1 ID=floor34
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	var id := OS.get_environment("ID") if OS.get_environment("ID") != "" else "floor34"
	G.go_to(id, "<")
	for i in 900:
		await process_frame
		var lv = get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == id and lv.stream_left() == 0 and i > 30: break
	for i in 120: await process_frame
	var foes := get_nodes_in_group("enemy")
	var t0 := Time.get_ticks_usec()
	for k in 60:
		for e in foes:
			e._physics_process(1.0 / 60.0)
	var t1 := Time.get_ticks_usec()
	for k in 60:
		for e in foes:
			e._process(1.0 / 60.0)
	var t2 := Time.get_ticks_usec()
	for k in 60:
		for e in foes:
			e.move_and_slide()
	var t3 := Time.get_ticks_usec()
	for k in 60:
		for e in foes:
			get_first_node_in_group("player"); G.combat_data()
	var t4 := Time.get_ticks_usec()
	var near := 0
	var pl = get_first_node_in_group("player")
	for e in foes:
		if e.global_position.distance_to(pl.global_position) < float(e.stats.get("aggro", 9.0)) * 2.0: near += 1
	print("FOES move_and_slide all: %.2f ms   group+combat_data all: %.2f ms   near the player: %d" % [(t3 - t2) / 60000.0, (t4 - t3) / 60000.0, near])
	print("FOES %s n=%d  physics tick, all foes: %.2f ms  (%.3f a foe)   draw tick, all foes: %.2f ms" % [id, foes.size(), (t1 - t0) / 60000.0, (t1 - t0) / 60000.0 / maxf(foes.size(), 1), (t2 - t1) / 60000.0])
	quit()
	var a := await _wall(300)
	for e in foes: e.process_mode = Node.PROCESS_MODE_DISABLED
	var b := await _wall(300)
	for e in foes: e.process_mode = Node.PROCESS_MODE_INHERIT
	var c := await _wall(300)
	print("FOES %s n=%d  with foes %.2f ms/frame  without %.2f  again %.2f  -> %.3f ms a foe" % [id, foes.size(), a, b, c, ((a + c) / 2.0 - b) / maxf(foes.size(), 1)])
	quit()


func _wall(n: int) -> float:
	## busy time a frame: process + physics, as the engine itself times them (the headless loop sleeps to ~7 ms a frame)
	var tot := 0.0
	for i in n:
		await process_frame
		tot += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return tot * 1000.0 / n
