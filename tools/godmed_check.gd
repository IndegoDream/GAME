extends SceneTree
## Round 181: god mode does every craft, crafting runs while you sit, and a passive redraw never frees an open dropdown.
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
	G.playlog_path = "user://godmed_playlog.jsonl"
	G.save_path = "user://godmed_save.json"
	G.save_base = "user://godmed_slots"
	var Tst = load("res://scripts/systems/Tester.gd")
	var ff := "user://godmed_flavor.json"
	var fw := FileAccess.open(ff, FileAccess.WRITE)
	fw.store_string(JSON.stringify({"clean": true, "assist": true}))
	fw.close()
	Tst.flavor_path = ff
	G.new_game()
	var T = G.sys("tester")
	var taught := ""
	for sid in G.skill_defs:
		if bool(G.skill_defs[sid].get("teach", false)):
			taught = str(sid)
			break
	check("a taught craft exists", taught != "")
	T.assist_god = false
	check("god off: a taught craft is locked", not G.skill_known(taught))
	T.assist_god = true
	check("god on: every craft is known", G.skill_known(taught))
	check("god on: bionics/foundry/cooking/tattoos work outside a town", G.sys("bionics").in_town() and G.sys("foundry").in_town())
	T.assist_god = false
	check("god off: not outside a town", not G.sys("foundry").in_town() or G.havens.has(G.current_level))
	T.assist_god = true
	# crystals
	var cid := ""
	for id in G.items:
		if G.is_crystal(str(id)):
			cid = str(id)
			break
	if cid != "":
		G.inventory[cid] = 1
		check("god on: a crystal is ready at any realm", G.crystal_ready(cid) == "")
	# sit craft
	var r: Dictionary = {}
	for rc in G.recipes:
		if str(rc.get("makes", "")) == "healing_salve":
			r = rc
	check("found a plain recipe", not r.is_empty())
	for need in r.get("needs", {}):
		G.inventory[str(need)] = 40
	check("first craft", G.craft(r))
	var CB = G.sys("craftbook")
	var key := ""
	for k in CB.order:
		if str(CB.recipes[k].get("kind", "")) == "recipe":
			key = str(k)
	check("journal has it", key != "")
	var times0: int = int(CB.recipes[key].get("times", 1))
	G.sitting = false
	check("sit job set", CB.sit_start(key, 3) != "")
	CB.tick(5.0)
	check("standing: nothing is made", int(CB.recipes[key].get("times", 1)) == times0 and CB.sit_done == 0)
	G.sitting = true
	CB.tick(1.1)
	check("sitting: one made", CB.sit_done == 1 and CB.sit_left == 2)
	CB.tick(0.5)
	check("not before the gap", CB.sit_done == 1)
	CB.tick(1.1)
	CB.tick(1.1)
	check("all three made, job over", not CB.sit_active() and int(CB.recipes[key].get("times", 1)) == times0 + 3)
	# ran out
	T.assist_god = false
	for need in r.get("needs", {}):
		G.inventory.erase(str(need))
	CB.sit_start(key, 5)
	CB.tick(10.0)
	check("out of materials: the job stops", not CB.sit_active())
	# dropdown guard
	var UI = load("res://scripts/core/UiStyle.gd")
	var page := VBoxContainer.new()
	root.add_child(page)
	var ob := OptionButton.new()
	ob.add_item("a")
	ob.add_item("b")
	page.add_child(ob)
	await process_frame
	check("closed dropdown: not busy", not UI.input_busy(page))
	ob.show_popup()
	await process_frame
	check("open dropdown: busy", UI.input_busy(page))
	ob.get_popup().hide()
	await process_frame
	check("closed again: not busy", not UI.input_busy(page))
	print("godmed_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
