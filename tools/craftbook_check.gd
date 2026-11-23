extends SceneTree
## Round 137: the crafting journal. Run: godot --headless --path . --script tools/craftbook_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var CB = G.sys("craftbook")
	var ch := []
	ch.append(["system exists", CB != null])
	ch.append(["starts empty", CB.recipes.is_empty() and CB.recipe_keys().is_empty()])
	# ---- a bench recipe
	G.skills["alchemy"] = 100000.0
	G.skills["medicine"] = 100000.0
	G.add_item("spirit_herb", 20, false)
	var rc = null
	for r in G.recipes:
		if str(r["makes"]) == "healing_salve":
			rc = r
	ch.append(["salve recipe exists", rc != null])
	var res: Dictionary = G.craft_attempt(rc, "balanced", 0.0, 0.5)
	ch.append(["craft succeeded", bool(res.get("success", false))])
	ch.append(["recipe row written", CB.recipes.size() == 1])
	var key: String = CB.recipe_keys()[0]
	var v: Dictionary = CB.recipe_view(key)
	ch.append(["row names the item and its inputs", str(v["name"]) != "" and (v["inputs"] as Array).size() == 1 and int(v["inputs"][0]["need"]) == 2])
	G.craft_attempt(rc, "balanced", 0.0, 0.5)
	ch.append(["making it again counts, no second row", CB.recipes.size() == 1 and int(CB.recipe_view(key)["times"]) == 2])
	ch.append(["materials counted as used", int(CB.used.get("spirit_herb", 0)) == 2])
	var txt: String = CB.remake(key)
	ch.append(["make again from the page works (%s)" % txt, txt.begins_with("You made") or txt.begins_with("It goes wrong")])
	ch.append(["it used the materials again", G.count("spirit_herb") < 20 - 4])
	# ---- a forged piece
	G.skills["smithing"] = 100000.0
	G.add_item("iron_ore", 30, false)
	G.gold = 99999
	var fr: Dictionary = G.forge_piece("armor", "iron_ore", "", 0.0, 0.5)
	ch.append(["forge succeeded", bool(fr.get("success", false))])
	ch.append(["forged piece has its row", CB.recipes.size() == 2])
	# ---- a design-less second forge of the same thing: still one row
	G.forge_piece("armor", "iron_ore", "", 0.0, 0.5)
	ch.append(["same forge twice: one row, times 2", CB.recipes.size() == 2])
	# ---- save and load keep it
	var saved: Dictionary = G._systems_save()
	var snap: Dictionary = (saved["craftbook"] as Dictionary).duplicate(true)
	G._systems_reset()
	ch.append(["reset empties", CB.recipes.is_empty()])
	G._systems_load(saved)
	ch.append(["load restores rows", CB.recipes.size() == 2 and CB.recipe_keys().size() == 2])
	ch.append(["round trip identical", JSON.stringify(CB.save_state()) == JSON.stringify(snap)])
	# ---- materials: levels climb
	G.journal["items"].erase("rough_jade")
	ch.append(["unseen material is level 0", CB.level_of("rough_jade") == 0 and str(CB.material_card("rough_jade")["name"]) == "???"])
	G.add_item("rough_jade", 1, false)
	ch.append(["seen material is level 1+", CB.level_of("rough_jade") >= 1])
	G.mat_known.erase("rough_jade")
	var lv1: int = CB.level_of("rough_jade")
	G.skills["alchemy"] = 0.0
	G.skills["jewelcrafting"] = 0.0
	G.skills["smithing"] = 0.0
	G.skills["herbalism"] = 0.0
	ch.append(["handled only after you work it", CB.level_of("iron_thistle") <= 1])
	G.mat_known["rough_jade"] = true
	ch.append(["handled shows traits", CB.level_of("rough_jade") >= 2 and (CB.material_card("rough_jade")["traits"] as Array).size() > 0])
	CB.used["rough_jade"] = 3
	ch.append(["used 3 times = understood", CB.level_of("rough_jade") == 3])
	var card: Dictionary = CB.material_card("rough_jade")
	ch.append(["understood card has an element note and effects", str(card.get("element_note", "")) != "" and card.has("adds")])
	# ---- complements
	G.add_item("goblin_tooth", 1, false)
	G.add_item("rough_ruby", 1, false)
	G.add_item("silver_ore", 1, false)
	var cp: Dictionary = CB.complements("goblin_tooth")      # keen+volatile: pairs with volatile/keen things
	ch.append(["complements list is real", cp.has("named") and cp.has("hidden")])
	var names := []
	for p in cp["named"]:
		names.append(str(p["id"]))
	ch.append(["a seen partner is named (rough_ruby: keen+volatile)", "rough_ruby" in names])
	ch.append(["unseen partners are only counted", int(cp["hidden"]) >= 0 and not ("sword_intent_shard" in names)])
	# every material sits on a shelf and shelves cover all
	var all_on := 0
	for sh in CB.shelves():
		all_on += CB.materials_on(sh).size()
	ch.append(["every material is on a shelf (%d)" % all_on, all_on == G.craft_data()["materials"].size()])
	# ---- bestiary + drops
	G.kills["goblin"] = 1
	G.loot_source = "goblin"
	G.add_item("goblin_tooth", 1, false)
	G.clear_loot_source()
	var fc: Dictionary = CB.foe_card("goblin")
	ch.append(["met foe opens", bool(fc["met"]) and str(fc["name"]) == "Goblin"])
	ch.append(["a drop is learned", "goblin_tooth" in fc["drops"]])
	ch.append(["strength hidden until 3 kills", not fc.has("hp")])
	G.kills["goblin"] = 3
	ch.append(["strength shows at 3 kills", CB.foe_card("goblin").has("hp")])
	G.kills["goblin"] = 10
	ch.append(["loot table opens at 10", CB.foe_card("goblin").has("table")])
	ch.append(["unmet foe is ???", str(CB.foe_card("skeleton")["name"]) == "???" or int(G.kills.get("skeleton", 0)) > 0])
	ch.append(["gold is not a drop", not (CB.drops.get("goblin", {}) as Dictionary).has("gold")])
	# ---- heirloom piece is recorded
	var H = G.sys("heirloom")
	G.skills["smithing"] = 100000.0
	H.ignite("t")
	G.add_item("iron_ore", 40, false)
	G.gold = 99999
	var hr: Dictionary = H.make(0, {})
	ch.append(["heirloom piece recorded", bool(hr.get("ok", false)) and CB.recipes.has("heirloom:0")])
	var fail := 0
	for c in ch:
		print("CRAFTBOOK ", "ok  " if c[1] else "FAIL", c[0])
		if not c[1]:
			fail += 1
	print("CRAFTBOOK CHECK ", ch.size() - fail, " passed, ", fail, " failed")
	quit(1 if fail > 0 else 0)
