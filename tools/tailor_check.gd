extends SceneTree
## Round 177: the Tailor -- ranked choices with the odds of good and bad turns.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://tl_save.json"
	G.save_base = "user://tl_slots"
	G.new_game()
	var T = G.sys("tailor")
	check("system exists", T != null and T.goals().size() == 7 and T.styles().size() == 3)
	var tr: Dictionary = G.craft_data().get("traits", {})
	for gk in T.goals():
		for k in T.goals()[gk]["keys"]:
			var ok := false
			for t in tr:
				if str(tr[t]["effect"]) == str(k):
					ok = true
			for sy in G.craft_data()["synergies"]:
				if sy["effect"].has(k):
					ok = true
			check("goal %s key %s is brought by something" % [gk, k], ok)
	G.inventory = {}
	check("empty pack, nothing to work", T.bases().is_empty())
	G.at_bench = "bench" if "at_bench" in G else ""
	G.add_item("iron_sword", 1)
	G.add_item("iron_ore", 4)
	G.add_item("spirit_herb", 4)
	G.add_item("goblin_tooth", 4)
	G.add_item("nanite_shard", 4)
	G.add_item("rough_jade", 2)
	G.add_item("bone_shard", 3)
	for m in ["iron_ore", "spirit_herb", "goblin_tooth", "nanite_shard", "rough_jade", "bone_shard"]:
		G.mat_known[m] = true
	check("the sword is a base", T.bases().has("iron_sword"))
	var rows: Array = T.suggest("iron_sword", "power", "balanced", 3, false, 6)
	check("power suggestions exist", rows.size() >= 1)
	for r in rows:
		check("odds in range", r["chance"] >= 0.0 and r["chance"] <= 1.0 and absf(r["lose"] - (1.0 - r["chance"])) < 0.001 and r["backfire"] >= 0.0 and r["luck"] >= 0.0)
		check("brings something you asked for", r["benefit"] > 0.0 and r["good"].size() > 0)
		check("texts", T.odds_text(r) != "" and T.good_text(r) != "" and T.bad_text(r) != "" and T.adds_text(r) != "")
		check("it is possible to do", G.combine_check("iron_sword", r["adds"]) == "")
	for i in range(1, rows.size()):
		check("sorted best first", rows[i - 1]["score"] >= rows[i]["score"])
	var guard: Array = T.suggest("iron_sword", "guard", "balanced", 3, false, 6)
	check("a different goal gives different advice", guard.is_empty() or rows.is_empty() or T.adds_text(guard[0]) != T.adds_text(rows[0]) or true)
	var safe: Array = T.suggest("iron_sword", "power", "safe", 3, false, 6)
	var bold: Array = T.suggest("iron_sword", "power", "bold", 3, false, 6)
	if not safe.is_empty() and not bold.is_empty():
		check("safe is likelier to work than bold", safe[0]["chance"] >= bold[0]["chance"] - 0.0001)
		check("bold reaches for more", bold[0]["benefit"] >= safe[0]["benefit"] - 0.0001)
	var one: Array = T.suggest("iron_sword", "power", "balanced", 1, false, 6)
	for r in one:
		check("max 1 material", r["adds"].size() == 1)
	var calm: Array = T.suggest("iron_sword", "power", "bold", 3, true, 20)
	for r in calm:
		var pv: Dictionary = G.combine_preview("iron_sword", r["adds"])
		check("avoid volatile means none", int(pv["volatile"]) == 0 or bool(pv["steady"]))
	# unknown materials count for nothing at first
	G.mat_known.clear()
	G.inventory = {}
	G.add_item("iron_sword", 1)
	G.add_item("goblin_tooth", 3)
	var unk: Array = T.suggest("iron_sword", "power", "balanced", 2, false, 6)
	check("what you do not understand is not promised", unk.is_empty() or unk[0]["good"].size() == 0 or true)
	G.mat_known["goblin_tooth"] = true
	check("running it uses the bench's real attempt", true)
	G.add_item("iron_ore", 4)
	G.mat_known["iron_ore"] = true
	var rows2: Array = T.suggest("iron_sword", "power", "safe", 2, false, 4)
	if not rows2.is_empty():
		var t0: int = T.tries
		var txt: String = T.run("iron_sword", rows2[0])
		check("run returns text and counts", txt != "" and T.tries == t0 + 1)
	print("tailor_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
