extends SceneTree
## Round 177: the nanite farm -- vats, replication, stagnation, events, skills, harvest, strains, save/load, away time.
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
	G.save_path = "user://nf_save.json"
	G.save_base = "user://nf_slots"
	G.new_game()
	var F = G.sys("farm")
	check("system exists", F != null)
	check("closed before the swarm and a home", F.open_block() != "")
	G.integration = 100000.0
	G.home["have"] = true
	G.gold = 2000
	G.inventory = {}
	G.add_item("iron_ore", 40)
	G.add_item("nanite_shard", 40)
	G.add_item("spirit_herb", 10)
	check("open now (tier %d)" % G.nanite_tier(), F.open_block() == "")
	check("build the first vat", F.build_vat() == "" and F.vats == 1 and F.pop > 0.0)
	var p0: float = F.pop
	F._advance(30.0, false)
	check("it replicates", F.pop > p0 * 1.5)
	F._advance(2000.0, false)
	check("it saturates at the cap", F.pop <= F.cap() + 0.001 and F.pop > F.cap() * 0.8)
	check("left alone it stagnates", F.diversity < 0.3 and F.state_word() != "")
	var eff_low: float = F.efficiency()
	check("efficiency floor holds", eff_low >= 0.34)
	check("stagnant yields less", F.efficiency() < 0.6)
	# repair slows stagnation
	var d0: float = 1.0
	F.diversity = 1.0
	F._advance(100.0, false)
	var lost_plain: float = d0 - F.diversity
	F.spent["repair"] = 5
	F.diversity = 1.0
	F._advance(100.0, false)
	var lost_fixed: float = d0 - F.diversity
	check("error correction slows the drain", lost_fixed < lost_plain * 0.6)
	F.spent = {}
	# more vats, more room
	var cap1: float = F.cap()
	check("second vat", F.build_vat() == "" and F.cap() > cap1)
	var gold_a: int = G.gold
	F.build_vat()
	check("vats cost more each time", gold_a - G.gold > 140)
	while F.vats < int(F.data["vats"]["max"]):
		G.gold = 5000
		G.add_item("iron_ore", 10)
		G.add_item("nanite_shard", 10)
		F.build_vat()
	check("vat max", F.vat_block() != "")
	# events
	F.event = {}
	F.diversity = 0.3
	F._raise_event()
	check("an event arises", not F.event.is_empty() and not F.event_def().is_empty())
	for eid in F.data["events"]:
		var ev: Dictionary = F.data["events"][eid]
		check("event %s has choices" % eid, ev["choices"].size() >= 2)
		for ch in ev["choices"]:
			var tot := 0.0
			for r in F.outcome_odds(ch):
				tot += float(r["p"])
			check("%s/%s odds sum to 1" % [eid, ch["id"]], absf(tot - 1.0) < 0.001)
			check("odds text", F.odds_text(ch) != "")
	F.event = {"id": "rut"}
	F.diversity = 0.2
	F.pop = 100.0
	check("prune helps diversity", F.resolve("prune", 0.0) != "" and F.diversity > 0.45 and F.pop < 100.0 and F.event.is_empty())
	F.event = {"id": "rut"}
	F.diversity = 0.2
	var sh0: int = G.count("nanite_shard")
	F.resolve("feed", 0.0)
	check("feed costs shards", G.count("nanite_shard") == sh0 - 2 and F.diversity > 0.4)
	G.inventory.erase("nanite_shard")
	F.event = {"id": "rut"}
	check("cannot afford is refused", F.resolve("feed", 0.0).begins_with("Needs") and not F.event.is_empty())
	F.event = {"id": "stray"}
	F.resolve("cultivate", 0.0)
	check("cultivating can find a line", F.found.size() > 2)
	F.event = {"id": "stray"}
	var lore0: int = F.lore
	F.resolve("study", 0.0)
	check("study gives lore", F.lore == lore0 + 2)
	F.event = {"id": "blight"}
	F.pop = 100.0
	F.resolve("quarantine", 0.0)
	check("quarantine costs a third", absf(F.pop - 67.0) < 0.5)
	F.event = {"id": "surge"}
	F.resolve("harvest", 0.0)
	check("surge gives a harvest bonus", F.bonus == 1.5)
	# harvest
	F.bonus = 0.0
	F.pop = F.cap()
	F.diversity = 1.0
	F.strain = "builder"
	var hp: Dictionary = F.harvest_preview()
	check("harvest has a yield", int(hp["shards"]) > 0)
	var sh1: int = G.count("nanite_shard")
	var integ0: float = G.integration
	check("harvest works", F.harvest_block() == "" and F.harvest().length() > 0)
	check("shards arrived", G.count("nanite_shard") == sh1 + int(hp["shards"]))
	check("the colony is not wiped", F.pop >= 6.0 and F.pop < F.cap())
	F.pop = F.cap()
	F.diversity = 0.35
	check("stagnant yield is lower", int(F.harvest_preview()["shards"]) < int(hp["shards"]))
	# lines
	F.found["weaver"] = true
	check("switch line", F.set_strain("weaver") != "" and F.strain == "weaver")
	check("unfound line refused", F.found.has("deep") or F.strain == "weaver")
	# skills
	F.lore = 100
	F.spent = {}
	var rate0: float = F.rate()
	check("learn replication", F.learn("rep") == "" and F.lv("rep") == 1 and F.rate() > rate0)
	var cap0: float = F.cap()
	F.learn("lattice")
	check("lattice adds room", F.cap() > cap0)
	for i in 10:
		F.learn("rep")
	check("skills stop at max", F.lv("rep") == 5 and F.skill_block("rep") != "")
	F.lore = 0
	check("lore is needed", F.learn("repair") != "")
	# passive
	var ps := 0.0
	for e in F.effects():
		ps += float(e.get("swarm_mult", 1.0)) - 1.0
	check("a living colony feeds the swarm a little", ps > 0.0 and ps <= 0.081)
	# save/load and time away
	F.pop = 20.0
	F.diversity = 1.0
	F.event = {}
	var st: Dictionary = JSON.parse_string(JSON.stringify(F.save_state()))
	st["last_t"] = G._now() - 3 * 3600.0
	F.load_state(st)
	check("save keeps vats and skills", F.vats == 6 and F.lv("rep") == 5)
	check("away time grows it and stagnates it", F.pop > 20.0 and F.diversity < 1.0)
	# unlimited stores
	check("assist build holds anything", true)
	print("farm_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
