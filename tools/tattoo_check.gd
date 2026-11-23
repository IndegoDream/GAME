extends SceneTree
## Round 177: tattoos -- runes cut into beasts.
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
	G.save_path = "user://tt_save.json"
	G.save_base = "user://tt_slots"
	G.new_game()
	var T = G.sys("tattoos")
	check("system exists", T != null and T.placements().size() == 4)
	for pk in T.placements():
		for k in T.placements()[pk]["keys"]:
			check("placement key %s is read" % k, str(k) in G.ADDITIVE_KEYS or str(k) in ["qi_mult", "insight_mult", "damage_mult", "move_mult", "ranged_mult", "damage_taken", "hp_mult", "swarm_mult", "meditate_mult", "bond_mult", "keep_gold"])
	var b := {"species": "cave_hare", "name": "Inky", "bond": 80.0, "tier": 0, "out": true}
	G.contracts = [b]
	G.familiar = b
	G.current_level = "village"
	G.havens["village"] = "the village"
	check("runecraft is taught first", T.block(b, "edge_rune", "paw") != "")
	G.skills["runecraft"] = 9999.0
	check("slots follow runecraft", T.slots() >= 1)
	G.inventory = {}
	check("no rune blocks", T.block(b, "edge_rune", "paw") != "")
	G.add_item("edge_rune", 6)
	G.add_item("ember_rune", 2)
	check("block clear", T.block(b, "edge_rune", "paw") == "")
	check("placement needed", T.block(b, "edge_rune", "nowhere") != "")
	G.current_level = "floor3"
	G.havens.erase("floor3")
	check("town only", T.block(b, "edge_rune", "paw") != "")
	G.current_level = "village"
	var o: Dictionary = T.odds(b, "edge_rune")
	check("odds add to one", absf(float(o["ok"]) + float(o["crack"]) - 1.0) < 0.001 and float(o["flinch"]) <= float(o["crack"]))
	var weak := {"species": "cave_hare", "name": "Shy", "bond": 0.0, "tier": 0}
	G.skills["runecraft"] = 60.0
	check("bond helps", float(T.odds(b, "edge_rune")["ok"]) > float(T.odds(weak, "edge_rune")["ok"]))
	G.skills["runecraft"] = 9999.0
	var n0: int = G.count("edge_rune")
	var r: Dictionary = T.apply(b, "edge_rune", "paw", 0.0)
	check("tattoo takes", r["success"] == true and T.marks(b).size() == 1 and G.count("edge_rune") == n0 - 1)
	check("lines", T.lines(b).size() == 2)
	var g_paw: Dictionary = T.gifts(b)
	var plain := {"species": "cave_hare", "name": "Brow", "bond": 80.0, "tier": 0, "out": false}
	T.apply(plain, "edge_rune", "flank", 0.0)
	var d_paw := 1.0 - float(g_paw.get("damage_taken", 1.0))
	var d_flank := 1.0 - float(T.gifts(plain).get("damage_taken", 1.0))
	check("flank leans toward toughness more than paw does", d_flank > d_paw)
	var eff := 0.0
	for e in T.effects():
		eff += 1.0 - float(e.get("damage_taken", 1.0))
	check("effects reach the party", eff > 0.0)
	# crack and flinch
	var victim := {"species": "cave_hare", "name": "Vic", "bond": 50.0, "tier": 0}
	var bond0: float = float(victim["bond"])
	var have0: int = G.count("edge_rune")
	var rc: Dictionary = T.apply(victim, "edge_rune", "paw", 0.9999)
	check("a slip cracks it, unmarked", rc["success"] == false and T.marks(victim).is_empty() and G.count("edge_rune") == have0 - 1)
	check("a bad slip flinches", float(victim["bond"]) < bond0)
	# slot limit
	var guard := 0
	while T.block(b, "ember_rune", "brow") == "" and guard < 6:
		T.apply(b, "ember_rune", "brow", 0.0)
		guard += 1
	check("slot limit holds", T.marks(b).size() <= T.slots())
	# scour
	G.gold = 500
	var sc: int = T.scour_cost(b)
	check("scour clears it", T.scour(b) != "" and T.marks(b).is_empty() and G.gold == 500 - sc)
	# constructs excluded
	check("constructs use the foundry", T.block({"construct": true, "name": "Lump"}, "edge_rune", "paw") != "")
	# save/load keeps the mark on the beast and the counter
	T.apply(b, "edge_rune", "back", 0.0)
	var st: Dictionary = T.save_state()
	check("counter saved", int(st["cut"]) >= 3)
	print("tattoo_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
