extends SceneTree
## 2026-11-03: the mysteries and treasure hunts (data/mysteries.json, scripts/systems/Quests.gd _mysteries).
##   godot --headless --path . --script res://tools/mystery_check.gd
## Proves: every clue is a readable item; every giver and witness exists where the quest says; every clue's "near"
## resolves in its real level and the clue is built there (subtle ones without a far diamond); an accusation needs
## its proof; endings pay (and charge) what they say; the demo marks the deep ones as the full game's.
var passed := 0
var failed := 0


func check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _npc_names() -> Dictionary:
	## every townsperson's name, by the place they stand in
	var out := {}
	var dir := DirAccess.open("res://levels")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + f))
		if d is Dictionary:
			for k in d.get("npcs", {}):
				var n = d["npcs"][k]
				if n is Dictionary:
					out[str(n.get("name", ""))] = f.trim_suffix(".json")
	var fr = JSON.parse_string(FileAccess.get_file_as_string("res://data/frontier.json"))
	for rid in fr.get("regions", {}):
		for n in fr["regions"][rid].get("npcs", []):
			if n is Dictionary:
				out[str(n.get("name", ""))] = "frontier:" + str(rid)          # the Lands' people
	return out


func _build(G, id: String):
	var lv = load("res://scripts/world/Level.gd").new()
	lv.name = "Level"
	lv.build(G.load_level_def(id))
	root.add_child(lv)
	return lv


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://myst_save.json"; G.save_base = "user://myst_slots"; G.playlog_path = "user://myst_playlog.jsonl"
	G.new_game()
	await process_frame
	var Q = G.sys("quests")
	Q.quiet = false
	var md = JSON.parse_string(FileAccess.get_file_as_string("res://data/mysteries.json"))
	check("data/mysteries.json reads", md is Dictionary)
	var ids := []
	for q in md.get("quests", []):
		ids.append(str(q["id"]))
	check("four mysteries and hunts are side quests now", ids.size() >= 4 and ids.all(func(i): return not Q.qdef(i).is_empty()), str(ids))
	check("the Quests page knows the two new kinds", Q.kind_name("mystery") == "Mysteries" and Q.kind_name("treasure") == "Treasure hunts")
	for cid in md.get("clues", {}):
		var it: Dictionary = G.items.get(str(cid), {})
		check("clue %s is an item you can read" % cid, bool(it.get("clue", false)) and str(it.get("desc", "")).contains(str(md["clues"][cid]["text"]).substr(0, 20)))
	# --- every name a quest talks to stands where the quest says ---
	var names := _npc_names()
	for qid in ids:
		var q: Dictionary = Q.qdef(qid)
		var giver := str(q.get("giver", ""))
		check("%s: its giver %s exists" % [qid, giver], names.has(giver), giver)
		if str(q.get("giver_at", "")) != "" and names.has(giver):
			check("%s: %s stands in %s" % [qid, giver, q["giver_at"]], names[giver] == str(q["giver_at"]), str(names.get(giver, "")))
		for st in q.get("stages", []):
			var g: Dictionary = st.get("goal", {})
			if g.has("talk"):
				var who := str(g["talk"])
				check("%s: %s exists" % [qid, who], names.has(who))
				if str(g.get("where", "")) != "" and names.has(who):
					check("%s: %s is in %s" % [qid, who, g["where"]], names[who] == str(g["where"]), str(names.get(who, "")))
			if g.has("find"):
				check("%s: clue %s is defined" % [qid, g["find"]["item"]], G.items.has(str(g["find"]["item"])))
	# --- every clue's spot resolves in the real level, and is built there ---
	var level_ids := {}
	for qid in ids:
		for st in Q.qdef(qid).get("stages", []):
			var f: Dictionary = st.get("goal", {}).get("find", {})
			if not f.is_empty():
				var place: String = Q._where(f)
				if not level_ids.has(place):
					level_ids[place] = []
				level_ids[place].append(f)
	for place in level_ids:
		var lv = _build(G, place)
		for f in level_ids[place]:
			var near := str(f.get("near", ""))
			if near != "":
				var at: Vector2i = lv.quest_spot_near(near, "check|" + str(f["item"]))
				check("%s: '%s' in %s has a spot" % [f["item"], near, place], at.x >= 0)
				if at.x >= 0:
					check("%s: the spot is walkable ground" % f["item"], lv.is_walkable_char(lv.char_at(at)), lv.char_at(at))
		lv.queue_free()
		await process_frame
	# --- the strongbox, played: clue in the village by Wen's stall, then the accusation ---
	G.journal["places"] = {"floor1": true, "floor5": true}
	G.current_level = "village"
	var sid := "myst_empty_strongbox"
	check("the strongbox opens once you've been down", Q.unlocked(sid))
	Q.accept(sid)
	var sp: Array = Q.spawns_for("village")
	check("the first clue waits in the village, by Wen", sp.size() == 1 and str(sp[0].get("near", "")) == "M", str(sp))
	var lv = _build(G, "village")
	var objs: Array = []
	for n in lv.get_children():
		if n.is_in_group("quest_object") or (n.get_script() != null and str(n.get_script().resource_path).ends_with("QuestObject.gd")):
			objs.append(n)
	check("the clue is built in the village (towns hold a quest's thing where it says)", objs.size() == 1, str(objs.size()))
	if objs.size() == 1:
		var wen: Vector2i = lv.spawns["M"][0]
		var oc: Vector2i = objs[0].cell
		check("...within a few steps of Wen's stall", maxi(absi(oc.x - wen.x), absi(oc.y - wen.y)) <= 16, "%s vs %s" % [oc, wen])
		check("...and marked (a whodunit's clues show)", not objs[0].subtle)
	lv.queue_free()
	await process_frame
	Q.found(sid, "mc_soot_print")
	check("finding it moves to Smith Hale", str(Q.goal(sid).get("talk", "")) == "Smith Hale", str(Q.goal(sid)))
	Q.advance(sid)            # Hale
	Q.advance(sid)            # Pell
	Q.found(sid, "mc_marked_coin")
	Q.advance(sid)            # Lin
	check("Shellhaven's tally is a Floor 5 clue", Q.goal_place(sid) == "floor5" and Q.goal_floor(sid) == 5, Q.goal_place(sid))
	var acc: Dictionary = (Q.qdef(sid)["stages"] as Array)[-1]
	var truth: Dictionary = acc["choices"][0]
	var pay: Dictionary = acc["choices"][3]
	check("without the tally you can't name Lin", not Q._choice_open(truth))
	G.gold = 0
	check("without ninety gold you can't make it good yourself", not Q._choice_open(pay))
	Q.found(sid, "mc_lotus_tally")
	check("with the tally you can", Q._choice_open(truth))
	check("the accusation shows what you hold", Q.casebook(sid).size() == 3, str(Q.casebook(sid)))
	G.add_item("gold", 100)
	Q.advance(sid, "pay")
	check("paying it back costs ninety of your own gold", int(G.gold) == 10, str(G.gold))
	check("...and the quest is done that way", str(Q.done.get(sid, "")) == "pay")
	check("its clues are gone with it", G.count("mc_lotus_tally") == 0 and G.count("mc_soot_print") == 0)
	# --- the treasure hunt: subtle, and the riddle leads across three places ---
	var tid := "treasure_founders_cache"
	Q.accept(tid)
	var ts: Array = Q.spawns_for("village")
	check("the hunt's first find is by the fountain, unmarked", ts.size() == 1 and str(ts[0]["near"]) == "fountain" and bool(ts[0]["subtle"]), str(ts))
	var lv2 = _build(G, "village")
	var tobj = null
	for n in lv2.get_children():
		if n.is_in_group("quest_object"):
			tobj = n
	check("the disc is built", tobj != null)
	if tobj != null:
		check("...near the fountain", (tobj.cell - lv2.fountain_cell()).length() <= 12.0, str(tobj.cell))
		check("...and only glints when you're nearly on it", tobj.subtle and tobj.SUBTLE_RANGE < tobj.MARK_RANGE)
	lv2.queue_free()
	await process_frame
	Q.found(tid, "tc_verdigris_disc")
	Q.found(tid, "tc_river_stone")
	check("the third word is on Floor 1, by the way down", Q.goal_place(tid) == "floor1" and str(Q.goal(tid)["find"]["near"]) == "stairs")
	Q.found(tid, "tc_black_tablet")
	Q.found(tid, "tc_founders_box")
	Q.advance(tid)
	check("the cache pays the Founders' Signet and a name", G.count("founders_signet") == 1 and G.titles.has("One Who Listened"))
	# --- the Ninth Lamp: the deep, and the demo calls it the full game's ---
	var st = G.store
	var was: String = st.backend
	st.backend = "demo"
	var owned: Dictionary = st.owned
	st.owned = {}
	check("in the demo the Ninth Lamp is marked as the full game's", Q.locked_tag("myst_ninth_lamp") != "")
	check("...and the strongbox (Floor 5 at most) is not", Q.locked_tag("myst_empty_strongbox") == "")
	check("...and the Lift Rope (Shellhaven, Floor 5) is not", Q.locked_tag("myst_cut_rope") == "")
	st.backend = was
	st.owned = owned
	print("MYSTERY CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
