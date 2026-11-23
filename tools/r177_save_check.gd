extends SceneTree
## Round 177: a real save and load keeps genes, tattoos, parts, eggs, samples, the farm; an old save without them loads clean.
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
	G.save_path = "user://r177_save.json"
	G.save_base = "user://r177_slots"
	G.new_game()
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.skills["runecraft"] = 9999.0
	G.integration = 100000.0
	G.home["have"] = true
	G.bond_familiar("cave_hare")
	var c: Dictionary = G.contracts[0]
	c["bond"] = 80.0
	var N = G.sys("genome")
	N.set_level(c, "nose", 4)
	c["syn"] = {"a": "scout", "b": "gather", "str": "brilliant"}
	c["quirk"] = "frail"
	c["bl"] = "frost"
	c["blood"] = 2
	G.current_level = "village"
	G.havens["village"] = "the village"
	G.add_item("edge_rune", 2)
	G.sys("tattoos").apply(c, "edge_rune", "flank", 0.0)
	G.contracts.append({"species": "golem_clay", "name": "Lump", "bond": 0.0, "tier": 0, "out": false, "construct": true})
	G.sys("foundry").bin["clay_frame"] = 1
	G.sys("foundry").fit("golem:Lump", "frame", "clay_frame")
	G.sys("foundry").mech_parts["reactor"] = "qi_cell"
	G.sys("eggs").lay("floor", true)
	N.take_sample(c, "nose")
	G.add_item("iron_ore", 4); G.add_item("nanite_shard", 4); G.gold = 1000
	G.sys("farm").build_vat()
	G.sys("farm").lore = 5
	G.sys("farm").learn("rep")
	G.save_game()
	var nose: int = N.level(c, "nose")
	G.new_game()
	check("new game is empty again", G.sys("eggs").eggs.is_empty() and G.sys("farm").vats == 0 and G.sys("foundry").bin.is_empty())
	check("load works", G.load_game())
	var c2: Dictionary = G.contracts[0]
	check("genes survive", int(N.level(c2, "nose")) == nose)
	check("synergy, quirk and bloodline survive", c2["syn"]["str"] == "brilliant" and c2["quirk"] == "frail" and c2["bl"] == "frost" and int(c2["blood"]) == 2)
	check("tattoo survives", G.sys("tattoos").marks(c2).size() == 1)
	check("golem parts survive", G.sys("foundry").target_parts("golem:Lump").get("frame", "") == "clay_frame")
	check("frame parts survive", G.sys("foundry").mech_parts.get("reactor", "") == "qi_cell")
	check("egg survives", G.sys("eggs").eggs.size() == 1)
	check("sample survives", N.samples.size() == 1)
	check("farm survives", G.sys("farm").vats == 1 and G.sys("farm").lv("rep") == 1)
	# an old save: strip the new systems
	var txt := FileAccess.get_file_as_string(G.save_path)
	var d = JSON.parse_string(txt)
	for k in ["genome", "eggs", "foundry", "tattoos", "farm", "tailor"]:
		if d.get("systems", {}).has(k):
			d["systems"].erase(k)
	var f := FileAccess.open(G.save_path, FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	G.new_game()
	check("an old save loads", G.load_game())
	check("and the new systems are simply empty", G.sys("eggs").eggs.is_empty() and G.sys("farm").vats == 0 and G.sys("genome").samples.is_empty())
	print("r177_save_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
