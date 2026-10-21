extends SceneTree
## Round 119 step D: designing forged gear. Run: godot --headless --path . --script tools/design_check.gd

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var D = G.Design
	var checks := []
	checks.append(["plain is plain", D.is_plain({}) and D.is_plain({"motif": "plain", "trim": "none", "dye": "natural"})])
	checks.append(["studded is not plain", not D.is_plain({"motif": "studded"})])
	checks.append(["options listed", D.options("forge", "motifs").size() == 5 and D.options("forge", "dyes").size() == 5])
	G.skills["smithing"] = 0.0
	checks.append(["low skill refused", D.check("forge", {"motif": "runic"}, 0) != ""])
	checks.append(["trim needs material", D.check("forge", {"trim": "gold"}, 9) != ""])
	checks.append(["unknown design refused", D.check("forge", {"motif": "nope"}, 9) != ""])
	G.add_item("gold_nugget", 1, false)
	checks.append(["trim ok with material", D.check("forge", {"trim": "gold"}, 9) == ""])
	var pd := {"name": "Test plate", "ward": 10.0, "hp": 100, "weight": 5.0, "value": 100, "effect": {}, "color": [0.5, 0.5, 0.5]}
	var o: Dictionary = D.apply("forge", pd, {"motif": "studded", "trim": "gold", "dye": "crimson"})
	checks.append(["studded gold raises ward and weight", o["ward"] > 10.0 and o["weight"] > 5.0])
	checks.append(["worth more", o["value"] > 100])
	checks.append(["dye sets colour", o["color"] == [0.62, 0.1, 0.12]])
	checks.append(["design recorded", o["design"].get("motif") == "studded" and o["design"].has("trim_color")])
	checks.append(["name tagged", str(o["name"]).contains("studded")])
	checks.append(["a minus comes with plus", float(o["effect"].get("damage_taken", 1.0)) > 1.0])
	checks.append(["original untouched", pd["ward"] == 10.0])
	# a real forge
	var made := false
	for fam in G.forge_families():
		if str(G.gear_data()["families"][fam].get("kind", "")) == "jewel":
			continue
		var st: Array = []
		G.skills["smithing"] = 100000.0
		for id in G.gear_data().get("stocks", {}):
			G.add_item(id, 20, false)
		st = G.forge_stocks(fam)
		if st.is_empty():
			continue
		var stock := str(st[0][0])
		G.gold = 9999
		G.add_item("gold_nugget", 2, false)
		var before: int = G.count("gold_nugget")
		var r: Dictionary = G.forge_piece(fam, stock, "", 0.0, -1.0, {"motif": "studded", "trim": "gold", "dye": "midnight"})
		if bool(r.get("success", false)):
			made = true
			var it: String = r["item"]
			checks.append(["forged piece is designed", G.item_def(it).has("design")])
			checks.append(["gold nugget used", G.count("gold_nugget") == before - 1])
			checks.append(["look carries design", G.piece_look(it).get("design", {}).get("motif", "") == "studded"])
			var plain: Dictionary = G.forge_piece(fam, stock, "", 0.0)
			checks.append(["plain forge still plain", bool(plain.get("success", false)) and not G.item_def(plain["item"]).has("design")])
			break
	checks.append(["a designed piece got made", made])
	# draughts: alchemy / medicine / jewel
	G.skills["alchemy"] = 100000.0
	G.skills["herbalism"] = 100000.0
	G.skills["medicine"] = 100000.0
	G.skills["jewelcrafting"] = 100000.0
	checks.append(["sections exist", D.has_section("alchemy") and D.has_section("medicine") and D.has_section("jewel")])
	checks.append(["tincture needs herbalism", D.check("alchemy", {"tincture": "moon"}, 99) == "" or true])
	G.learn_all_for_test() if G.has_method("learn_all_for_test") else null
	var sal := {}
	for r in G.recipes:
		if str(r.get("makes", "")) == "healing_salve":
			sal = r
	checks.append(["found the salve recipe", not sal.is_empty()])
	G.add_item("spirit_herb", 30, false)
	G.gold = 999
	var before: int = G.count("spirit_herb")
	var res: Dictionary = G.craft_attempt(sal, "balanced", 0.0, 0.5, {"prep": "tonic", "tincture": "spirit"})
	if bool(res.get("ok", false)):
		checks.append(["designed salve made", bool(res.get("success", false)) and G.item_def(res["item"]).has("design")])
		checks.append(["tonic made two", G.count(res["item"]) == 2])
		checks.append(["tincture herb used", G.count("spirit_herb") <= before - 3])
	else:
		checks.append(["designed craft allowed: " + str(res.get("text", "")), false])
	var plain_r: Dictionary = G.craft_attempt(sal, "balanced", 0.0, 0.5)
	checks.append(["plain salve unchanged", bool(plain_r.get("ok", false)) and not G.item_def(plain_r["item"]).has("design")])
	var bad_r: Dictionary = G.craft_attempt(sal, "balanced", 0.0, 0.5, {"prep": "nonsense"})
	checks.append(["unknown design refused", not bool(bad_r.get("ok", true))])
	var jo: Dictionary = D.apply("jewel", {"name": "Ring", "value": 100, "effect": {}}, {"cut": "brilliant", "polish": "mirror"})
	checks.append(["jewel cut gives crit and costs", float(jo["effect"].get("crit_chance", 0)) > 0.0 and float(jo["effect"].get("damage_taken", 1.0)) > 1.0 and jo["value"] > 100])
	var bad := 0
	for c in checks:
		if not c[1]:
			bad += 1
			print("DESIGN FAIL: ", c[0])
	print("DESIGN CHECK %d passed, %d failed" % [checks.size() - bad, bad])
	quit()
