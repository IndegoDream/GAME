extends SceneTree
## Round 142b: "what do you want your first days to be like?" -- four equal answers that reorder the guided first steps.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _fresh() -> void:
	G.save_path = "user://pace_save.json"
	G.save_base = "user://pace_slots"
	G.new_game()
	G.playtime = 10.0


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	var qs: Array = G.creation_data()["questions"]
	var q: Dictionary = {}
	for x in qs:
		if str(x["id"]) == "pace":
			q = x
	check("a pace question exists, before the last one", not q.is_empty() and str(qs[qs.size() - 1]["id"]) == "road" and str(qs[qs.size() - 2]["id"]) == "pace")
	check("it has four answers: fighter, crafter, wanderer, scholar", q["answers"].map(func(a): return a.get("pace", "")) == ["fighter", "crafter", "wanderer", "scholar"])
	check("every answer is worth the same: one point", q["answers"].all(func(a): return (a.get("attrs", {}) as Dictionary).values().reduce(func(x, y): return x + y, 0) + int(a.get("free", 0)) == 1))
	check("every answer has a note that says what it does", q["answers"].all(func(a): return str(a.get("note", "")).length() > 20))
	for a in q["answers"]:
		for it in a.get("gift", {}).get("items", {}):
			check("gift %s is an item" % it, G.items.has(str(it)))
		for sk in a.get("gift", {}).get("skill_xp", {}):
			check("gift skill %s exists" % sk, G.skill_name(str(sk)) != "")
	# the steps, per pace
	var base_ids := ["fs:talk", "fs:bag", "fs:weapon", "fs:floor", "fs:kill", "fs:path", "fs:journal", "fs:meditate"]
	for p in G.PACE_ORDER:
		var ord: Array = G.PACE_ORDER[p]
		check("%s's order has every standard first step once" % p, base_ids.all(func(b): return ord.count(b) == 1))
		check("%s's extras have text" % p, ord.all(func(f): return base_ids.has(f) or G.PACE_STEP_TEXT.has(f)))
	var firsts := {}
	for p in ["", "fighter", "crafter", "wanderer", "scholar"]:
		_fresh()
		if p != "":
			G.set_flag("pace:" + p)
		check("pace() reads %s" % p, G.pace() == p)
		var lines: Array = G.first_steps()
		firsts[p] = str(lines[0]) if lines.size() > 0 else ""
		check("%s has a first step to show" % p, firsts[p] != "")
	check("no pace and the old order are the same as before: talk to Elder Mo", firsts[""].find("Elder Mo") >= 0)
	check("fighter starts with a weapon", firsts["fighter"].find("weapon") >= 0)
	check("crafter starts with Elder Mo, then a bench", firsts["crafter"].find("Elder Mo") >= 0)
	check("scholar and wanderer both start with Elder Mo (the story begins there)", firsts["scholar"].find("Elder Mo") >= 0 and firsts["wanderer"].find("Elder Mo") >= 0)
	# walking a crafter through
	_fresh()
	G.set_flag("pace:crafter")
	G.log_event("talk", {"role": "elder"})
	G.set_flag("fs:bag")
	var l: Array = G.first_steps()
	check("crafter: after Mo and the bag, make something at a bench", l.size() == 1 and str(l[0]).find("bench") >= 0)
	G.log_event("craft", {"makes": "x", "success": false})
	check("a failed craft doesn't count", str(G.first_steps()[0]).find("bench") >= 0)
	G.log_event("craft", {"makes": "x", "success": true})
	check("a made thing does", G.has_flag("fs:craft") and str(G.first_steps()[0]).find("bench") < 0)
	# wanderer: waystone, scholar: lesson
	_fresh()
	G.set_flag("pace:wanderer")
	for f in ["fs:talk", "fs:weapon", "fs:floor"]:
		G.set_flag(f)
	check("wanderer: after the way down, a waystone", str(G.first_steps()[0]).find("waystone") >= 0)
	G.log_event("waystone", {"id": "floor5"})
	check("a waystone woken ticks it", G.has_flag("fs:waystone"))
	_fresh()
	G.set_flag("pace:scholar")
	for f in ["fs:talk", "fs:bag"]:
		G.set_flag(f)
	check("scholar: a lesson", str(G.first_steps()[0]).find("teacher") >= 0)
	G.log_event("lesson", {"npc": "x", "kind": "y"})
	check("a lesson ticks it", G.has_flag("fs:lesson"))
	# finishing creation sets the flag and pays the gift
	_fresh()
	G.flags.erase("creation_done")
	var ans := {}
	for x in qs:
		ans[str(x["id"])] = 0
	ans["pace"] = 3
	var ins0: float = G.insight
	check("creation finishes", G.creation_finish("Tester", {"sex": "m"}, ans) == "")
	check("choosing 'answers' makes you a scholar", G.pace() == "scholar")
	check("...and the scholar's gift is paid (insight)", G.insight > ins0)
	_fresh()
	G.flags.erase("creation_done")
	ans["pace"] = 1
	G.creation_finish("Tester", {"sex": "m"}, ans)
	check("choosing the bench makes you a crafter", G.pace() == "crafter")
	check("...and the crafter practiced", G.skill_level("smithing") >= 1)
	print("PACE CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
