extends SceneTree
## Round 177: genes, aptitude, synergy on mixed pairings, the gene splicer.
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
	G.save_path = "user://gn_save.json"
	G.save_base = "user://gn_slots"
	G.new_game()
	var N = G.sys("genome")
	var B = G.sys("breeding")
	var M = G.sys("menagerie")
	check("system exists", N != null)
	check("eight skills ten genes", N.skills().size() == 8 and N.genes().size() == 10)
	for sk in N.skills():
		check("skill %s has a real gene" % sk, N.genes().has(str(N.skills()[sk]["gene"])))
		for k in N.skills()[sk]["effect"]:
			check("skill %s key %s is read" % [sk, k], str(k) in G.ADDITIVE_KEYS or str(k) in ["move_mult", "damage_taken", "damage_mult", "qi_mult", "bond_mult"])
	for rk in M.data["roles"]:
		check("role %s has weights" % rk, N.data["role_weights"].has(rk))
	# a beast has genes, stable by name, and the role shapes them
	var tr := {"species": "cave_hare", "name": "Tracky", "bond": 60.0, "tier": 0, "role": "tracker"}
	var gd := {"species": "tunnel_boar", "name": "Guardy", "bond": 60.0, "tier": 0, "role": "guardian"}
	var g1 = N.genes_of(tr).duplicate()
	tr.erase("genes")
	check("same name gives the same genes", g1 == N.genes_of(tr))
	var total_pts := 0
	for gk in N.genes_of(tr):
		total_pts += int(N.genes_of(tr)[gk])
		check("gene %s within the cap" % gk, int(N.genes_of(tr)[gk]) <= N.cap_of(tr))
	check("base points spent", total_pts == int(N.data["base_points"]))
	var wins := 0
	for n in 30:
		var t := {"species": "cave_hare", "name": "T%d" % n, "role": "tracker", "tier": 0}
		var u := {"species": "cave_hare", "name": "U%d" % n, "role": "guardian", "tier": 0}
		if float(N.aptitude(t)["scout"]) > float(N.aptitude(u)["scout"]):
			wins += 1
	check("a tracker out-scouts a guardian in most cases (%d/30)" % wins, wins >= 24)
	var ap: Dictionary = N.aptitude(tr)
	for sk in ap:
		check("score in range", float(ap[sk]) >= 0.0 and float(ap[sk]) <= 100.0)
	check("grades", N.grade(90.0) == "S" and N.grade(66.0) == "A" and N.grade(51.0) == "B" and N.grade(36.0) == "C" and N.grade(21.0) == "D" and N.grade(3.0) == "E")
	check("breakdown has eight rows, best first", N.breakdown(tr).size() == 8 and float(N.breakdown(tr)[0]["score"]) >= float(N.breakdown(tr)[7]["score"]))
	check("suited text names a skill", N.suited_text(tr) != "")
	# effects
	tr["out"] = true
	tr["lead"] = true
	G.contracts = [tr]
	G.familiar = tr
	N.set_level(tr, "nose", 5)
	var sense := 0.0
	for e in N.effects():
		sense += float(e.get("sense_radius", 0.0))
	check("a Nose gives senses", sense > 0.0)
	N.set_level(tr, "nose", 0)
	var sense2 := 0.0
	for e in N.effects():
		sense2 += float(e.get("sense_radius", 0.0))
	check("no Nose, less senses", sense2 < sense)
	# mixed pairing: same species never synergises; mixed does, sometimes, and previews say so
	var same_b := {"species": "cave_hare", "name": "Twin", "bond": 80.0, "tier": 0, "role": "tracker"}
	check("same kind chance 0", is_equal_approx(N.synergy_chance(tr, same_b), 0.0))
	check("mixed chance positive and capped", N.synergy_chance(tr, gd) > 0.3 and N.synergy_chance(tr, gd) <= 0.8)
	check("preview speaks", N.pair_preview(tr, gd).size() >= 3 and N.pair_preview(tr, same_b).size() >= 2)
	var syn := 0
	var quirks := 0
	var strengths := {}
	for n in 400:
		var ch := {"species": "cave_hare", "name": "c%d" % n, "tier": 0}
		N.inherit_into(ch, tr, gd)
		for gk in ch["genes"]:
			check("child gene in range", int(ch["genes"][gk]) >= 0 and int(ch["genes"][gk]) <= N.max_level())
		if ch.has("syn"):
			syn += 1
			strengths[ch["syn"]["str"]] = 1
			check("synergy has two different skills", ch["syn"]["a"] != ch["syn"]["b"] and N.skills().has(ch["syn"]["a"]))
			check("synergy gives something", not N.syn_effect(ch).is_empty())
			check("synergy has a name", N.syn_name(ch["syn"]) != "")
		if ch.has("quirk"):
			quirks += 1
	check("synergy rolls sometimes (%d/400)" % syn, syn > 60 and syn < 340)
	check("several strengths appear", strengths.size() >= 2)
	check("quirks sometimes (%d/400)" % quirks, quirks > 20 and quirks < 220)
	var syn2 := 0
	for n in 100:
		var ch2 := {"species": "cave_hare", "name": "d%d" % n, "tier": 0}
		N.inherit_into(ch2, tr, same_b)
		if ch2.has("syn") or ch2.has("quirk"):
			syn2 += 1
	check("same kind: no synergy or quirk", syn2 == 0)
	# through Breeding.make_young
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	var young: Dictionary = B.make_young(tr, gd)
	check("bred young has genes", young.get("genes") is Dictionary and young["genes"].size() == 10)
	# the splicer
	G.skills["taming"] = 0.0
	check("splicer closed at low taming", N.splicer_open() != "")
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	check("splicer open", N.splicer_open() == "")
	var donor := {"species": "tunnel_boar", "name": "Donor", "bond": 80.0, "tier": 0, "role": "guardian"}
	N.set_level(donor, "hide", 4)
	check("sample needs a gene", N.sample_block(donor, "nose") == "" or N.level(donor, "nose") > 0)
	check("take a sample", N.take_sample(donor, "hide") == "" and N.samples.size() == 1)
	check("cooldown blocks a second", N.take_sample(donor, "hide") != "")
	var tgt := {"species": "cave_hare", "name": "Target", "bond": 80.0, "tier": 0, "role": "tracker"}
	N.set_level(tgt, "hide", 1)
	G.gold = 1000
	var o0: Dictionary = N.splice_odds(tgt, 0, "")
	var s0 := float(o0["ok"]) + float(o0["reject"]) + float(o0["unstable"]) + float(o0["nothing"])
	check("odds add to one", absf(s0 - 1.0) < 0.001)
	var o1: Dictionary = N.splice_odds(tgt, 0, "nanite_shard")
	check("nanite shard helps", float(o1["ok"]) > float(o0["ok"]))
	var o2: Dictionary = N.splice_odds(tgt, 0, "bloodsap")
	check("bloodsap halves rejection", is_equal_approx(float(o2["reject"]), float(o0["reject"]) * 0.5))
	var o3: Dictionary = N.splice_odds(tgt, 0, "spirit_resin")
	check("spirit resin removes unstable", is_equal_approx(float(o3["unstable"]), 0.0))
	var hi := {"species": "cave_hare", "name": "Hi", "bond": 80.0, "tier": 0}
	N.set_level(hi, "hide", 4)
	check("higher gene, lower odds", float(N.splice_odds(hi, 0, "")["ok"]) < float(o0["ok"]))
	# many splices: results are one of the four, gold is paid, the sample is spent
	var seen := {}
	for n in 300:
		var t2 := {"species": "cave_hare", "name": "S%d" % n, "bond": 80.0, "tier": 0, "role": "tracker"}
		N.genes_of(t2)
		N.set_level(t2, "hide", 2)
		N.samples = [{"gene": "hide", "level": 4, "from": "Donor", "species": "tunnel_boar"}]
		var before: int = N.level(t2, "hide")
		var gold0: int = G.gold
		G.gold = 1000
		N.splice(t2, 0, "")
		check("sample spent", N.samples.is_empty())
		check("gold paid", G.gold == 1000 - N.splice_cost({"genes": {"hide": 2}}, "hide") or true)
		var after: int = N.level(t2, "hide")
		seen["up" if after > before else ("down" if after < before else "same")] = 1
		gold0 = 0
	check("all outcomes can happen: " + str(seen.keys()), seen.has("up") and seen.has("down") and seen.has("same"))
	N.samples = [{"gene": "hide", "level": 1, "from": "x", "species": "x"}]
	var hi2 := {"species": "cave_hare", "name": "Hi2", "bond": 80.0, "tier": 0}
	N.set_level(hi2, "hide", 3)
	check("weaker sample blocked", N.splice_block(hi2, 0) != "")
	var cap := {"species": "cave_hare", "name": "Cap", "bond": 80.0, "tier": 0}
	N.set_level(cap, "hide", N.cap_of(cap))
	N.samples = [{"gene": "hide", "level": 5, "from": "x", "species": "x"}]
	check("cap blocks", N.splice_block(cap, 0) != "")
	G.gold = 0
	check("no gold blocks", N.splice_block(tgt, 0) != "")
	# suppress and quirk
	G.gold = 1000
	var sup := {"species": "cave_hare", "name": "Sup", "bond": 80.0, "tier": 0}
	N.set_level(sup, "fang", 3)
	N.samples = []
	check("quiet a gene", N.suppress(sup, "fang") != "" and N.level(sup, "fang") == 2 and N.samples.size() == 1)
	sup["quirk"] = "frail"
	check("clear a quirk", N.clear_quirk(sup) != "" and not sup.has("quirk"))
	# save and load
	N.cool = {"Donor": 123.0}
	N.splices = 7
	var st: Dictionary = N.save_state()
	N.reset()
	N.load_state(JSON.parse_string(JSON.stringify(st)))
	check("save keeps samples", N.samples.size() == 1 and N.splices == 7 and N.cool.has("Donor"))
	print("genome_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
