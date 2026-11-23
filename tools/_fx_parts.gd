extends SceneTree
## r197: what each source of Game._build_effects() costs on Robert's save
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_rob"; G.use_slot(2); G.load_game(); G.save_base = "user://tool_shot"; G.save_path = "user://tool_shot.json"
	var N := 50
	var parts := {
		"techniques": func(): for tid in G.techniques: G.technique_defs.get(tid, {}).get("effect", {}),
		"treasures": func(): for id in G.inventory: G.is_treasure(id),
		"affinity": func(): G.affinity_effect(),
		"lattice": func(): G.lattice_effect(),
		"buffs": func(): G.active_buffs(),
		"nanite": func(): G.nanite_effect(),
		"sect": func(): G.sect_effect(),
		"dao_heart": func(): G.dao_heart_effect(),
		"beasts": func(): G.beasts_out(),
		"gear": func(): G.gear_effects(),
		"runes": func(): G.rune_effects(),
		"blood": func(): G.blood_effect(),
		"zone": func(): G.zone_effect(),
		"ascension": func(): G.ascension_effect(),
		"attribute": func(): G.attribute_effect(),
		"title": func(): G.title_effect(),
	}
	var rows := []
	for k in parts:
		var t0 := Time.get_ticks_usec()
		for i in N: parts[k].call()
		rows.append([(Time.get_ticks_usec() - t0) / 1000.0 / N, k])
	var sy := []
	for k in G.systems:
		var t1 := Time.get_ticks_usec()
		for i in N: G.systems[k].effects()
		sy.append([(Time.get_ticks_usec() - t1) / 1000.0 / N, k])
	sy.sort_custom(func(a, b): return a[0] > b[0])
	var stot := 0.0
	for r in sy: stot += r[0]
	rows.append([stot, "systems (all %d)" % sy.size()])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var t2 := Time.get_ticks_usec()
	for i in N: G._build_effects()
	print("FXP _build_effects %.3f ms total" % ((Time.get_ticks_usec() - t2) / 1000.0 / N))
	for r in rows: print("FXP   %-18s %.3f" % [r[1], r[0]])
	print("FXP top systems ", sy.slice(0, 8).map(func(r): return "%s %.3f" % [r[1], r[0]]))
	var ev := {"check_unlocks": func(): G.check_unlocks(), "Hook.on_kill": func(): G.get_node("/root/Hook").on_kill("ghoul") if G.has_node("/root/Hook") else load("res://scripts/systems/Hook.gd").on_kill("ghoul"), "log_event": func(): G.log_event("kill", {"type": "ghoul"}), "guild_event": func(): G.guild_event("kill"), "sect_contrib": func(): G.sect_contrib(1.0, "kill"), "blood_kill": func(): G.blood_kill({"hp": 100}), "add_qi": func(): G.add_qi(5.0, "x"), "train_weapon": func(): G.train_weapon(0, 100)}
	for k in ev:
		var t3 := Time.get_ticks_usec()
		for i in 10: ev[k].call()
		print("FXP event %-14s %.3f ms" % [k, (Time.get_ticks_usec() - t3) / 10000.0])
	var ev2 := {"weekly_note": func(): G.weekly_note("kill"), "_insight_from_event": func(): G._insight_from_event("kill", {"type": "ghoul"}), "mq_auto": func(): G.mq_auto()}
	for k in ev2:
		var t4 := Time.get_ticks_usec()
		for i in 10: ev2[k].call()
		print("FXP log part %-20s %.3f ms" % [k, (Time.get_ticks_usec() - t4) / 10000.0])
	var se := []
	for k in G.systems:
		var t5 := Time.get_ticks_usec()
		for i in 10: G.systems[k].on_event("kill", {"type": "ghoul"})
		se.append([(Time.get_ticks_usec() - t5) / 10000.0, k])
	se.sort_custom(func(a, b): return a[0] > b[0])
	print("FXP on_event top ", se.slice(0, 6).map(func(r): return "%s %.3f" % [r[1], r[0]]))
	var t6 := Time.get_ticks_usec()
	for i in 10:
		var f := FileAccess.open("user://tool_playlog.jsonl", FileAccess.READ_WRITE if FileAccess.file_exists("user://tool_playlog.jsonl") else FileAccess.WRITE)
		f.seek_end(); f.store_line("{}")
	print("FXP file append %.3f ms" % ((Time.get_ticks_usec() - t6) / 10000.0))
	var ev3 := {"gear_pool": func(): G.gear_pool(22, ["weapon", "armor"]), "drop_gear": func(): G.drop_gear(22, 0), "drop_gear(held)": func(): G.fx_hold(true); G.drop_gear(22, 0); G.fx_hold(false), "Hook.compare": func(): G.Hook.compare(G.weapon), "roll_loot": func(): G.roll_loot({"gold": [10, 20]}), "add_item": func(): G.add_item("spirit_herb", 1), "reveal_loot": func(): G.reveal_loot("spirit_herb")}
	for k in ev3:
		var t7 := Time.get_ticks_usec()
		for i in 10: ev3[k].call()
		print("FXP gear %-16s %.3f ms" % [k, (Time.get_ticks_usec() - t7) / 10000.0])
	quit(0)
