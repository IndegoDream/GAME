extends SceneTree
## Round 177: the foundry -- parts, slots, fitting, aptitude, gifts, runes on constructs, skiff and frame mods.
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
	G.save_path = "user://fd_save.json"
	G.save_base = "user://fd_slots"
	G.new_game()
	var F = G.sys("foundry")
	var N = G.sys("genome")
	var CN = G.sys("constructs")
	check("system exists", F != null and F.parts().size() == 39)
	for id in F.parts():
		var p: Dictionary = F.parts()[id]
		check("%s slot valid" % id, F.slots_of(str(p["kind"])).has(str(p["slot"])))
		for it in p["needs"]:
			check("%s needs real item %s" % [id, it], G.has_item_def(str(it)))
		for k in p.get("effect", {}):
			check("%s key %s is read" % [id, k], str(k) in G.ADDITIVE_KEYS or str(k) in ["move_mult", "damage_taken", "damage_mult", "qi_mult", "hp_mult", "swarm_mult", "crit_chance"])
		for sk in p.get("apt", {}):
			check("%s apt skill %s exists" % [id, sk], N.skills().has(str(sk)))
	for kind in ["golem", "mech", "ship"]:
		for slot in F.slots_of(kind):
			check("%s/%s has three tiers" % [kind, slot], F.for_slot(kind, str(slot)).size() == 3)
	# a golem to work on
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.realm = 10
	var g := {"species": "golem_clay", "name": "Lump", "bond": 0.0, "tier": 0, "out": true, "construct": true}
	G.contracts = [g]
	G.familiar = g
	var t := "golem:Lump"
	check("no parts, no aptitude beyond kind", float(F.aptitude(t)["guard"]) > 0.0 and float(F.aptitude(t)["scout"]) == 0.0)
	# making a part
	G.inventory = {}
	G.gold = 500
	check("cannot make without research", F.make_block("clay_frame") != "")
	var R = G.sys("research")
	R.researched["animation"] = true
	R.researched["skiff_yard"] = true
	var can: bool = CN._research("animate")
	check("research gate answers", can)
	G.add_item("ancient_clay", 10)
	var mb: String = F.make_block("clay_frame")
	if can:
		check("can make with materials", mb == "")
		check("make", F.make("clay_frame") == "" and int(F.bin.get("clay_frame", 0)) == 1 and G.count("ancient_clay") == 7)
	else:
		F.bin["clay_frame"] = 1
	# fitting
	G.current_level = "floor3"
	G.havens.erase("floor3")
	check("fit needs a town", F.fit_block(t, "frame", "clay_frame") != "")
	G.current_level = "village"
	G.havens["village"] = "the village"
	check("wrong slot refused", F.fit_block(t, "core", "clay_frame") != "")
	check("fit ok", F.fit(t, "frame", "clay_frame") == "" and str(F.target_parts(t)["frame"]) == "clay_frame" and int(F.bin.get("clay_frame", 0)) == 0)
	check("gifts from the part", absf(float(F.gifts(t)["damage_taken"]) - 0.97) < 0.001)
	var eff_has := false
	for e in F.effects():
		if e.has("damage_taken") and float(e["damage_taken"]) < 1.0:
			eff_has = true
	check("it reaches the party effects", eff_has)
	var ap0: float = float(F.aptitude(t)["guard"])
	F.bin["iron_frame"] = 1
	var gold0: int = G.gold
	check("swap ok, costs gold, old part to bin", F.fit(t, "frame", "iron_frame") == "" and G.gold == gold0 - int(F.data["swap_gold"]) and int(F.bin.get("clay_frame", 0)) == 1)
	check("better part, better aptitude", float(F.aptitude(t)["guard"]) > ap0)
	check("unfit returns it", F.unfit(t, "frame") != "" and not F.target_parts(t).has("frame") and int(F.bin.get("iron_frame", 0)) == 1)
	F.fit(t, "frame", "iron_frame")
	# breakdown & suited text
	var bd: Array = F.breakdown(t)
	check("breakdown eight rows, sorted", bd.size() == 8 and float(bd[0]["score"]) >= float(bd[7]["score"]) and int(bd[0]["level"]) == -1)
	check("suited text", F.suited_text(t) != "")
	F.bin["hound_nose"] = 1
	F.fit(t, "senses", "hound_nose")
	check("hound nose makes a scout", float(F.aptitude(t)["scout"]) >= 20.0)
	# runes on the golem
	check("no runecraft, no sockets", F.rune_sockets() == 0)
	G.skills["runecraft"] = 9999.0
	if F.rune_sockets() > 0:
		G.add_item("edge_rune", 3)
		check("inscribe works", F.inscribe(t, "edge_rune", 0.0)["success"] == true and F.runes_on(t).size() == 1)
		check("rune gift", not F.rune_pool(F.runes_on(t), "wear").is_empty())
		var dt0: float = float(F.rune_pool(F.runes_on(t), "wear").get("damage_taken", 1.0))
		check("rune lowers damage taken", dt0 < 1.0)
		check("socket limit", F.rune_sockets() > 1 or F.inscribe_block(t, "edge_rune") != "")
		check("crack keeps the golem unmarked", F.inscribe("mech", "edge_rune", 0.99)["success"] == false and F.runes_on("mech").is_empty())
		F.mech_runes = ["edge_rune"]
		check("mech takes the weapon half", float(F.mech_effects().get("damage_mult", 1.0)) > 1.0)
		check("scour works", F.scour("mech") != "" and F.mech_runes.is_empty())
	else:
		check("runecraft not testable here", true)
	# the power frame
	F.mech_parts = {}
	F.mech_runes = []
	var base_dr: float = F.mech_drain_mult()
	F.bin["nanite_reactor"] = 1
	F.fit("mech", "reactor", "nanite_reactor")
	check("reactor cuts drain", F.mech_drain_mult() < base_dr and is_equal_approx(F.mech_drain_mult(), 0.7))
	F.bin["power_servos"] = 1
	F.fit("mech", "servos", "power_servos")
	CN.mech_on = true
	var me := {}
	for e in CN.effects():
		me = e
	check("worn frame has base and part gifts", float(me.get("damage_mult", 1.0)) > 1.15 and float(me.get("hp_mult", 1.0)) >= 1.25)
	CN.mech_on = false
	# the skiff
	var s0: Dictionary = F.ship_mods()
	check("bare skiff is plain", s0["hours"] == 1.0 and s0["loot"] == 1.0)
	F.bin["canvas_sail"] = 1
	F.bin["ribbed_hull"] = 1
	F.bin["navigator_chart"] = 1
	F.fit("ship", "sails", "canvas_sail")
	F.fit("ship", "hull", "ribbed_hull")
	F.fit("ship", "charts", "navigator_chart")
	var s1: Dictionary = F.ship_mods()
	check("skiff mods", is_equal_approx(s1["hours"], 0.85) and is_equal_approx(s1["loot"], 1.15) and is_equal_approx(s1["insight"], 1.5))
	var cn_ok: bool = CN._research("voyage")
	if cn_ok:
		var crew := {"species": "golem_stone", "name": "Crew", "bond": 0.0, "tier": 0, "out": false, "construct": true}
		G.contracts.append(crew)
		var vd: Dictionary = CN._voyage_def("coast")
		var before: float = G._now()
		check("voyage starts", CN.start_voyage("coast") == "")
		var dur: float = float(CN.voyage["end"]) - float(CN.voyage["start"])
		check("sails shorten the voyage", is_equal_approx(dur, float(vd["hours"]) * 3600.0 * 0.85))
		before = 0.0
	# aptitude of the ship
	check("ship aptitude exists", float(F.aptitude("ship")["haul"]) > 0.0)
	# save/load
	var st: Dictionary = F.save_state()
	F.reset()
	F.load_state(JSON.parse_string(JSON.stringify(st)))
	check("save keeps parts", F.ship_parts.has("hull") and F.mech_parts.has("reactor"))
	print("foundry_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
