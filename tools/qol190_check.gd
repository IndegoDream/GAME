extends SceneTree
## round 190, from Robert's play log: 107 of 110 attribute points went in one click each; 400 coins went in the
## fountain, but nothing happened after the hundredth. Points: +5, All, Spread evenly. Fountain: it keeps counting.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"
	G.save_path = "user://tool_shot.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	# --- attributes
	G.realm = 6
	G.attrs = {}
	var free: int = G.attr_points_free()
	check("there are points to spend", free >= 10, str(free))
	var ids: Array = G.attr_ids()
	var a0: String = str(ids[0])
	var before: int = G.attr_total(a0)
	check("+5 spends five at once", G.attr_spend(a0, 5) and G.attr_total(a0) == before + 5 and G.attr_points_free() == free - 5)
	check("can't spend more than you have", not G.attr_spend(a0, 9999))
	var n: int = G.attr_spread()
	check("spread spends every free point", n == free - 5 and G.attr_points_free() == 0, "%d %d" % [n, G.attr_points_free()])
	var lo := 99999
	var hi := 0
	for id in ids:
		if str(id) == a0:
			continue
		lo = mini(lo, G.attr_total(str(id)))
		hi = maxi(hi, G.attr_total(str(id)))
	check("spread fills the lowest first (the rest end within one of each other)", hi - lo <= 1 or G.attr_total(a0) <= lo, "%d..%d" % [lo, hi])
	check("spread with nothing free does nothing", G.attr_spread() == 0)
	G.attrs = {}
	var all_free: int = G.attr_points_free()
	check("All puts every point in one", G.attr_spend(a0, all_free) and G.attr_points_free() == 0)
	# --- a seasoned fighter from before weapon arts: one line, not twenty
	var said0 := []
	var cb0 := func(t): said0.append(str(t))
	G.message.connect(cb0)
	for w in ["sword", "spear", "bow", "staff", "dagger"]:
		G.skills[w] = 50000.0
	for k in G.techniques.keys():
		if str(k).begins_with("w_"):
			G.techniques.erase(k)
	G.sys("arts").sync()
	G.message.disconnect(cb0)
	var wl: Array = G.techniques.keys().filter(func(k): return str(k).begins_with("w_"))
	check("all the weapon arts earned come at once", wl.size() >= 15, str(wl.size()))
	check("in one line, not one each", said0.filter(func(t): return t.begins_with("WEAPON ARTS:")).size() == 1 and said0.filter(func(t): return t.begins_with("TECHNIQUE LEARNED") or t.begins_with("WEAPON ART:")).size() == 0, str(said0.size()))
	# --- the fountain
	var F = load("res://scripts/objects/Fountain.gd").new()
	var said := []
	var cb := func(t): said.append(str(t))
	G.message.connect(cb)
	G.gold = 100000
	G.counters["coins"] = 449
	F.interact(null)
	check("every fiftieth coin, the water counts", said.size() > 0 and said[-1].find("450") >= 0, str(said.slice(-1)))
	G.counters["coins"] = 499
	var g0: int = G.gold
	var pills0: int = G.count("breakthrough_pill")
	F.interact(null)
	check("the 500th coin gives something back", G.gold > g0, "%d -> %d" % [g0, G.gold])
	G.counters["coins"] = 776
	F.interact(null)
	check("the 777th coin: a pill", G.count("breakthrough_pill") == pills0 + 1)
	G.counters["coins"] = 1999
	F.interact(null)
	check("every thousandth coin: two pills", G.count("breakthrough_pill") == pills0 + 3)
	G.counters["coins"] = 1000
	var g1: int = G.gold
	F.interact(null)
	check("an ordinary coin costs one gold", G.gold == g1 - 1)
	G.message.disconnect(cb)
	F.free()
	# --- wear the better pieces
	G.equipment = {}
	var slot_a := ""
	var fam_a := ""
	for sl in G.gear_slots():
		if str(sl[2]) in G.WEAR_TYPES:
			slot_a = str(sl[0])
			fam_a = str(sl[2])
			break
	var pieces := []
	for id in G.items.keys():
		var d: Dictionary = G.items[id]
		if G.gear_family(str(id)) == fam_a and G._plain_piece(str(id)) and d.has("hp"):
			pieces.append(str(id))
	pieces.sort_custom(func(x, y): return int(G.items[x].get("hp", 0)) + G.piece_ward(x) < int(G.items[y].get("hp", 0)) + G.piece_ward(y))
	check("there are plain %s pieces to compare" % fam_a, pieces.size() >= 2, str(pieces.size()))
	if pieces.size() >= 2:
		var weak: String = pieces[0]
		var strong: String = pieces[-1]
		G.inventory[weak] = 1
		G.inventory[strong] = 1
		G.equipment[slot_a] = weak
		check("the stronger piece is plainly better", G.better_piece(weak, strong), "%s %d/%.1f vs %s %d/%.1f" % [weak, G.items[weak].get("hp", 0), G.piece_ward(weak), strong, G.items[strong].get("hp", 0), G.piece_ward(strong)])
		var said2: String = G.wear_better()
		check("Wear the better pieces swaps it in", G.worn(slot_a) == strong, said2)
		check("and says so", said2.find(G.item_name(strong)) >= 0, said2)
		check("a second press finds nothing better", G.wear_better().begins_with("Nothing"))
		check("never a worse piece", not G.better_piece(strong, weak))
		# a piece made for you (worked at the bench) is the player's choice: never swapped out
		var mine := weak + "_mine190"
		G.custom_items[mine] = (G.items[weak] as Dictionary).duplicate(true)
		G.items[mine] = G.custom_items[mine]
		G.inventory[mine] = 1
		G.equipment[slot_a] = mine
		G.wear_better()
		check("a piece you made stays on", G.worn(slot_a) == mine, G.worn(slot_a))
		G.custom_items.erase(mine)
	# jewellery and weapons are never touched
	var w0: String = G.weapon
	G.wear_better()
	check("the weapon is left alone", G.weapon == w0)
	# --- the buttons, through the real character page
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	G.new_game()
	G.realm = 6
	G.attrs = {}
	var hud = root.get_tree().get_first_node_in_group("hud")
	for i in 30:
		await process_frame
	if hud != null and hud._title != null and hud._title.visible:
		hud.close_title()
	for nm in ["_title", "_create", "_ending"]:
		if hud != null and hud.get(nm) != null:
			hud.get(nm).visible = false
	if hud._dialog.visible:
		hud.close_dialog()
	hud._hub.show_page("You")
	for i in 3:
		await process_frame
	var btn := func(t: String) -> Array:
		return root.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with(t) and (b as Button).is_visible_in_tree())
	var Hub = load("res://scripts/ui/Hub.gd")
	var mk: Dictionary = Hub.ready_marks()
	check("the menu marks You while points wait", mk.has("You"), str(mk))
	hud._hub._update_marks(true)
	check("the You button carries the dot", hud._hub.buttons["You"].text.ends_with("•") and hud._hub.buttons["You"].tooltip_text != "", hud._hub.buttons["You"].text)
	check("a page with nothing waiting has no dot", not hud._hub.buttons["System"].text.ends_with("•"))
	var f0: int = G.attr_points_free()
	check("the page offers +5 and All beside each attribute", btn.call("+5").size() == ids.size() and btn.call("All (").size() == ids.size(), "%d %d" % [btn.call("+5").size(), btn.call("All (").size()])
	var sp: Array = btn.call("Spread them evenly")
	check("and one Spread evenly button", sp.size() == 1)
	if OS.get_environment("SHOTS") != "":
		hud._create.visible = false
		for i in 3:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("/tmp/qol_attrs.png")
	if sp.size() == 1:
		(sp[0] as Button).pressed.emit()
		for i in 2:
			await process_frame
	hud._hub.show_page("Pack")
	for i in 3:
		await process_frame
	check("the pack offers Wear the better pieces", btn.call("Wear the better pieces").size() == 1)
	if OS.get_environment("SHOTS") != "":
		for i in 3:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("/tmp/qol_pack.png")
	hud._hub.show_page("You")
	for i in 3:
		await process_frame
	sp = btn.call("Spread them evenly")
	if sp.size() == 1:
		(sp[0] as Button).pressed.emit()
		for i in 2:
			await process_frame
	# --- the bench: a sure thing, again and again
	var T = G.sys("tester")
	var was_en = T.enabled if T != null else false
	if T != null:
		T.enabled = true
		T.god_on = true
	G.at_bench = "home"
	var kit = hud._kit
	var gbase := "g_iron_ore_gauntlets"
	G.inventory[gbase] = 1
	G.inventory["bone_shard"] = 3
	kit.bench_set(gbase, ["bone_shard"])
	var pvb: Dictionary = G.combine_preview(gbase, ["bone_shard"])
	check("god craft makes it a sure thing", bool(pvb["ok"]) and float(pvb["chance"]) >= 0.999, str(pvb.get("chance")))
	hud._hub.show_page("Pack")
	kit.show_tab("Bench")
	for i in 3:
		await process_frame
	check("the bench offers 'again and again'", btn.call("Work it again and again").size() == 1)
	if T != null:
		T.infinite_on = false
	var bone0: int = G.count("bone_shard")
	var nd: int = kit.bench_go_many(5)
	check("it works until something runs out (3 shards -> 3 times, not 5)", nd >= 1 and nd <= 3 and G.count("bone_shard") == bone0 - nd, "%d done, shards %d -> %d" % [nd, bone0, G.count("bone_shard")])
	check("and the improved piece stays on the bench", kit.bench_base != "" and G.gear_family(kit.bench_base) != "", kit.bench_base)
	if T != null:
		T.infinite_on = true
		T.enabled = was_en
	hud._hub.show_page("You")
	for i in 3:
		await process_frame
	check("pressing it spends them all", f0 > 0 and G.attr_points_free() == 0, "%d -> %d" % [f0, G.attr_points_free()])
	hud._hub._update_marks(true)
	check("spent: the dot goes", not hud._hub.buttons["You"].text.ends_with("•"), hud._hub.buttons["You"].text)
	check("and the buttons go away", btn.call("+5").size() == 0 and btn.call("Spread them evenly").size() == 0)
	print("QOL190 CHECK %d passed, %d failed" % [passed, failed])
	quit(0)
