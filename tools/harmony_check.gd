extends SceneTree
## Round 155b: with every aspect alive, a clash tempers (strengthens) instead of costing qi.
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
	G.save_path = "user://harm_save.json"
	G.save_base = "user://harm_slots"
	G.new_game()
	for e in G.ELEMENTS:
		G.affinity[e] = 0.0
	G.affinity["fire"] = 40.0
	G.affinity["water"] = 40.0
	var f1: Dictionary = G.affinity_effect()
	check("incomplete: a clash costs qi", float(f1["qi_mult"]) < 1.0)
	check("incomplete: not harmony", not G.all_aspects_alive())
	check("incomplete: clash is listed", G.affinity_status()["clashes"].size() >= 1)
	for e in G.ELEMENTS:
		G.affinity[e] = 40.0
	check("all alive: harmony", G.all_aspects_alive())
	var f2: Dictionary = G.affinity_effect()
	check("all alive: no qi penalty, a bonus", float(f2["qi_mult"]) > 1.0)
	check("all alive: no clash war listed", G.affinity_status()["clashes"].is_empty())
	check("all alive: tempered listed", (G.affinity_status()["synergies"] as Array).any(func(x): return str(x).begins_with("Tempered") or str(x).find("Tempered") >= 0))
	# compare against the same elements without the tempering: hp and gifts are higher than plain
	var plain_hp: float = 1.0 + 0.4 * 1.4 * 0.2
	check("foundation grows (hp)", float(f2["hp_mult"]) > plain_hp)
	G.affinity["fire"] = 70.0
	var f3: Dictionary = G.affinity_effect()
	check("a lopsided build still harmonises (no clash, no penalty)", float(f3["qi_mult"]) >= 1.0)
	print("harmony_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
