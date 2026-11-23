extends SceneTree
## r196: what costs a lot once in a while (the "min 1 fps" spikes): the 2-second housekeeping and friends
func t(f: Callable, n: int = 5) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n: f.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / n
func wall(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n: await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	G.go_to(OS.get_environment("ID") if OS.get_environment("ID") != "" else "village", "<")
	for i in 900:
		await process_frame
		var lv = get_first_node_in_group("level")
		if lv != null and lv.stream_left() == 0 and i > 30: break
	for i in 60: await process_frame
	var rows := []
	for name in ["check_achievements", "check_collections", "check_bounties", "process_queue", "check_expedition", "_downtime_tick", "_rest_tick"]:
		if G.has_method(name):
			var ms: float
			if name == "_downtime_tick" or name == "_rest_tick":
				ms = t(func(): G.call(name, 2.0))
			else:
				ms = t(func(): G.call(name))
			rows.append([ms, name])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows: print("SPIKE %-22s %.2f ms" % [r[1], r[0]])
	# frame-time histogram over 20 s: which frames are slow, and is anything periodic?
	var slow := []
	var last := Time.get_ticks_usec()
	var t_start := last
	while Time.get_ticks_usec() - t_start < 20000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		if d > 25.0: slow.append([snappedf((now - t_start) / 1e6, 0.1), snappedf(d, 0.1)])
		last = now
	print("SPIKE slow frames (>25 ms) in 20 s: ", slow.size(), " first ", slow.slice(0, 6), " last ", slow.slice(slow.size() - 6, slow.size()))
	var pl = get_first_node_in_group("player")
	pl.start_meditating(false)
	for i in 30: await process_frame
	var cands := {"none": [], "MemLog": [root.get_node_or_null("MemLog")], "HUD": [root.find_child("HUD", true, false)], "Pursuit": [G.sys("pursuit")], "Main": [root.get_node_or_null("Main")]}
	for nm in ["Horizon.gd", "Audio.gd", "Familiar.gd", "Ads.gd", "WorldSound.gd", "Waystone.gd"]:
		cands[nm] = []
	for nd in root.find_children("*", "", true, false):
		if nd.get_script() and cands.has(nd.get_script().resource_path.get_file()):
			cands[nd.get_script().resource_path.get_file()].append(nd)
	for k in cands:
		for nd in cands[k]:
			if nd != null and nd is Node: nd.set_process(false)
		var slow2 := []
		var last2 := Time.get_ticks_usec()
		var ts := last2
		while Time.get_ticks_usec() - ts < 6000000:
			await process_frame
			var now2 := Time.get_ticks_usec()
			var d2 := (now2 - last2) / 1000.0
			if d2 > 22.0: slow2.append(snappedf(d2, 0.1))
			last2 = now2
		for nd in cands[k]:
			if nd != null and nd is Node: nd.set_process(true)
		print("SPIKE sitting, %-14s off: slow frames in 6 s: %d %s" % [k, slow2.size(), str(slow2.slice(0, 8))])
	quit(0)
