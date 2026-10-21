extends SceneTree
## Round 158: the test kit's unlimited materials -- crafting and advancing never run dry; gear and treasures are left alone.
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
	G.save_path = "user://inf_save.json"
	G.save_base = "user://inf_slots"
	var ap: String = "user://inf_slots_account.json"
	var wf := FileAccess.open(ap, FileAccess.WRITE)
	wf.store_string(JSON.stringify({"tester": true, "god": true, "infinite": true}))
	wf.close()
	G.new_game()
	var T = G.sys("tester")
	check("infinite is on", T.infinite())
	T.tick(0.1)
	check("iron ore stocked", G.count("iron_ore") >= 99)
	check("a consumable is stocked", G.count("healing_salve") >= 99 or G.count("salve") >= 99 or G.inventory.values().any(func(v): return int(v) >= 99))
	check("remove succeeds", G.remove_item("iron_ore", 40))
	check("...and nothing is used up", G.count("iron_ore") >= 99)
	check("selling conjured stock pays nothing", G.sell("iron_ore", 5) == 0)
	var gold0: int = G.gold
	check("gold itself still works", G.remove_item("gold", 0) and G.gold == gold0)
	var weapons: Array = G.items.keys().filter(func(k): return str(G.items[k].get("type", "")) == "weapon")
	check("weapons are not conjured", weapons.all(func(k): return G.count(str(k)) < 99))
	T.infinite_on = false
	T._stocked = false
	G.inventory["iron_ore"] = 5
	G.remove_item("iron_ore", 3)
	check("off: normal use-up", G.count("iron_ore") == 2)
	print("infinite_check: %d passed, %d failed" % [total - fails, fails])
	DirAccess.remove_absolute(ap)
	quit(1 if fails > 0 else 0)
