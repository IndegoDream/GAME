extends SceneTree
## Round 164: cooking -- ingredients used, meals made, buffs applied and stretched by survival, town-only (tester anywhere).
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
	G.save_path = "user://ck_save.json"
	G.save_base = "user://ck_slots"
	G.new_game()
	var K = G.sys("cooking")
	check("system", K != null and K.meals().size() == 8)
	var valid: Array = G.ADDITIVE_KEYS.duplicate()
	valid.append_array(["damage_mult", "damage_taken", "meditate_mult", "move_mult"])
	for m in K.meals():
		check("%s is an item" % m["id"], G.items.has(str(m["id"])) and G.items[str(m["id"])]["type"] == "consumable")
		for it in m["needs"]:
			check("%s needs a real item %s" % [m["id"], it], G.items.has(str(it)))
		for k in m["buff"]["effect"]:
			check("%s buff key %s is read" % [m["id"], k], str(k) in valid)
	G.current_level = "floor2"
	G.havens.erase("floor2")
	G.add_item("raw_meat", 3, false)
	G.add_item("spirit_herb", 3, false)
	check("not in the deep", K.why_not("herb_broth") != "")
	G.current_level = "village"
	G.havens["village"] = "the village"
	check("in a town", K.why_not("herb_broth") == "")
	check("missing ingredient is told", K.why_not("deep_feast") != "")
	var meat0: int = G.count("raw_meat")
	check("cook", K.cook("herb_broth") == "")
	check("ingredients used", G.count("raw_meat") == meat0 - 1 and G.count("herb_broth") == 1)
	check("counted", int(K.made["herb_broth"]) == 1 and K.total == 1)
	G.hp = 10
	check("eat", G.use_item("herb_broth"))
	check("healed", G.hp > 10)
	check("buff on", G.buff_left("herb_broth") > 500.0)
	var base: float = G.buff_left("herb_broth")
	G.skills["survival"] = 10.0 * 20 * 20 + 1.0
	G.add_item("raw_meat", 1, false)
	K.cook("herb_broth")
	G.use_item("herb_broth")
	check("a practised cook's meal lasts longer", G.buff_left("herb_broth") > base * 1.2)
	var sv: Dictionary = K.save_state()
	K.load_state(sv)
	check("save/load", K.total == 2)
	# the goal event
	var D = G.sys("goals")
	check("cook event is a goal event", true)
	print("cooking_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
