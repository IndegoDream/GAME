extends SceneTree
## Round 152: the pull -- teasers, sitting line, omens, barks, petting/feeding, streak titles, the first blade.
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
	G.save_path = "user://pull_save.json"
	G.save_base = "user://pull_slots"
	G.new_game()
	var P = G.sys("pull")
	check("system exists", P != null)
	# ---- data
	var roles: Dictionary = G.sys("menagerie").data["roles"]
	for r in roles:
		check("role %s has a bark" % r, (P.cfg["beast_barks"].get(r, []) as Array).size() >= 1)
	for st in ["guard", "scout", "striker"]:
		for ev in ["floor", "boss", "clear"]:
			check("%s has %s lines" % [st, ev], (P.cfg["human_barks"][st][ev] as Array).size() >= 1)
	for k in ["cache", "spirit", "sage"]:
		check("omen %s defined" % k, not P.omen_def(k).is_empty())
	# ---- teasers
	G.qi = G.qi_to_next() * 0.8
	var t: Array = P.teasers()
	check("a step 80%% along is a teaser (%s)" % str(t), t.size() >= 1 and str(t[0]).find("80") >= 0)
	G.qi = 0.0
	check("nothing near: no block (or only far ones)", P.teasers().filter(func(x): return str(x).find("next step") >= 0).is_empty())
	# ---- sitting line
	check("not sitting: no line", P.sit_line() == "")
	G.sitting = true
	P.tick(0.5)
	P._sit_t = 30.0
	P._sit_rate = 6.0
	var sl: String = P.sit_line()
	check("sitting line shows time and rate (%s)" % sl, sl.find("0:30") >= 0 and sl.find("6.0") >= 0)
	G.sitting = false
	# ---- omens
	var g0: int = G.gold
	P.collect("cache", Vector3.ZERO)
	check("a cache pays gold", G.gold > g0)
	var q0: float = G.qi
	P.collect("spirit", Vector3.ZERO)
	check("a spirit pays qi and a buff", G.qi > q0 and G.buff_left("pull_spirit") > 30.0)
	var i0: float = G.insight
	P.collect("sage", Vector3.ZERO)
	check("a sage pays insight and a buff", G.insight > i0 and G.buff_left("pull_sage") > 30.0)
	check("omens are counted", P.omens_found == 3)
	var saved: Dictionary = P.save_state()
	P.reset()
	P.load_state(saved)
	check("the count saves", P.omens_found == 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for i in 200:
		seen[P.pick_omen(rng)] = true
	check("all three omens come up", seen.size() == 3)
	check("compass reads", P._compass(Vector2(0, -10)) == "north" and P._compass(Vector2(10, 0)) == "east" and P._compass(Vector2(0, 10)) == "south")
	# ---- petting and feeding
	G.familiar = {"species": "cave_hare", "name": "Tuft", "bond": 5.0}
	var b: Dictionary = G.familiar
	var msg: String = P.pet(b)
	check("petting adds bond", float(b["bond"]) > 5.5 and msg.find("Tuft") >= 0)
	var b1 := float(b["bond"])
	P.pet(b)
	check("...but not again straight away", is_equal_approx(float(b["bond"]), b1))
	check("no food: it says so", P.feed(b).find("nothing to feed") >= 0)
	G.add_item("raw_meat", 2, false)
	var m0: int = G.count("raw_meat")
	var f1: String = P.feed(b)
	check("feeding costs one and adds bond", G.count("raw_meat") == m0 - 1 and float(b["bond"]) > b1 + 1.5 and f1.find("wolfs") >= 0)
	P.feed(b)
	check("...with a rest between", G.count("raw_meat") == m0 - 1)
	check("a hare bark exists", P.beast_line(b) != "")
	# ---- forms (round 153)
	var MN = G.sys("menagerie")
	for r in MN.data["roles"]:
		var fr: Dictionary = MN.forms["roles"].get(r, {})
		check("role %s has a form" % r, not fr.is_empty() and str(fr["title2"]) != "" and str(fr["title3"]) != "" and not (fr["awaken"] as Dictionary).is_empty())
		for k in fr.get("awaken", {}):
			check("form %s awaken key %s is read" % [r, k], str(k) in G.ADDITIVE_KEYS or str(k) in ["damage_mult", "damage_taken", "insight_mult", "move_mult", "bond_mult", "meditate_mult", "qi_mult", "ranged_mult", "swarm_mult", "hp_mult", "attack_speed", "cleanse_speed"] or str(k).begins_with("craft_"))
	var hare := {"species": "cave_hare", "name": "Tuft", "bond": 20.0}
	check("no form before fierce", MN.form_of(hare).is_empty())
	hare["bond"] = 110.0
	var f2: Dictionary = MN.form_of(hare)
	check("fierce: titled, not awakened", f2.get("title", "") == "Root-wise" and not f2["awakened"])
	hare["bond"] = 180.0
	var f3: Dictionary = MN.form_of(hare)
	check("spirit beast: awakened", f3.get("title", "") == "Greenmother's pick" and f3["awakened"])
	G.familiar = {"species": "cave_hare", "name": "Tuft", "bond": 110.0, "tier": 0}
	var gc0: float = G.tech_effect("gather_chance", 0.0)
	G.familiar["bond"] = 180.0
	var gc1: float = G.tech_effect("gather_chance", 0.0)
	check("awakening adds a gift (%.3f -> %.3f)" % [gc0, gc1], gc1 > gc0 + 0.02)
	check("the title shows the form", G.familiar_title(G.familiar).find("Greenmother") >= 0)
	check("the beast lines name the form", MN.beast_lines(G.familiar).any(func(l): return str(l).find("Awakened") >= 0))
	var BeastS = load("res://scripts/actors/Beast.gd")
	for nm in ["hare", "boar", "stag", "fox", "lizard", "toad", "crab", "hawk", "worm", "tortoise"]:
		var prev := -1
		var strict := true
		for stg in 4:
			var bm = BeastS.build(nm, Color(0.6, 0.5, 0.4))
			bm.evolve(stg, Color(1.0, 0.5, 0.2))
			var n := 0
			var stack: Array = [bm]
			while not stack.is_empty():
				var cur = stack.pop_back()
				n += 1
				for ch in cur.get_children():
					stack.append(ch)
			if n <= prev:
				strict = false
			prev = n
			bm.free()
		check("%s: each stage adds to the body" % nm, strict)
	# ---- streak titles
	P.award_streak(7)
	check("a 7 day streak earns a name", G.titles.has("Steady Footed"))
	P.award_streak(7)
	check("...once", G.titles.count("Steady Footed") == 1)
	P.award_streak(5)
	check("no name on day 5", not G.titles.has(""))
	# ---- the first blade
	G.weapon = ""
	G.flags.erase("fs:gift")
	G.log_event("talk", {"npc": "Elder Mo", "role": "elder"})
	check("Elder Mo hands over a blade", G.weapon == "iron_sword" and G.has_flag("fs:gift"))
	var w0: String = G.weapon
	G.log_event("talk", {"npc": "Elder Mo", "role": "elder"})
	check("only once", G.weapon == w0 and G.count("iron_sword") <= 1)
	G.rivals = {"Ashen Vale": {"met": 3, "beat": 1, "lost": 2}, "Iri": {"met": 2, "beat": 2, "lost": 0}}
	check("the rival who has won more is the nemesis", P.nemesis() == "Ashen Vale")
	G.rivals = {}
	check("no rivals, no nemesis", P.nemesis() == "")
	# ---- the world: omens on floors, the landmark in the village and valley
	var omens := 0
	for i in 14:
		var l8 = load("res://scripts/world/Level.gd").new()
		l8.name = "LevelO%d" % i
		l8.build(G.load_level_def("floor%d" % (i + 2)))
		root.add_child(l8)
		var here: int = l8.get_children().filter(func(c): return c.is_in_group("omen")).size()
		omens += here
		check("never more than one omen on a floor", here <= 1)
		l8.queue_free()
	G.current_level = "floor8"
	P.collect("cache", Vector3.ZERO)
	var again = load("res://scripts/world/Level.gd").new()
	again.name = "LevelAgain"
	again.build(G.load_level_def("floor8"))
	root.add_child(again)
	check("a taken omen stays gone for the day", again.get_children().filter(func(c): return c.is_in_group("omen")).is_empty())
	again.queue_free()
	check("omens turn up on floors (%d over 14)" % omens, omens >= 2 and omens <= 12)
	for lid in ["village", "valley"]:
		var lv = load("res://scripts/world/Level.gd").new()
		lv.name = "LevelL_" + lid
		lv.build(G.load_level_def(lid))
		root.add_child(lv)
		check("%s has the Heaven Gate landmark" % lid, lv.spawns.has("landmark"))
		var lbl := false
		for c in lv.get_children():
			for cc in c.get_children():
				if cc is Label3D and str(cc.text).find("HEAVEN GATE") >= 0:
					lbl = true
		check("%s's landmark is signed" % lid, lbl)
		lv.queue_free()
	var tl = load("res://scripts/world/Level.gd").new()
	tl.name = "LevelT"
	tl.build(G.load_level_def("floor5"))
	root.add_child(tl)
	check("a town (floor 5 haven) has no omen", tl.get_children().filter(func(c): return c.is_in_group("omen")).is_empty())
	tl.queue_free()
	print("PULL CHECK %d passed, %d failed" % [total - fails, fails])
	quit(fails)
