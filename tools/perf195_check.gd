extends SceneTree
## round 195: the per-frame readers (fx_now, max_hp(true)) use a kept effect list instead of rebuilding it every call;
## tech_effect() stays exact and sees every change at once.
## And the autosave checks its file without parsing it twice.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://p195_save.json"
	G.save_base = "user://p195_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	G.techniques.erase("iron_skin")
	G.fx_dirty()
	var base: float = G.tech_effect("damage_taken", 1.0)
	# the same frame: a change is seen at once
	G.learn("iron_skin", "test", true)
	check("a technique learned is seen in the same frame", is_equal_approx(G.tech_effect("damage_taken", 1.0), base * 0.85), "%f vs %f" % [G.tech_effect("damage_taken", 1.0), base * 0.85])
	G.techniques.erase("iron_skin")           # (straight into the dictionary, no signal)
	check("...and one removed straight from the dictionary too", is_equal_approx(G.tech_effect("damage_taken", 1.0), base), str(G.tech_effect("damage_taken", 1.0)))
	G.add_buff("p195", {"damage_taken": 0.5}, 60.0)
	check("a buff is seen at once", is_equal_approx(G.tech_effect("damage_taken", 1.0), base * 0.5), str(G.tech_effect("damage_taken", 1.0)))
	G.buffs.erase("p195")
	G.stats_changed.emit()
	check("a buff gone is gone at once", is_equal_approx(G.tech_effect("damage_taken", 1.0), base))
	# cost: many calls, one build
	var b0: int = G.fx_builds
	var t0 := Time.get_ticks_usec()
	for i in 200:
		G.fx_now("damage_taken", 1.0)
		G.max_hp(true)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check("400 per-frame reads build the list at most once", G.fx_builds - b0 <= 1, str(G.fx_builds - b0))
	check("...and take under 40 ms", ms < 40.0, "%.1f ms" % ms)
	# across frames: kept, but time-bound effects catch up within a quarter second
	G.add_buff("p195b", {"damage_taken": 0.5}, 0.4)
	check("a short buff counts", is_equal_approx(G.fx_now("damage_taken", 1.0), base * 0.5))
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 900:
		await process_frame
	check("...and a quarter second after it runs out the kept list no longer has it", is_equal_approx(G.fx_now("damage_taken", 1.0), base), str(G.fx_now("damage_taken", 1.0)))
	# a system's own state changed directly (no signal): tech_effect sees it at once, fx_now within FX_KEEP_MS
	var D = G.sys("dao")
	if D != null and D.has_method("dao_fx"):
		D.pts["blade"] = 1500.0
		D.sense = 1200.0
		var before: float = G.tech_effect("damage_mult", 1.0)
		G.fx_now("damage_mult", 1.0)
		D.focus = "blade" if str(D.focus) != "blade" else ""
		check("a system's state changed straight in: tech_effect sees it in the same frame", not is_equal_approx(G.tech_effect("damage_mult", 1.0), before))
		var t3 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t3 < 400:
			await process_frame
		check("...and fx_now within a moment", is_equal_approx(G.fx_now("damage_mult", 1.0), G.tech_effect("damage_mult", 1.0)))
	# the safe save: still keeps a .bak, still refuses to lose the old one
	G.save_game()
	G.gold = 12345
	G.save_game()
	check("the save is written", FileAccess.file_exists(G.save_path))
	check("...the last good one kept as .bak", FileAccess.file_exists(G.save_path + ".bak"))
	var d = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
	check("...and the save reads back with the new gold", d is Dictionary and int(d.get("gold", 0)) == 12345)
	var fb := FileAccess.open(G.save_path, FileAccess.WRITE)
	fb.store_string("{ this is not json")
	fb.close()
	G._wrote_good.clear()                      # (as on the next run of the game)
	G.save_game()
	var broken := 0
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("p195_save.json.broken-") or (f.begins_with("p195_save") and f.contains("broken")):
			broken += 1
	check("a save file that won't read is kept aside, not written over", broken >= 1, str(DirAccess.get_files_at("user://")))
	var d2 = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
	check("...and the new save is good", d2 is Dictionary)
	var t2 := Time.get_ticks_usec()
	G.save_game()
	var sm := (Time.get_ticks_usec() - t2) / 1000.0
	check("a second save this run is quick", sm < 1000.0, "%.1f ms" % sm)
	# round 196: healing with a big HP pool -- the survival XP goes in once a second, not every physics tick
	var PL = load("res://scripts/actors/Player.gd")
	G.skills["survival"] = 2000.0
	var sk0: float = float(G.skills["survival"])
	var calls := [0]
	var cb := func(): calls[0] += 1
	G.stats_changed.connect(cb)
	var pl = PL.new()
	pl.set("_calm_t", 99.0)
	G.hp = 1
	for i in 120:                                   # two seconds of physics ticks
		pl._regen(1.0 / 60.0)
	G.stats_changed.disconnect(cb)
	check("two seconds of healing: HP went up", G.hp > 1, str(G.hp))
	check("...survival XP still earned", float(G.skills["survival"]) > sk0, "%f -> %f" % [sk0, float(G.skills["survival"])])
	check("...with a handful of updates, not one a tick", calls[0] <= 4, "%d stats_changed" % calls[0])
	pl.free()
	# round 196: the HUD redraws once a frame however many changes come in
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/HUD.gd")
	check("the HUD listens through _refresh_soon (once a frame)", hud_src.contains("Game.stats_changed.connect(_refresh_soon)"))
	# round 197: a held event (a kill, a blow) builds the list once, yet still sees an item gained in the middle of it
	G.fx_hold(true)
	var bh: int = G.fx_builds
	for i in 30:
		G.tech_effect("damage_mult", 1.0)
		G.tech_effect("hp_mult", 1.0)
	check("held: 60 asks, one build", G.fx_builds - bh <= 1, str(G.fx_builds - bh))
	var tid := ""
	for t in G.technique_defs:
		if not G.techniques.has(t) and (G.technique_defs[t].get("effect", {}) as Dictionary).has("damage_taken"):
			tid = t
			break
	if tid != "":
		var before_h: float = G.tech_effect("damage_taken", 1.0)
		G.techniques[tid] = true
		check("held: a technique learned mid-event is still seen (the signature moved)", not is_equal_approx(G.tech_effect("damage_taken", 1.0), before_h))
		G.techniques.erase(tid)
	G.fx_hold(false)
	check("released: exact again", G._fx_hold == 0)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("p195_"):
			DirAccess.remove_absolute("user://" + f)
	print("PERF195 CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
