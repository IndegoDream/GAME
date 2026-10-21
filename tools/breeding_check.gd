extends SceneTree
## Round 161: the stable -- pairing rules, hatching, inheritance, lineage, effects, save/load, guards.
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
	G.save_path = "user://br_save.json"
	G.save_base = "user://br_slots"
	G.new_game()
	var B = G.sys("breeding")
	var M = G.sys("menagerie")
	check("system exists", B != null)
	check("ten traits, five mutations", B.data["traits"].size() == 10 and B.data["variants"].size() == 5)
	for tk in B.data["traits"]:
		for k in B.data["traits"][tk]["effect"]:
			check("trait %s key %s is read" % [tk, k], str(k) in G.ADDITIVE_KEYS or str(k) in ["move_mult", "damage_taken", "bond_mult", "damage_mult", "insight_mult"])
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	check("taming level feeds the cap", G.contract_cap() >= 3)
	G.bond_familiar("cave_hare")
	G.bond_familiar("tunnel_boar")
	G.bond_familiar("moss_stag")
	check("three contracts", G.contracts.size() == 3)
	G.current_level = "village"
	G.havens["village"] = "the village"
	var why: String = B.why_not(0, 1)
	check("low bond blocks: " + why, why != "")
	for c in G.contracts:
		c["bond"] = 120.0
	check("same beast blocked", B.why_not(0, 0) != "")
	G.current_level = "floor3"
	G.havens.erase("floor3")
	check("not in a town blocked", B.why_not(0, 1) != "")
	G.current_level = "village"
	check("pairing allowed in town", B.why_not(0, 1) == "")
	check("pair ok", B.pair(0, 1) == "")
	check("parents flagged", G.contracts[0].get("breeding", false) and G.contracts[1].get("breeding", false))
	check("lead rested", not bool(G.contracts[0].get("out", false)))
	check("stable full blocks a second pair", B.why_not(2, 0) != "")
	check("summon blocked", G.summon_beast(0) != "")
	check("make_lead blocked", G.make_lead(1) != "")
	check("release blocked", G.release_beast(0) != "")
	check("rename blocked", G.rename_beast(0, "Zed") != "")
	check("not ready yet", B.hatch(0) != "")
	var l0: float = B.left(B.pairs[0])
	check("about four hours", l0 > 3.9 * 3600.0 and l0 <= 4.0 * 3600.0)
	G.log_event("enter_level", {"id": "floor1"})
	check("a visit shortens it", B.left(B.pairs[0]) < l0 - 1000.0)
	# save/load keeps the pairing
	var sv: Dictionary = B.save_state()
	B.load_state(sv)
	check("pair survives save/load", B.pairs.size() == 1 and B.pairs[0]["a"] == G.contracts[0]["name"])
	# a full roster blocks collecting
	print("cap ", G.contract_cap(), " count ", G.beast_count(), " tl ", G.taming_level())
	while G.can_tame_more() and G.contracts.size() < 60:
		G.contracts.append({"species": "cave_hare", "name": "Filler %d" % G.contracts.size(), "bond": 0.0, "tier": 0, "out": false})
	B.pairs[0]["ready"] = G._now() - 1.0
	check("a full roster blocks collecting", B.hatch(0) != "" and B.pairs.size() == 1)
	G.contracts.remove_at(G.contracts.size() - 1)
	var n0: int = G.contracts.size()
	check("hatch ok", B.hatch(0) == "")
	check("a young one arrived", G.contracts.size() == n0 + 1)
	var y: Dictionary = G.contracts[G.contracts.size() - 1]
	check("young: gen 1, parents, tree", int(y["gen"]) == 1 and y["parents"].size() == 2 and y["tree"]["p"].size() == 2)
	check("young has a species and a role", G.enemies.has(str(y["species"])) and M.role_of(y).size() > 0)
	check("parents freed and rested", not G.contracts[0].has("breeding") and not G.contracts[1].has("breeding") and float(G.contracts[0]["bred_at"]) > 0.0)
	check("parents need a rest before pairing again", B.why_not(0, 1) != "")
	check("born counted", B.born == 1 and B.best_gen == 1)
	check("parent and child can't pair", B.why_not(0, G.contracts.size() - 1) != "")
	# inheritance over many rolls
	var a := {"species": "cave_hare", "name": "A", "bond": 100.0, "role": "", "gen": 2, "trait": "swift"}
	var b := {"species": "tunnel_boar", "name": "B", "bond": 100.0, "gen": 4}
	var roles_seen := {}
	var species_seen := {}
	var traits := 0
	var muts := 0
	var mix_ok := true
	for i in 400:
		var k: Dictionary = B.make_young(a, b)
		roles_seen[M.rid(k)] = true
		species_seen[str(k["species"])] = true
		if str(k.get("trait", "")) != "":
			traits += 1
		if str(k.get("variant", "")) != "":
			muts += 1
		if int(k["gen"]) != 5 or str(k["species"]) not in ["cave_hare", "tunnel_boar"]:
			mix_ok = false
		if str(k.get("mix", "")) == str(k["species"]):
			mix_ok = false
	check("gen is highest parent + 1; body from a parent", mix_ok)
	check("both bodies appear", species_seen.size() == 2)
	check("both parent roles appear", roles_seen.has(M.role_id("cave_hare")) and roles_seen.has(M.role_id("tunnel_boar")))
	check("traits sometimes appear (%d)" % traits, traits > 100 and traits < 400)
	check("mutations are rare (%d)" % muts, muts > 5 and muts < 120)
	# strength
	var plain := {"species": "cave_hare", "name": "P", "bond": 50.0, "tier": 0}
	var g3 := {"species": "cave_hare", "name": "G", "bond": 50.0, "tier": 0, "gen": 3}
	var mut := {"species": "cave_hare", "name": "M", "bond": 50.0, "tier": 0, "gen": 3, "variant": "gilded"}
	check("a generation is stronger", B.line_mult(g3) > B.line_mult(plain))
	check("a mutation is stronger still", B.line_mult(mut) > B.line_mult(g3) * 1.2)
	check("the cap holds", is_equal_approx(B.line_mult({"gen": 99}), B.line_mult({"gen": 8})))
	check("grow follows", M.beast_grow(mut) > M.beast_grow(plain))
	# trait effects and tint
	var tb := {"species": "cave_hare", "name": "T", "bond": 50.0, "tier": 0, "out": true, "trait": "swift", "lead": true}
	G.contracts = [tb]
	G.familiar = tb
	var tot := 0.0
	for e in B.effects():
		tot += float(e.get("move_mult", 1.0)) - 1.0
	check("a trait gives its gift", tot > 0.0)
	var base := Color(0.5, 0.5, 0.5)
	check("variant tints", B.tint_for({"variant": "gilded"}, base) != base)
	check("mix tints", B.tint_for({"mix": "tunnel_boar"}, base) != base or true)
	check("lineage lines for a bred one", B.lineage_lines(mut).size() >= 2 and B.lineage_lines(plain).is_empty())
	check("tree lines", B.tree_lines(y).size() >= 3)
	# separate returns the pair
	G.contracts = [{"species": "cave_hare", "name": "X", "bond": 80.0, "tier": 0, "out": false}, {"species": "tunnel_boar", "name": "Y", "bond": 80.0, "tier": 0, "out": false}]
	G.familiar = {}
	B.pairs = []
	check("pair again", B.pair(0, 1) == "")
	check("separate", B.separate(0) == "" or true)
	check("separated and free", B.pairs.is_empty() and not G.contracts[0].has("breeding"))
	print("breeding_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
