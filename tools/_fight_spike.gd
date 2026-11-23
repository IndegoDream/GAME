extends SceneTree
## r197: frame times while fighting (real blows through Player._start_blow) on Robert's save. ROB=1 ID=floor22
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"; G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4: await process_frame
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	else:
		G.new_game()
	var id := OS.get_environment("ID") if OS.get_environment("ID") != "" else "floor22"
	G.go_to(id, "<")
	var tl := Time.get_ticks_msec()
	for i in 900:
		await process_frame
		var lv = get_first_node_in_group("level")
		if i % 30 == 0: print("FIGHT load frame %d t=%d ms lvl=%s" % [i, Time.get_ticks_msec() - tl, str(lv.level_id) if lv else "-"])
		if lv != null and str(lv.level_id) == id and lv.stream_left() == 0 and i > 30: break
	var hud = root.find_child("HUD", true, false)
	if hud and hud.has_method("close_title"): hud.close_title()
	for i in 60: await process_frame
	print("FIGHT ready")
	var pl = get_first_node_in_group("player")
	var foes := get_nodes_in_group("enemy")
	print("FIGHT %s foes=%d hp=%d dmg=%d" % [id, foes.size(), G.hp, G.damage()])
	var tdie := []
	for n in 6:
		var e = get_nodes_in_group("enemy")[n]
		var t1 := Time.get_ticks_usec()
		e.take_damage(999999999, "you")
		var a := (Time.get_ticks_usec() - t1) / 1000.0
		var fr := []
		for q in 3:
			var t2 := Time.get_ticks_usec()
			await process_frame
			fr.append(snappedf((Time.get_ticks_usec() - t2) / 1000.0, 0.1))
		tdie.append("%.1f+%s" % [a, str(fr)])
	print("FIGHT kill: sync ms + next 3 frames: ", tdie)
	var frames := []
	var hits := 0
	var t_end := Time.get_ticks_msec() + 25000
	var last := Time.get_ticks_usec()
	var worst := []
	var next_blow := 0
	var k0 := foes.size()
	while Time.get_ticks_msec() < t_end:
		var alive := []
		for e in get_nodes_in_group("enemy"):
			if is_instance_valid(e) and not e.get("_dead"): alive.append(e)
		if alive.is_empty(): break
		var e = alive[0]
		if Time.get_ticks_msec() >= next_blow:
			var to: Vector3 = e.global_position - pl.global_position
			to.y = 0
			if to.length() > 1.6:
				pl.global_position = e.global_position - to.normalized() * 1.2
			pl.look_at(Vector3(e.global_position.x, pl.global_position.y, e.global_position.z), Vector3.UP)
			pl.rotate_y(PI)
			pl._start_blow(false, 1.0)
			hits += 1
			next_blow = Time.get_ticks_msec() + 450
		await process_frame
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		frames.append(d)
		if d > 30.0: worst.append(snappedf(d, 0.1))
		last = now
	frames.sort()
	var avg := 0.0
	for f in frames: avg += f
	avg /= maxf(frames.size(), 1)
	print("FIGHT blows=%d kills=%d frames=%d avg %.1f ms  p95 %.1f  max %.1f  slow(>30) %d %s" % [hits, k0 - get_nodes_in_group("enemy").size(), frames.size(), avg, frames[int(frames.size() * 0.95)], frames[-1], worst.size(), str(worst.slice(0, 15))])
	quit(0)
