extends SceneTree
## round 126b: every wave of the Ember Gauntlet really builds as a ring with the right foes.
var passed := 0
var failed := 0
var f := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.save_path = "user://gt_save.json"
	G.save_base = "user://gt_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	for depth in [1, 4, 9, 20, 40]:
		var st: Dictionary = G.Hook.gauntlet_build(depth)
		for i in st["rounds"].size():
			st["stage"] = i
			var lid: String = G.Arena.make_id("village", "gauntlet", i)
			var lv: Dictionary = G.Arena.generate(lid, st)
			check("d%d wave %d builds" % [depth, i + 1], not lv.is_empty() and lv.get("arena", false) == true)
			var want := 0
			for fo in st["rounds"][i]:
				want += int(fo["count"])
				var eid := str(fo["id"])
				check("d%d wave %d foe %s exists" % [depth, i + 1, eid], G.enemies.has(eid) or st["defs"].has(eid), eid)
			var got := 0
			var en: Dictionary = lv.get("enemies", {})
			for row in lv["map"]:
				for ch in str(row):
					if en.has(ch):
						got += 1
			check("d%d wave %d has %d foes" % [depth, i + 1, want], got == want, "%d" % got)
	# a full loss and a full win leave the arena clean
	G.hp = G.max_hp()
	G.Hook.gauntlet_start()
	G.arena_lost("test")
	check("a loss ends the run", not G.arena_active() and str(G.arena.get("result", "")) == "gauntlet" and not G.arena.get("won", true))
	for fn in DirAccess.get_files_at("user://"):
		if fn.begins_with("gt_"):
			DirAccess.remove_absolute("user://" + fn)
	print("GAUNTLET CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
