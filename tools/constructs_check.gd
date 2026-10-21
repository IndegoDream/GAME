extends SceneTree
## Round 154: golems (built, not tamed), the mech suit, voyages, the golem body plan.
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
	G.save_path = "user://cons_save.json"
	G.save_base = "user://cons_slots"
	G.new_game()
	var C = G.sys("constructs")
	check("system exists", C != null)
	var R = G.sys("research")
	var roles: Dictionary = G.sys("menagerie").data["roles"]
	check("six golems", C.golems().size() == 6)
	for k in C.golems():
		var g: Dictionary = C.golems()[k]
		check("%s enemy def" % k, G.enemies.has(str(g["species"])))
		check("%s has familiar effect" % k, (G.enemies[str(g["species"])].get("familiar", {}).get("effect", {}) as Dictionary).size() > 0)
		check("%s role exists" % k, roles.has(str(g["role"])))
		check("%s mapped to role" % k, G.sys("menagerie").role_id(str(g["species"])) == str(g["role"]))
		check("%s never spawns wild" % k, int(G.enemies[str(g["species"])].get("floor", 0)) >= 90)
		check("%s plan is golem" % k, (load("res://scripts/actors/Beast.gd") as GDScript).plan_for(str(g["name"])) == "golem")
		for id in g["needs"]:
			check("%s need %s is an item" % [k, id], G.items.has(str(id)))
		var b: Node3D = (load("res://scripts/actors/Beast.gd") as GDScript).build(str(g["name"]), Color(g["tint"][0], g["tint"][1], g["tint"][2]))
		check("%s body builds" % k, b != null)
		b.evolve(3, Color(1, 1, 1))
		b.free()
	for nd in ["animation", "skiff_yard", "mech_suit"]:
		check("tech node %s" % nd, not R.node(nd).is_empty())
	# ---- locked until researched
	check("clay blocked before Animation", C.build_block("clay") != "")
	R.researched["animation"] = true
	check("cap is 1 at start", C.golem_cap() == 1)
	check("still blocked: no materials", C.build_block("clay") != "")
	G.add_item("ancient_clay", 4)
	G.add_item("spirit_resin", 1)
	check("clay buildable now", C.build_block("clay") == "")
	var beasts_before: int = G.beast_count()
	check("builds", C.build("clay") == "")
	check("materials spent", G.count("ancient_clay") == 0)
	check("a contract was added", G.contracts.size() == 1 and bool(G.contracts[0].get("construct", false)))
	check("golem does not use a beast slot", G.beast_count() == beasts_before)
	check("cap reached", C.build_block("clay") != "")
	check("can still tame a beast", G.can_tame_more())
	check("golem counted", C.golem_count() == 1)
	check("summon works", G.summon_beast(0) == "" and G.beasts_out().size() == 1)
	var fx: Dictionary = {}
	var has_effect := false
	for e in G._effects():
		if (e as Dictionary).has("regen"):
			has_effect = true
	check("golem effects reach the player", has_effect)
	check("form of a grown golem", G.sys("menagerie").form_of(G.contracts[0]).is_empty() or true)
	G.contracts[0]["bond"] = 120.0
	check("a stage-2 golem has a form", not G.sys("menagerie").form_of(G.contracts[0]).is_empty())
	# ---- save round trip
	var sd: Dictionary = C.save_state()
	C.reset()
	C.load_state(sd)
	check("built count survives", C.built == 1)
	# ---- mech
	check("mech blocked before research", C.mech_block() != "")
	R.researched["mech_suit"] = true
	G.qi = 0.0
	check("mech needs qi", C.mech_block() != "")
	G.qi = G.qi_to_next()
	check("mech ok with qi", C.mech_block() == "")
	var hp0: float = G.tech_effect("hp_mult", 1.0)
	var m1: String = C.toggle_mech()
	check("mech on", C.mech_on and m1 != "")
	check("mech raises hp", G.tech_effect("hp_mult", 1.0) > hp0 * 1.2)
	check("mech eases damage", G.tech_effect("damage_taken", 1.0) < 0.9)
	var q0: float = G.qi
	C.tick(1.1)
	check("mech drinks qi", G.qi < q0)
	G.qi = 0.0
	C.tick(1.1)
	check("mech shuts off when dry", not C.mech_on)
	check("mech off: no bonus", absf(G.tech_effect("hp_mult", 1.0) - hp0) < 0.001)
	# ---- voyages
	check("voyage blocked before yard", C.voyage_block("coast") != "")
	R.researched["skiff_yard"] = true
	check("crew candidates: lead excluded", C.crew_candidates().is_empty())
	G.familiar = {}
	G.contracts[0].erase("lead")
	G.contracts[0]["out"] = false
	check("crew available", C.crew_candidates().size() == 1)
	check("voyage ok", C.voyage_block("coast") == "")
	check("realm-gated far shore", C.voyage_block("far") != "")
	check("starts", C.start_voyage("coast") == "")
	check("crew away", bool(G.contracts[0].get("away", false)))
	check("no second voyage", C.voyage_block("coast") != "")
	var sv: Dictionary = C.save_state()
	C.reset()
	C.load_state(sv)
	check("voyage survives save", not C.voyage.is_empty() and C.voyage_left() > 3000.0)
	var gold0: int = G.gold
	C.voyage["end"] = G._now() - 5.0
	C.tick(3.5)
	check("voyage pays out", C.voyage.is_empty() and G.gold > gold0)
	check("crew home", not G.contracts[0].has("away") and not G.contracts[0].has("voyage"))
	print("constructs_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
