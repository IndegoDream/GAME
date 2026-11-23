extends SceneTree
## Round 176: the Assist page in a CLEAN build -- god mode (damage only), floor warp, map warp -- and nothing else switched on.
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
	G.playlog_path = "user://assist_playlog.jsonl"
	G.save_path = "user://assist_save.json"
	G.save_base = "user://assist_slots"
	var Tst = load("res://scripts/systems/Tester.gd")
	var ap := "user://assist_slots_account.json"
	var ff := "user://assist_flavor.json"
	# a dev account with a vault in it: the clean build must leave it alone
	var wf := FileAccess.open(ap, FileAccess.WRITE)
	wf.store_string(JSON.stringify({"vault": {"iron_ore": 12}, "tester": true, "god": true}))
	wf.close()
	var fw := FileAccess.open(ff, FileAccess.WRITE)
	fw.store_string(JSON.stringify({"clean": true, "assist": true}))
	fw.close()
	Tst.flavor_path = ff
	G.new_game()
	var T = G.sys("tester")
	check("clean + assist", T.clean() and T.assist())
	check("kit stays off: no vault, no free tables, no endless, no open locks", not T.vault_on() and not T.endless() and not T.unlocked() and not T.infinite())
	check("assist is on", T.assist_ok())
	check("god mode starts off", not T.god())
	var hp0: int = G.hp
	G.hurt(5)
	check("damage lands with god mode off", G.hp < hp0)
	T.assist_god = true
	check("god mode on", T.god())
	var hp1: int = G.hp
	G.hurt(50)
	check("god mode: no damage", G.hp == hp1)
	G.player_died("test")
	check("god mode: death does not end you", G.hp == G.max_hp())
	# round 178: held consumables/materials never run out under god mode, and still work
	G.inventory["healing_salve"] = 3
	check("held consumables are free under god mode", T.free_item("healing_salve") and G.count("healing_salve") == 3)
	G.hp = maxi(1, int(G.max_hp() * 0.5))
	var hpu: int = G.hp
	G.use_item("healing_salve")
	check("a salve still heals under god mode", G.hp > hpu)
	check("...and the stack is not used up", G.count("healing_salve") == 3)
	check("gear is never free", not T.free_item("iron_sword") or str(G.item_def("iron_sword").get("type","")) in ["material","consumable"])
	check("selling a free item pays nothing", G.sell("healing_salve", 1) == 0 and G.count("healing_salve") == 3)
	T.tick(0.1)
	check("tick does not invent stock", G.count("healing_salve") == 3)
	T.assist_god = false
	check("god off: items used up again", not T.free_item("healing_salve"))
	T.assist_god = true
	# round 179: god mode crafts from anywhere at 100%, the chest holds anything, nothing weighs you down
	var hard := {"skill": "smithing", "difficulty": 40, "needs": {}, "makes": "healing_salve", "gold": 0}
	check("god: craft chance is 100%", T.god_craft() and G.craft_chance(hard) == 1.0)
	check("god: portable bench", T.portable_bench() and G.road_bench() == G.road_bench())
	G.inventory["iron_sword"] = 2
	G.inventory["healing_salve"] = 5
	G.inventory["iron_ore"] = 30
	var moved: int = G.stash_everything()
	check("god: chest takes everything", moved >= 37 and G.count("iron_sword") == 0 and int(G.stash_ref().get("iron_sword", 0)) == 2 and int(G.stash_ref().get("healing_salve", 0)) == 5)
	G.take_everything()
	check("god: take it all back", G.count("iron_sword") == 2 and G.count("healing_salve") == 5 and G.stash_ref().is_empty())
	G.inventory["iron_ore"] = 99999
	check("god: no weight slowdown", G.weight_penalty() == 0.0)
	T.assist_god = false
	check("god off: odds are the normal ones", not T.god_craft() and G.craft_chance(hard) < 1.0)
	T.assist_god = true
	T.god_stock()
	check("god: every material/consumable/rune stocked", G.count("iron_ore") >= 999 and G.count("healing_salve") >= 999 and G.count("nanite_shard") >= 999)
	var every := true
	for id in G.items:
		if str(G.items[id].get("type", "")) in ["material", "consumable", "rune"] and G.count(str(id)) < 999:
			every = false
	check("god: nothing missing from the stock", every)
	G.use_item("healing_salve")
	check("god: use keeps it at 999", G.count("healing_salve") >= 999)
	T.assist_god = false
	T.assist_god = true
	# the switch is remembered, the dev vault is untouched
	T._dirty = true
	T._flush()
	var d = JSON.parse_string(FileAccess.get_file_as_string(ap))
	check("assist_god saved", d is Dictionary and bool(d.get("assist_god", false)))
	check("dev vault left alone", d is Dictionary and int(d.get("vault", {}).get("iron_ore", 0)) == 12)
	# warps
	check("can warp", T.can_warp())
	G.warp_pass = false
	var went := []
	G.level_change_requested.connect(func(id, tag): went.append([id, tag]))
	T.teleport("floor3", ">")
	await process_frame
	check("floor warp went to floor3, the way down", went.size() == 1 and went[0][0] == "floor3" and went[0][1] == ">")
	check("the pass is used up", not G.warp_pass)
	check("floor list has village, valley, floors", T.floor_ids().size() >= 3 and T.floor_ids()[0] == "village")
	# off in the online world / when the flavor has no assist
	var fw2 := FileAccess.open(ff, FileAccess.WRITE)
	fw2.store_string(JSON.stringify({"clean": true}))
	fw2.close()
	check("no assist flag: no assist", not T.assist() and not T.can_warp())
	T.assist_god = true
	check("no assist flag: god mode is off", not T.god())
	Tst.flavor_path = "res://data/build_flavor.json"
	DirAccess.remove_absolute(ap)
	DirAccess.remove_absolute(ff)
	print("assist_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
