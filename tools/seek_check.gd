extends SceneTree
## Round 155: one human follows, both slots search.
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
	G.save_path = "user://seek_save.json"
	G.save_base = "user://seek_slots"
	G.new_game()
	var S = G.sys("seek")
	check("system exists", S != null)
	for k in S.kinds():
		for tier in S.kinds()[k]["tiers"]:
			for id in tier["items"]:
				check("%s item %s exists" % [k, id], G.items.has(str(id)))
	check("four kinds", S.kinds().size() == 4)
	G.companion = {"name": "Aria", "persona": "Aria", "home": "village", "tint": [1, 1, 1]}
	G.companion2 = {"name": "Brin", "persona": "Brin", "home": "village", "tint": [1, 1, 1]}
	G.flags["travelled:Aria"] = true
	G.flags["travelled:Brin"] = true
	check("no search yet", not S.searching(0) and not S.searching(1))
	check("nobody in a missing slot", S.block(1, "plants") == "" and G.companion2.has("name"))
	check("starts slot 0", S.start(0, "plants", 1.0) == "" and S.searching(0) and bool(G.companion.get("away", false)))
	check("starts slot 1", S.start(1, "jewels", 2.0) == "" and S.searching(1))
	check("no double search", S.block(0, "plants") != "")
	check("expedition blocked while searching", G.can_send("companion") != "")
	var tz: Array = G.sys("pull").candidates().filter(func(x): return str(x[1]).find("search") >= 0)
	check("a search shows as a teaser candidate", tz.size() == 2)
	G.part_with_companion(1)
	check("cannot send home while searching", G.companion2.has("name"))
	check("timer", S.left(0) > 3000.0 and S.left(1) > 7000.0)
	check("depth 1 pool has base items only", S.pool("plants").size() == 4)
	var save: Dictionary = G.companion.duplicate(true)
	G.companion["search"]["end"] = G._now() - 1.0
	G.companion2["search"]["end"] = G._now() - 1.0
	var spirit0: int = G.count("spirit_herb") + G.count("ember_root") + G.count("moonpetal") + G.count("iron_thistle")
	var jade0: int = G.count("rough_jade") + G.count("rough_ruby") + G.count("sapphire_shard") + G.count("silver_ore") + G.count("gold_nugget")
	S.tick(3.5)
	check("slot 0 home", not G.companion.has("search") and not G.companion.has("away"))
	check("slot 1 home", not G.companion2.has("search") and not G.companion2.has("away"))
	var spirit1: int = G.count("spirit_herb") + G.count("ember_root") + G.count("moonpetal") + G.count("iron_thistle")
	var jade1: int = G.count("rough_jade") + G.count("rough_ruby") + G.count("sapphire_shard") + G.count("silver_ore") + G.count("gold_nugget")
	check("plants found", spirit1 > spirit0)
	check("jewels found", jade1 > jade0)
	check("can search again", S.block(0, "shards") == "")
	check("swap carries search state", S.start(1, "reagents", 1.0) == "" and (G.swap_party() or true) and G.companion.has("search") and not G.companion2.has("search"))
	# overflow: a full pouch sends the rest to the chest (nothing bought or found is lost)
	G.home["have"] = true
	G.home["stash"] = {}
	G.inventory["nanite_shard"] = 15
	G.add_item("nanite_shard", 10, false)
	check("pouch fills to the cap", G.count("nanite_shard") == G.pouch_cap())
	check("the rest went to the chest", int(G.home["stash"].get("nanite_shard", 0)) == 25 - G.pouch_cap())
	G.home["have"] = false
	G.home["stash"] = {}
	G.marks = 10
	G.inventory["nanite_shard"] = 18
	var r: String = G.buy_with_marks("nanites")
	check("no chest, full pouch: nothing spent", G.marks == 10 and r != "")
	print("seek_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
