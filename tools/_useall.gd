extends SceneTree
## r198 probe: what one "Use all" costs on Robert's save. ROB=1 PILL=mirror_pill_f25 N=200
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	G.go_to("village", "<")
	for i in 240: await process_frame
	var pill := OS.get_environment("PILL") if OS.get_environment("PILL") != "" else "mirror_pill_f25"
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 200
	var ta := Time.get_ticks_usec()
	for i in 50: G.stats_changed.emit()
	var tb := Time.get_ticks_usec()
	for i in 50: G.log_event("probe_ev", {"id": pill})
	var tc := Time.get_ticks_usec()
	for i in 50: G.add_qi(1.0, "probe")
	var td := Time.get_ticks_usec()
	for i in 50: G.remove_item(pill, 1)
	var te := Time.get_ticks_usec()
	print("USEALL parts each: stats_changed=%.2f log_event=%.2f add_qi=%.2f remove_item=%.2f ms" % [(tb-ta)/50000.0, (tc-tb)/50000.0, (td-tc)/50000.0, (te-td)/50000.0])
	print("USEALL affinity=%s" % str(G.affinity))
	G.fx_hold(true); G.log_hold(true)
	var tf := Time.get_ticks_usec()
	for i in 50: G.log_event("use_item", {"id": pill})
	var tg := Time.get_ticks_usec()
	for i in 50: G.add_qi(1.0, "probe")
	var th := Time.get_ticks_usec()
	for i in 50: G.attune("water", 4.0)
	var ti := Time.get_ticks_usec()
	G.log_hold(false); G.fx_hold(false)
	print("USEALL held each: log_event=%.2f add_qi=%.2f attune=%.2f ms" % [(tg-tf)/50000.0, (th-tg)/50000.0, (ti-th)/50000.0])
	var parts := {}
	var t := Time.get_ticks_usec()
	for i in 50: G.weekly_note("use_item")
	parts["weekly_note"] = (Time.get_ticks_usec() - t) / 50000.0
	t = Time.get_ticks_usec()
	for i in 50: G._insight_from_event("use_item", {"id": pill})
	parts["insight"] = (Time.get_ticks_usec() - t) / 50000.0
	t = Time.get_ticks_usec()
	for i in 50: G.mq_auto()
	parts["mq_auto"] = (Time.get_ticks_usec() - t) / 50000.0
	for k in G.systems:
		t = Time.get_ticks_usec()
		for i in 20: G.systems[k].on_event("use_item", {"id": pill})
		var ms: float = (Time.get_ticks_usec() - t) / 20000.0
		if ms > 0.01: parts["sys:" + str(k)] = ms
	print("USEALL log parts: %s" % str(parts))
	print("USEALL have=%d can_many=%s" % [G.count(pill), str(G.can_use_many(pill))])
	var t0 := Time.get_ticks_usec()
	var used: int = G.use_many(pill, n)
	var t1 := Time.get_ticks_usec()
	await process_frame
	var t2 := Time.get_ticks_usec()
	print("USEALL used=%d loop=%.1f ms (%.2f ms each) next_frame=%.1f ms" % [used, (t1 - t0) / 1000.0, (t1 - t0) / 1000.0 / maxf(used, 1), (t2 - t1) / 1000.0])
	quit()
