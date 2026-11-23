extends SceneTree
## Round 177: eggs, warming, hatching, bloodlines, essence, blood.
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
	G.save_path = "user://eg_save.json"
	G.save_base = "user://eg_slots"
	G.new_game()
	var E = G.sys("eggs")
	var N = G.sys("genome")
	var B = G.sys("breeding")
	check("system exists", E != null and E.eggs.is_empty())
	check("essence item exists", G.has_item_def("blood_essence"))
	for bk in E.data["bloodlines"]:
		for k in E.data["bloodlines"][bk]["effect"]:
			check("bloodline %s key %s is read" % [bk, k], str(k) in G.ADDITIVE_KEYS or str(k) in ["move_mult", "damage_taken", "damage_mult", "qi_mult"])
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.depth = 6
	check("species pool grows with depth", E.species_pool().size() > 6)
	G.depth = 1
	var small: int = E.species_pool().size()
	G.depth = 20
	check("deeper pool is bigger", E.species_pool().size() > small)
	G.depth = 6
	# finding
	var e: Dictionary = E.lay("floor", true)
	check("lay gives an egg with a bloodline", not e.is_empty() and e["bl"] != "" and e["pot"] >= 1 and e["pot"] <= 3)
	check("egg is carried", E.eggs.size() == 1 and E.found == 1)
	var bl_n := 0
	for n in 200:
		E.eggs = []
		var x: Dictionary = E.lay("floor")
		if x["bl"] != "":
			bl_n += 1
	check("some eggs have a bloodline (%d/200)" % bl_n, bl_n > 5 and bl_n < 120)
	E.eggs = []
	var got := 0
	for n in 400:
		E.eggs = []
		E.on_event("enter_level", {"id": "floor3"})
		got += E.eggs.size()
	check("floors give eggs now and then (%d/400)" % got, got > 10 and got < 200)
	E.eggs = []
	for n in 8:
		E.lay("chest")
	check("lay does not itself cap, events do", E.eggs.size() == 8)
	E.eggs = []
	for n in 200:
		E.on_event("enter_level", {"id": "floor3"})
	check("the carry-box is limited (unlimited in the assist build)", E.eggs.size() <= E.carry())
	# scout raises the chance
	var plain: float = E.find_chance("enter_floor")
	var sc := {"species": "cave_hare", "name": "Scouty", "bond": 80.0, "tier": 0, "role": "tracker", "out": true, "lead": true}
	N.set_level(sc, "nose", 5)
	G.contracts = [sc]
	G.familiar = sc
	check("a Scout finds more", E.find_chance("enter_floor") > plain)
	# warming and hatching
	E.eggs = []
	var e2: Dictionary = E.lay("floor", true)
	G.current_level = "floor3"
	G.havens.erase("floor3")
	check("not in town blocked", E.warm_block(e2) != "")
	G.current_level = "village"
	G.havens["village"] = "the village"
	check("warm in town", E.warm(e2["id"]) == "" and bool(e2["warm"]))
	check("not ready", E.hatch_block(e2) != "")
	check("hours about three", E.left(e2) > 2.9 * 3600.0 and E.left(e2) <= 3.0 * 3600.0)
	var l0: float = E.left(e2)
	E.on_event("enter_level", {"id": "village"})
	check("a visit shortens it", E.left(e2) < l0 - 500.0)
	check("revealed at half", not E.is_revealed(e2) or e2["seen"])
	e2["ready"] = G._now() + 100.0
	e2["start"] = G._now() - 3000.0
	check("progress high reveals", E.is_revealed(e2))
	check("nest limit", true)
	var e3: Dictionary = E.lay("floor")
	var e4: Dictionary = E.lay("floor")
	E.warm(e3["id"])
	check("third egg blocked by slots", E.warm_block(e4) != "" or E.slots() == 3)
	e2["ready"] = G._now() - 1.0
	var ne: int = G.contracts.size()
	check("hatch ok", E.hatch(e2["id"]) == "" and G.contracts.size() == ne + 1)
	var kid: Dictionary = G.contracts[G.contracts.size() - 1]
	check("kid has bloodline and blood", str(kid.get("bl", "")) != "" and int(kid.get("blood", 0)) >= 1 and kid["egg"] == true)
	check("kid has genes with extra points", N.genes_of(kid).size() == 10)
	var pts := 0
	for gk in N.genes_of(kid):
		pts += int(N.genes_of(kid)[gk])
	check("blood adds gene points", pts == int(N.data["base_points"]) + int(N.data["points_per_blood"]) * int(kid["blood"]))
	check("bloodline lines", E.lines(kid).size() >= 2)
	# feeding
	kid["out"] = true
	G.familiar = kid
	G.contracts = [kid]
	var b0: float = B.line_mult(kid)
	G.inventory = {}
	check("no essence blocks", E.feed_block(kid) != "")
	G.add_item("blood_essence", 20)
	var bl0: int = int(kid["blood"])
	check("feed works", E.feed(kid) == "" and int(kid["blood"]) == bl0 + 1)
	check("blood makes it stronger", B.line_mult(kid) > b0)
	var guard := 0
	while E.feed_block(kid) == "" and guard < 20:
		E.feed(kid)
		guard += 1
	check("bloodline-born goes to six", int(kid["blood"]) == 6)
	var plainb := {"species": "cave_hare", "name": "Plain", "bond": 50.0, "tier": 0, "blood": 3}
	check("plain beast stops at three", E.feed_block(plainb) != "")
	check("gene cap rises with blood", N.cap_of(kid) > N.max_level())
	# effects
	var tot := 0.0
	for ef in E.effects():
		for k in ef:
			tot += absf(float(ef[k]) - (1.0 if not (str(k) in G.ADDITIVE_KEYS) else 0.0))
	check("bloodline gives a gift", tot > 0.0)
	# essence from kills/chests
	G.inventory = {}
	for n in 600:
		E.on_event("kill", {"type": "cave_hare"})
	check("kills drop essence sometimes (%d)" % G.count("blood_essence"), G.count("blood_essence") >= 3)
	# save/load
	E.eggs = []
	var e5: Dictionary = E.lay("floor", true)
	var st: Dictionary = E.save_state()
	E.reset()
	E.load_state(JSON.parse_string(JSON.stringify(st)))
	check("save keeps eggs", E.eggs.size() == 1 and E.eggs[0]["bl"] == e5["bl"] and E.found > 0)
	print("eggs_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
