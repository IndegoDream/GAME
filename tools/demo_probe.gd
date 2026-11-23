extends SceneTree
## 2026-11-03: the Steam demo, as a player would meet it. Run with ELIET_DEMO=1 (and a clean data/build_flavor.json):
##   ELIET_DEMO=1 godot --headless --path . --script res://tools/demo_probe.gd
## The demo backend is on; floors 1-5, the village and the valley are open; floor 6 and every Land deeper than floor 5 stop
## at the store window; the village has no Gate to the online world; the online menu says it's the full game's; the
## test kit is gone; the developer's crash banner never shows; the demo's mysteries are offered and the deep one is marked.
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
	G.save_path = "user://demo_probe_save.json"; G.save_base = "user://demo_probe_slots"; G.playlog_path = "user://demo_probe.jsonl"
	G.new_game()
	await process_frame
	var S = G.store
	check("the demo backend is on (ELIET_DEMO=1)", S.demo(), S.backend)
	var clean: bool = load("res://scripts/systems/Tester.gd").clean()
	if clean:
		check("the test kit is off in this build", not G.tester_unlocked())
	else:
		print("  (the source is in the test-kit flavor: the clean-build checks run when tools/build makes the demo)")
	check("three save slots (no full-game comforts)", G.SLOTS == 3)
	for id in ["village", "valley", "floor1", "floor5"]:
		check("%s is open" % id, S.travel_check(id) == "", S.travel_check(id))
	check("floor 6 is the store window", S.travel_check("floor6") == "locked")
	for rid in ["whisperwood", "bonefields", "crash_site"]:
		check("the %s gate stops at the store window" % rid, S.travel_check("frontier:" + rid) == "locked")
	var stopped := [false]
	G.unlock_wanted.connect(func(_l, _a): stopped[0] = true)
	G.go_to("frontier:whisperwood", "P")
	check("walking into Whisperwood is stopped, not loaded", stopped[0] and G.current_level != "frontier:whisperwood", G.current_level)
	check("the online menu says it's the full game's", G.online_blocked() != "")
	var lv = load("res://scripts/world/Level.gd").new()
	lv.build(G.load_level_def("village"))
	root.add_child(lv)
	await process_frame
	check("the village has no Gate to the online world", lv.spawns.get("gate", []).is_empty())
	lv.queue_free()
	await process_frame
	var ml = root.get_node_or_null("MemLog")
	if ml and clean:
		var before := root.get_child_count()
		ml._show_prev({"min": 3.0, "static_mb": 1, "peak_mb": 1, "tex_mb": 0, "vid_mb": 0, "fps": 60, "nodes": 1, "scene": "x"})
		await process_frame
		var shown := false
		for c in ml.get_children():
			if c is CanvasLayer:
				shown = true
		check("the crash banner never shows a player", not shown)
	var Q = G.sys("quests")
	G.journal["places"] = {"floor1": true, "floor5": true}
	check("Trader Wen offers the Empty Strongbox", Q.unlocked("myst_empty_strongbox"))
	check("Elder Mo offers the Founders' Cache", Q.unlocked("treasure_founders_cache"))
	check("the Ninth Lamp waits for the full game (unlocks at Floor 7)", not Q.unlocked("myst_ninth_lamp"))
	print("DEMO PROBE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
