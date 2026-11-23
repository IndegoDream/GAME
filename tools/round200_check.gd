extends SceneTree
## round 200: deep floor masters ease (combat.json "boss_ease"); a tabbed page's long sections are built when their tab
## is first shown; "Spread them evenly" sits at the top of the attributes.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _waiting(box: Node) -> int:
	var n := 0
	for c in box.get_children():
		if c.has_meta("lazy_build"):
			n += 1
	return n


func _tab(box: Node, title: String) -> Button:
	for c in box.get_children():
		if c.name == "PageTabs" and not c.is_queued_for_deletion():
			for b in c.get_children():
				if b is Button and (b as Button).text == title:
					return b
	return null


func _text(box: Node) -> String:
	var t := ""
	for l in box.find_children("*", "Label", true, false):
		t += (l as Label).text + "\n"
	return t


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://p200_save.json"
	G.save_base = "user://p200_slots"
	G.playlog_path = "user://p200_playlog.jsonl"
	G.new_game()
	# ---- 1. the ease
	check("no ease up to floor 25", is_equal_approx(G.boss_ease(1, "hp"), 1.0) and is_equal_approx(G.boss_ease(25, "hp"), 1.0) and is_equal_approx(G.boss_ease(25, "damage"), 1.0))
	check("full ease at floor 49 (health x0.75, damage x0.85)", is_equal_approx(G.boss_ease(49, "hp"), 0.75) and is_equal_approx(G.boss_ease(49, "damage"), 0.85))
	check("half way at floor 37", is_equal_approx(G.boss_ease(37, "hp"), 0.875))
	var steady := true
	for d in range(25, 49):
		if G.boss_ease(d + 1, "hp") > G.boss_ease(d, "hp") + 0.0001:
			steady = false
	check("it only ever eases as you go down", steady)
	check("the last master has its own (x0.7, x0.8)", is_equal_approx(G.boss_ease(50, "hp"), 0.7) and is_equal_approx(G.boss_ease(50, "damage"), 0.8))
	var keep: Dictionary = G.combat_data().get("boss_ease", {}).duplicate()
	G.combat_data().erase("boss_ease")
	check("without the table nothing changes", is_equal_approx(G.boss_ease(49, "hp"), 1.0))
	G.combat_data()["boss_ease"] = keep
	# a real master on a deep floor, and a plain foe beside it
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4:
		await process_frame
	G.depth = 46
	G.go_to("floor46", "<")
	var lv = null
	for i in 900:
		await process_frame
		lv = get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == "floor46" and lv.stream_left() == 0 and i > 60:
			break
	var boss = null
	for e in get_nodes_in_group("enemy"):
		if bool(G.enemies.get(e.etype, {}).get("boss", false)) and not e.minion:
			boss = e
	check("(floor 46 has its master)", boss != null)
	if boss != null:
		# the same master made again with the table switched off: the only difference is the ease
		var table: Dictionary = G.combat_data()["boss_ease"]
		G.combat_data().erase("boss_ease")
		var at: Vector3 = boss.global_position + Vector3(2.0, 0, 0)
		var twin = lv._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": boss.etype, "cell": boss.cell})
		G.combat_data()["boss_ease"] = table
		for i in 2:
			await process_frame
		check("(a twin without the ease)", twin != null)
		if twin != null:
			var rh: float = float(boss.stats["hp"]) / float(twin.stats["hp"])
			var rd: float = float(boss.stats["damage"]) / float(twin.stats["damage"])
			check("the master's health is eased by the table (%.3f vs %.3f)" % [rh, G.boss_ease(46, "hp")], absf(rh - G.boss_ease(46, "hp")) < 0.01)
			check("...and its damage (%.3f vs %.3f)" % [rd, G.boss_ease(46, "damage")], absf(rd - G.boss_ease(46, "damage")) < 0.01)
			twin.queue_free()
		var plain = null
		for e in get_nodes_in_group("enemy"):
			if not bool(G.enemies.get(e.etype, {}).get("boss", false)) and not bool(e.stats.get("passive", false)) and not e.minion:
				plain = e
				break
		if plain != null:
			G.combat_data().erase("boss_ease")
			var p2 = lv._spawn_script("res://scripts/actors/Enemy.gd", plain.global_position + Vector3(1.5, 0, 0), {"type": plain.etype, "cell": plain.cell, "style": plain.style, "affixes": plain.affixes})
			G.combat_data()["boss_ease"] = table
			for i in 2:
				await process_frame
			check("a plain foe is untouched", p2 != null and int(p2.stats["damage"]) == int(plain.stats["damage"]), "%s vs %s" % [str(p2.stats["damage"]) if p2 else "-", str(plain.stats["damage"])])
			if p2 != null:
				p2.queue_free()
	# ---- 2. sections wait for their tab
	var hud = null
	for n in root.find_children("*", "CanvasLayer", true, false):
		if n.get("_hub") != null:
			hud = n
	check("(the HUD is up)", hud != null)
	if hud != null:
		var hub = hud._hub
		var PT = load("res://scripts/ui/PageTabs.gd")
		G.kills["goblin"] = 12
		G.add_item("spirit_herb", 5, false)
		PT._sel.erase("Craft")
		hub.show_page("Craft")
		for i in 3:
			await process_frame
		var w0 := _waiting(hub._craft)
		check("the Craft page leaves its long sections for later (%d waiting)" % w0, w0 >= 3)
		check("...so the bestiary isn't made yet", not _text(hub._craft).contains("Foes met:"))
		var bt := _tab(hub._craft, "Bestiary")
		check("it still has its Bestiary tab", bt != null)
		if bt != null:
			bt.pressed.emit()
			for i in 2:
				await process_frame
			check("opening the tab makes the bestiary", _text(hub._craft).contains("Foes met:") and _waiting(hub._craft) == w0 - 1)
			hub._fill("Craft")
			for i in 2:
				await process_frame
			check("a redraw keeps you on that tab, with it made", _text(hub._craft).contains("Foes met:") and _waiting(hub._craft) == w0 - 1)
			check("...and the page's own box is back in place", hub._craft.get_parent() is ScrollContainer and is_same(hub.pages["Craft"], hub._craft.get_parent()))
		PT.build_all(hub._craft)
		check("everything can be made at once", _waiting(hub._craft) == 0 and _text(hub._craft).contains("Handle a material in a craft"))
		for sec in ["Works", "Journal"]:
			PT._sel.erase(sec)
			hub.show_page(sec)
			for i in 3:
				await process_frame
			var box: Node = hub._works if sec == "Works" else hud._jr_body
			check("the %s page waits too (%d)" % [sec, _waiting(box)], _waiting(box) >= 2)
			var n0: int = box.find_children("*", "", true, false).size()
			PT.build_all(box)
			check("...and fills when asked (%d -> %d nodes)" % [n0, box.find_children("*", "", true, false).size()], box.find_children("*", "", true, false).size() > n0 and _waiting(box) == 0)
			check("...leaving nothing held", G._fx_hold == 0)
		check("the Journal's places are there once made", _text(hud._jr_body).contains("visited"))
		var tl := _tab(hub._works, "Tailor")
		hub.show_page("Works")
		for i in 2:
			await process_frame
		tl = _tab(hub._works, "Tailor")
		if tl != null:
			tl.pressed.emit()
			for i in 2:
				await process_frame
			check("the Tailor opens from its tab", _text(hub._works).contains("Pick what you want worked on"))
		# ---- 3. the attributes' spread button
		G.sublevel = mini(G.sublevel + 6, 10)
		hub.show_page("You")
		for i in 3:
			await process_frame
		var free: int = G.attr_points_free()
		check("(points to spend: %d)" % free, free > 1)
		var first_btn := ""
		var spread_i := -1
		var plus_i := -1
		var k := 0
		for b in hub.pages["You"].find_children("*", "Button", true, false):
			var t := str((b as Button).text)
			if t.begins_with("Spread them evenly") and spread_i < 0:
				spread_i = k
			if t == "+1" and plus_i < 0:
				plus_i = k
			k += 1
		check("Spread them evenly comes before the +1 buttons", spread_i >= 0 and plus_i >= 0 and spread_i < plus_i, "%d %d" % [spread_i, plus_i])
		if spread_i >= 0:
			(hub.pages["You"].find_children("*", "Button", true, false)[spread_i] as Button).pressed.emit()
			await process_frame
			check("...and spends them all", G.attr_points_free() == 0)
	print("round200_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
