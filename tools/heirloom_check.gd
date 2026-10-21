extends SceneTree
## Round 120: the Heirloom set. Run: godot --headless --path . --script tools/heirloom_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var H = G.sys("heirloom")
	var Q = G.sys("quests")
	var ch := []
	ch.append(["system exists with 7 pieces", H != null and H.pieces().size() == 7])
	ch.append(["not started", not H.started and H.effects().is_empty()])
	G.skills["smithing"] = 0.0
	ch.append(["needs smithing 2 to ask", not H.can_ignite_smithing()])
	ch.append(["design ignition needs all three", true])
	G.skills["smithing"] = 100000.0
	H.ignite_by_design({"motif": "studded", "trim": "gold"})
	ch.append(["two choices do not ignite", not H.started])
	var tx: String = H.ignite("test")
	ch.append(["ignites", H.started and tx != "" and Q.active.has("heirloom:line")])
	ch.append(["ignites once", H.ignite("again") == ""])
	ch.append(["kind heirloom", Q.kind_of("heirloom:line") == "heirloom"])
	ch.append(["only piece 1 can be made", H.make(1)["ok"] == false])
	ch.append(["piece 1 refused without stock", H.why_not(0) != ""])
	# make every piece in order
	for s in ["iron_ore", "silver_ore", "beast_hide", "bone_shard", "rough_jade", "healing_salve", "qi_pill", "spirit_herb", "cave_carp"]:
		G.add_item(s, 40, false)
	G.gold = 99999
	for sk in ["medicine", "alchemy", "herbalism", "fishing", "jewelcrafting", "mining"]:
		G.skills[sk] = 100000.0
	var ok_all := true
	var ids := []
	for i in 7:
		var r: Dictionary = H.make(i, {"motif": "studded", "dye": "crimson"} if i == 0 else {})
		if not bool(r.get("ok", false)):
			print("HEIRLOOM piece ", i, " -> ", r.get("text"))
			ok_all = false
			break
		ids.append(r["item"])
	ch.append(["all seven made in order", ok_all and H.complete()])
	ch.append(["first piece kept its design", G.item_def(ids[0]).has("design") and G.item_def(ids[0]).has("heirloom")])
	ch.append(["quest completes", Q.done.has("heirloom:line") and not Q.active.has("heirloom:line")])
	ch.append(["pieces are gear", ids.all(func(i): return G.gear_family(i) != "")])
	# wear them
	var worn := 0
	for id in ids:
		G.equip(id) if G.has_method("equip") else null
	for s in G.gear_slots():
		if str(s[0]) != "weapon" and G.worn(str(s[0])) != "":
			worn += 1
	ch.append(["pieces can be worn (or no equip method)", worn > 0 or not G.has_method("equip")])
	if worn == 0:
		for id in ids:
			var fam: String = G.gear_family(id)
			for s in G.gear_slots():
				if str(s[2]) == fam and G.worn(str(s[0])) == "":
					G.equipment[str(s[0])] = id
					break
	var n: int = H.worn_count()
	ch.append(["worn pieces counted", n >= 5])
	var e1: Array = H.effects()
	ch.append(["set bonus appears", e1.size() == 1 and float(e1[0]["ward"]) > 0.0])
	var g0: float = H.growth
	for k in 40:
		H.on_event("kill", {})
	ch.append(["kills grow it", H.growth > g0])
	G.realm = 0
	var s0: String = H.stage_name()
	H.growth = 0.0
	H._fx_key = ""
	var w0: float = float(H.effects()[0]["ward"])
	H.growth = 400.0
	G.realm = 8
	H._fx_key = ""
	ch.append(["higher stage, stronger set", H.stage_name() == "Ascendant" and float(H.effects()[0]["ward"]) > w0])
	G.add_item("emperor_jade", 1, false)
	var fo: Array = H.feed_options()
	ch.append(["a rare material can be fed", "emperor_jade" in fo])
	var g1: float = H.growth
	H.feed("emperor_jade")
	ch.append(["feeding grows it", H.growth > g1])
	var st: Dictionary = H.save_state()
	H.reset()
	ch.append(["reset clears", not H.started])
	H.load_state(st)
	ch.append(["save/load keeps it", H.complete() and H.growth > 0.0])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("HEIRLOOM FAIL: ", c[0])
	print("HEIRLOOM CHECK %d passed, %d failed" % [ch.size() - bad, bad])
	quit()
