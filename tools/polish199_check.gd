extends SceneTree
## round 199: from Robert's 2026-11-09 play and a timing of every menu page on his save.
##  - a boss's young are not bosses (three "boss kills" and three boss gear drops in one second on floor 34);
##  - Elder Mo's errands are worked out once per depth reached (the Road page took 1.3 s);
##  - ticks, arrows and diamonds come from our own symbol font, and a label with one no longer asks the system for a font;
##  - a place's name is read from its file once; a menu page builds the effect list once.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _label_ms(txt: String, f: Font) -> float:
	var t := Time.get_ticks_usec()
	for i in 150:
		var l := Label.new()
		l.add_theme_font_override("font", f)
		l.text = txt + str(i)
		l.get_minimum_size()
		l.free()
	return (Time.get_ticks_usec() - t) / 150000.0


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://p199_save.json"
	G.save_base = "user://p199_slots"
	G.playlog_path = "user://p199_playlog.jsonl"
	if FileAccess.file_exists(G.playlog_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(G.playlog_path))
	G.new_game()
	# ---- 1. the symbol font
	var U = load("res://scripts/core/UiStyle.gd")
	var sym: FontFile = U.symbols_font()
	check("our symbol font is there", sym != null)
	if sym != null:
		var miss := ""
		for ch in "✓✔→←↑↓↔★●◆◇▸✦☾†":
			if not sym.has_char(ch.unicode_at(0)):
				miss += ch
		check("...with every tick, arrow and shape the game writes", miss == "", miss)
		var body: FontFile = U.font("body")
		check("the body font falls back to it", body != null and body.fallbacks.has(sym))
		for kind in ["bold", "heavy", "title"]:
			var f = U.font(kind)
			check("...and so does %s" % kind, f == null or (f as FontFile).fallbacks.has(sym))
		var fb = ThemeDB.fallback_font
		check("the engine's own fallback font knows our symbols", fb is FontFile and (fb as FontFile).fallbacks.has(sym))
		var ts := TextServerManager.get_primary_interface()
		var rid := ts.create_shaped_text()
		ts.shaped_text_add_string(rid, "ab ✓ cd", body.get_rids(), 14)
		ts.shaped_text_shape(rid)
		var from_ours := false
		var sym_rids := sym.get_rids()
		for g in ts.shaped_text_get_glyphs(rid):
			if int(g.get("start", -1)) == 3:
				from_ours = sym_rids.has(g.get("font_rid", RID())) and int(g.get("index", 0)) != 0
		ts.free_rid(rid)
		check("a tick in a line of words is drawn from our font (the same on every machine)", from_ours)
		var plain := _label_ms("   ok  Speak to the elder", body)
		var tick := _label_ms("   ✓  Speak to the elder", body)
		var arrow := _label_ms("→ ★ ◆ ▸ the way on", body)
		check("a label with a tick costs about what a plain one does (%.3f vs %.3f ms)" % [tick, plain], tick < plain * 4.0 + 0.05)
		check("...and one with arrows and stars (%.3f ms)" % arrow, arrow < plain * 4.0 + 0.05)
	# ---- 2. errands: once per depth
	var d1: Dictionary = G.errand_defs()
	check("Elder Mo's errands are worked out once", is_same(d1, G.errand_defs()))
	var t0 := Time.get_ticks_usec()
	for i in 200:
		G.errand_ready("errand:kill:1")
	var each := (Time.get_ticks_usec() - t0) / 200000.0
	check("asking whether an errand is ready is cheap (%.3f ms)" % each, each < 0.2)
	var n1 := d1.size()
	G.journal["places"]["floor6"] = {"visits": 1, "first": 0, "notes": []}
	var d2: Dictionary = G.errand_defs()
	check("going deeper brings new errands (%d -> %d)" % [n1, d2.size()], d2.size() > n1 and not is_same(d1, d2))
	check("...made of the same things as before", d2.has("errand:kill:1") and str(d2["errand:kill:1"].get("goal", {}).get("kill", "")) == str(d1["errand:kill:1"].get("goal", {}).get("kill", "")))
	G.errand_accept("errand:kill:1")
	var open: Array = G.errands_open()
	check("an errand taken shows as active", open.any(func(e): return str(e[0]) == "errand:kill:1" and str(e[2]) == "active"))
	# ---- 3. the HUD: place names, and a page holds the effect list only while it draws
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 6:
		await process_frame
	var nm: String = hud._place_name("floor3")
	check("a place's name is the one in its file", nm == str(G.load_level_def("floor3").get("name", "floor3")) and nm != "", nm)
	check("...the same the second time", hud._place_name("floor3") == nm and hud._pname.has("floor3"))
	check("...the valley and an unknown place too", hud._place_name("valley") != "" and hud._place_name("p199_nowhere") == "p199_nowhere")
	var I = load("res://scripts/core/I18n.gd")
	var was: String = I.current
	I.current = "de"
	hud._place_name("valley")
	check("another language asks again", hud._pname_lang == "de" and not hud._pname.has("floor3"))
	I.current = was
	for sec in ["Road", "Quests", "Works", "Pack", "Journal", "Craft"]:
		hud._hub.show_page(sec)
		await process_frame
		check("the %s page lets the effect list go when it's drawn" % sec, G._fx_hold == 0)
	var b0: int = G.fx_builds
	hud._hub._fill("Works")
	check("a page builds the effect list a handful of times, not once a line (%d)" % (G.fx_builds - b0), G.fx_builds - b0 <= 6)
	hud.queue_free()
	await process_frame
	# ---- 4. a boss's young are not bosses
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4:
		await process_frame
	G.go_to("floor3", "<")
	var lv = null
	for i in 600:
		await process_frame
		lv = get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == "floor3" and lv.stream_left() == 0 and i > 60:
			break
	var boss = null
	for e in get_nodes_in_group("enemy"):
		if bool(G.enemies.get(e.etype, {}).get("boss", false)):
			boss = e
	check("(floor 3 has its master)", boss != null)
	if boss != null:
		var at: Vector3 = boss.global_position + Vector3(1.5, 0, 0)
		var young = lv._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": boss.etype, "cell": lv.world_to_cell(at), "minion": true, "style": "brawler", "hp_mult": 0.2, "scale_mult": 0.55, "young": true})
		for i in 3:
			await process_frame
		check("the master is still a boss", bool(boss.stats.get("boss", false)) and bool(G.enemies[boss.etype].get("boss", false)))
		check("its young is not", young != null and not bool(young.stats.get("boss", false)) and young.minion)
		check("...and carries no loot or gear of its own", young != null and (young.stats.get("loot", {}) as Dictionary).is_empty() and float(young.stats.get("gear_chance", 1.0)) == 0.0)
		if young != null:
			var txt0 := FileAccess.get_file_as_string(G.playlog_path)
			var bk0 := txt0.count("\"boss_kill\"")
			var gd0 := txt0.count("\"gear_drop\"")
			var ph0 := txt0.count("\"boss_phase\"")
			young.take_damage(int(young.hp * 0.5), "you")
			young.take_damage(999999999, "you")
			for i in 3:
				await process_frame
			var txt1 := FileAccess.get_file_as_string(G.playlog_path)
			check("killing the young is not a boss kill", txt1.count("\"boss_kill\"") == bk0, "%d" % (txt1.count("\"boss_kill\"") - bk0))
			check("...leaves no boss's gear", txt1.count("\"gear_drop\"") == gd0, "%d" % (txt1.count("\"gear_drop\"") - gd0))
			check("...and it never went through the master's phases", txt1.count("\"boss_phase\"") == ph0)
			check("the floor's master is not marked dead by it", not G.has_flag("%s:boss:%s" % [str(lv.level_id), boss.etype]))
			boss.take_damage(999999999, "you")
			for i in 3:
				await process_frame
			var txt2 := FileAccess.get_file_as_string(G.playlog_path)
			check("the master itself still counts, once", txt2.count("\"boss_kill\"") == bk0 + 1, "%d" % (txt2.count("\"boss_kill\"") - bk0))
			check("...and still leaves its gear", txt2.count("\"gear_drop\"") >= gd0 + 1)
	print("polish199_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
