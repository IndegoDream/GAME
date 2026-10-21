extends SceneTree
## Round 148: the road workshop and the sects' techniques.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _find_text(n: Node, needle: String) -> int:
	var c := 0
	if (n is Label or n is Button) and str(n.text).find(needle) >= 0:
		c += 1
	for ch in n.get_children():
		c += _find_text(ch, needle)
	return c


func _finish_line(WS, id: String) -> void:
	## walk a line to its end, doing every step the quick way
	WS.start(id)
	var guard := 0
	while WS.act.has(id) and guard < 40:
		guard += 1
		var s: Dictionary = WS.cur(id)
		match str(s["kind"]):
			"give":
				for it in s["items"]:
					G.add_item(str(it), int(s["items"][it]), false)
				WS.hand_over(id)
			"craft", "kills", "sit":
				WS.act[id]["prog"] = 9999.0
				WS._auto()
			"depth":
				G.depth = maxi(G.depth, int(s["floor"]))
				WS._auto()
			"skill":
				G.skills[str(s["skill"])] = 10.0 * float(int(s["level"]) * int(s["level"]) + 1)
				WS._auto()
			"inner":
				G.sys("inner_world").xp = 99999.0
				WS._auto()
			"rank":
				G.guilds[str(s["guild"])] = {"rep": 99999.0}
				if str(s["guild"]) == "academy":
					G.academy["enrolled"] = true
					G.academy["rank"] = int(s["rank"])
				WS._auto()


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://ws_save.json"
	G.save_base = "user://ws_slots"
	G.new_game()
	G.current_level = "village"
	var WS = G.sys("workshop")
	var IW = G.sys("inner_world")
	check("ten lines: four bench stages, six sect lines", WS.lines().size() == 10 and WS.lines().filter(func(l): return l["kind"] == "workshop").size() == 4)
	var steps := 0
	var ok_items := true
	for l in WS.lines():
		steps += (l["steps"] as Array).size()
		for s in l["steps"]:
			for it in s.get("items", {}):
				if not G.items.has(str(it)):
					ok_items = false
			if str(s["kind"]) == "rank" and not G.guild_defs.has(str(s["guild"])):
				ok_items = false
			if str(s["kind"]) == "skill" and not G.skill_defs.has(str(s["skill"])):
				ok_items = false
	check("60+ steps in all, every item/guild/skill is real", steps >= 60 and ok_items)
	var longest := 0
	for l in WS.lines():
		longest = maxi(longest, (l["steps"] as Array).size())
	check("the World-Seed is the longest chain", (WS.line("heaven")["steps"] as Array).size() == longest)
	check("the chains get longer as the items get better", (WS.line("table")["steps"] as Array).size() < (WS.line("master")["steps"] as Array).size())
	# status and locks
	check("table is open, forge locked", WS.status("table") == "open" and WS.status("forge") == "locked" and WS.status("heaven") == "locked")
	check("locked line cannot start", WS.start("forge") == "" and not WS.act.has("forge"))
	check("no bench yet", not G.road_bench() and not G.field_forge() and WS.effects().is_empty())
	# table line
	check("start table", WS.start("table") != "" and WS.status("table") == "active")
	var s0: Dictionary = WS.cur("table")
	check("step 1 is a hand-in", s0["kind"] == "give" and not WS.ready("table"))
	check("hand over refused without items", WS.hand_over("table") == "" and int(WS.act["table"]["step"]) == 0)
	G.add_item("iron_ore", 6, false)
	check("half the goods is not ready", not WS.ready("table"))
	G.add_item("beast_hide", 3, false)
	check("ready with the goods", WS.ready("table"))
	var ore0: int = G.count("iron_ore")
	WS.hand_over("table")
	check("goods are taken and the step advances", G.count("iron_ore") == ore0 - 6 and int(WS.act["table"]["step"]) == 1)
	# craft count
	WS.on_event("craft", {"makes": "healing_salve", "success": true})
	check("a craft counts", int(WS.progress("table")[0]) == 1)
	WS.on_event("craft", {"makes": "healing_salve", "success": false})
	check("a failed craft does not", int(WS.progress("table")[0]) == 1)
	for i in 5:
		WS.on_event("craft", {"makes": "healing_salve", "success": true})
	check("six crafts advance the step", int(WS.act["table"]["step"]) == 2)
	WS.act["table"]["step"] = 3
	WS.on_event("craft", {"makes": "healing_salve", "success": true})
	check("an easy craft does not count when a harder one is asked (difficulty 6+)", int(WS.progress("table")[0]) == 0)
	# kills by floor
	WS.act["seed"] = {"step": 3, "prog": 0.0}
	WS.on_event("kill", {"type": "goblin"})
	check("a floor-1 kill does not count toward floor-6+", int(WS.progress("seed")[0]) == 0)
	WS.on_event("kill", {"type": "thornling"})
	check("a floor-6 kill does", int(WS.progress("seed")[0]) == 1)
	WS.act.erase("seed")
	# max active
	# complete the table
	_finish_line(WS, "table")
	check("table done, effects, bench anywhere", WS.status("table") == "done" and G.road_bench() and WS.effects().size() == 1)
	check("forge now open", WS.status("forge") == "open")
	var ins0: float = G.insight
	_finish_line(WS, "forge")
	check("forge: field forge", G.field_forge() and WS.has("forge"))
	check("two lines at most", WS.start("step") != "" and WS.start("eye") != "" and WS.start("hands").find("two lines") >= 0 and WS.act.size() == 2 and not WS.act.has("hands"))
	WS.abandon("step")
	WS.abandon("eye")
	check("finishing pays insight", G.insight > ins0)
	_finish_line(WS, "roll")
	check("roll: rune table anywhere", G.rune_table_anywhere())
	_finish_line(WS, "master")
	var cs := 0.0
	for e in WS.effects():
		cs += float(e.get("craft_success", 0.0))
	check("master kit adds craft_success and craft_quality", cs >= 0.08 and WS.has("master"))
	check("craft_success reaches the game's effect sum", G.tech_effect("craft_success", 0.0) >= 0.08)
	# sect lines
	check("heaven still locked (needs the seed)", WS.status("heaven") == "locked" and WS.missing_needs("heaven").size() == 1)
	_finish_line(WS, "seed")
	check("seed done", WS.has("seed"))
	# inner world integration
	IW.xp = 0.0
	G.integration = 700.0
	var cap0: int = IW.capacity()
	check("seed: +2 habitat places", cap0 == 1 + IW.level() + 2)
	check("seed: xp x1.5", true)
	IW.xp = 0.0
	IW._lvl = 1
	IW._add_xp(10.0, false)
	check("seed grows the realm half again as fast", absf(IW.xp - 15.0) < 0.01)
	IW.xp = 99999.0
	check("level capped at 6 with the seed alone", IW.level() == 6 and IW.next_at() < 0.0 and IW.level_cap() == 6)
	check("seed: +1 plot", IW.plot_count() >= 5)
	_finish_line(WS, "hands")
	_finish_line(WS, "heaven")
	check("World-Seed done, cap now 8 (seed, hands, heaven)", WS.has("heaven") and IW.level() == 8)
	IW.meters = {"qi": 100.0, "flora": 100.0, "fauna": 100.0}
	check("heaven strengthens the realm's gifts", float(IW.effects()[0]["qi_mult"]) > 1.08)
	# other sect effects reach the game
	_finish_line(WS, "step")
	_finish_line(WS, "breath")
	_finish_line(WS, "eye")
	check("all ten lines done", WS.done.size() == 10)
	IW.xp = 99999.0
	check("every sect line raised the ceiling to the top", IW.level() == 10 and IW.improvements().size() == 6)
	check("effects merge (move_mult, regen, gather)", G.tech_effect("move_mult", 1.0) > 1.0 and G.tech_effect("regen", 0.0) >= 0.2 and G.tech_effect("gather_bonus", 0.0) >= 0.25)
	# save / load
	WS.done.erase("eye")
	WS.act["eye"] = {"step": 2, "prog": 4.0}
	var st: Dictionary = WS.save_state()
	WS.reset()
	WS.load_state(st)
	check("save/load keeps done and act", WS.done.size() == 9 and int(WS.act["eye"]["step"]) == 2 and float(WS.act["eye"]["prog"]) == 4.0)
	WS.load_state({"done": {"nonsense": true, "table": true}, "act": {"forge": {"step": 999, "prog": -5}, "zzz": {}}})
	check("bad data is sanitised", WS.done.size() == 1 and int(WS.act["forge"]["step"]) == 5 and float(WS.act["forge"]["prog"]) == 0.0 and not WS.act.has("zzz"))
	# online
	WS.reset()
	G.current_level = "online:gate1"
	check("cannot begin online", WS.start("table").find("online") >= 0 and WS.act.is_empty())
	G.current_level = "village"
	# sit
	WS.reset()
	WS.act["seed"] = {"step": 4, "prog": 0.0}
	G.sitting = true
	WS.tick(3600.0)
	G.sitting = false
	check("sitting counts minutes", int(WS.progress("seed")[0]) >= 60)
	# hub
	WS.reset()
	var hub = load("res://scripts/ui/Hub.gd")
	check("hub script loads", hub != null)
	print("WORKSHOP CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
