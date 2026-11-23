extends SceneTree
## round 198: Robert's 2026-11-09 play. "Use all" on 999 pills froze the game for 10-20 s (4 ms a pill: the effect list
## rebuilt for every pill, the play log opened for every pill, the quest book walked for every event), the bag took
## 160 ms to redraw on every tap, and 89 idle foes slid in place every tick. All the same answers, much less work.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _state(G) -> String:
	return JSON.stringify([snappedf(G.qi, 0.001), G.realm, G.sublevel, G.affinity, G.count("mirror_pill_f25"), G.hp, G.flags.keys().size()])


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://p198_save.json"
	G.save_base = "user://p198_slots"
	G.playlog_path = "user://p198_playlog.jsonl"
	if FileAccess.file_exists(G.playlog_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(G.playlog_path))
	G.new_game()
	for e in G.affinity:
		G.affinity[e] = 30.0                  # (below the top, so every pill moves an element)
	G.add_item("mirror_pill_f25", 60, false)
	G.save_game()
	# ---- 1. Use all == the same pills one by one
	var a0 := Time.get_ticks_usec()
	for i in 60:
		G.use_item("mirror_pill_f25")
	var one_ms := (Time.get_ticks_usec() - a0) / 1000.0
	var one := _state(G)
	check("(the pills did something)", G.count("mirror_pill_f25") == 0 and G.affinity["water"] > 30.0, one)
	G.load_game()
	check("(the save came back)", G.count("mirror_pill_f25") == 60 and is_equal_approx(G.affinity["water"], 30.0), _state(G))
	var lines0 := FileAccess.get_file_as_string(G.playlog_path).count("\"use_item\"")
	var used: int = G.use_many("mirror_pill_f25")
	var many := _state(G)
	check("Use all takes all 60", used == 60)
	check("...and ends exactly where 60 single uses do (qi, realm, step, elements, HP)", many == one, many + "  vs  " + one)
	var lines1 := FileAccess.get_file_as_string(G.playlog_path).count("\"use_item\"")
	check("the play log still has one line a pill", lines1 - lines0 == 60, "%d" % (lines1 - lines0))
	check("...written once the batch is done (nothing held back after)", G._log_hold == 0 and G._log_buf.is_empty())
	check("the effect list isn't held after", G._fx_hold == 0)
	# ---- 2. the held list can't go stale
	var sg0: String = G._fx_signature()
	G.affinity["fire"] = float(G.affinity["fire"]) + 1.0
	check("an element's attunement is part of the effect list's signature", G._fx_signature() != sg0)
	var sg1: String = G._fx_signature()
	G._fx_bump += 1
	check("...and so is the bump a cleansing pill gives", G._fx_signature() != sg1)
	var cl := ""
	for id in G.items:
		var d: Dictionary = G.items[id]
		if str(d.get("type", "")) == "consumable" and d.has("cleanse"):
			cl = str(id)
			break
	if cl != "" and G.sys("cleansing") != null:
		G.add_item(cl, 1, false)
		var b0: int = G._fx_bump
		G.use_item(cl)
		check("a cleansing pill bumps the effect list (%s)" % cl, G._fx_bump == b0 + 1)
	# ---- 3. the log hold nests and keeps order
	var before := FileAccess.get_file_as_string(G.playlog_path).count("\n")
	G.log_hold(true)
	G.log_event("p198_a", {})
	G.log_hold(true)
	G.log_event("p198_b", {})
	G.log_hold(false)
	check("a nested hold keeps its lines until the outer one ends", FileAccess.get_file_as_string(G.playlog_path).count("\n") == before)
	G.log_hold(false)
	var txt := FileAccess.get_file_as_string(G.playlog_path)
	check("...then writes them, in order", txt.count("\n") == before + 2 and txt.find("p198_a") < txt.find("p198_b") and txt.find("p198_a") >= 0)
	G.log_hold(false)
	check("an extra release does no harm", G._log_hold == 0)
	# ---- 4. speed: a pill in a batch costs far less than a pill on its own
	G.add_item("mirror_pill_f25", 300, false)
	var t0 := Time.get_ticks_usec()
	G.use_many("mirror_pill_f25", 300)
	var many_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check("Use all on 300 pills: under half the time a pill takes alone (%.2f vs %.2f ms a pill)" % [many_ms / 300.0, one_ms / 60.0], many_ms / 300.0 < 0.5 * one_ms / 60.0)
	# ---- 5. the quest book's index answers what the walk answered
	var Q = G.sys("quests")
	var all_ok := true
	var bad := ""
	for q in Q.all():
		var id := str(q.get("id", ""))
		var slow := {}
		for q2 in Q.all():
			if str(q2.get("id", "")) == id:
				slow = q2
				break
		if not is_same(Q.qdef(id), slow):
			all_ok = false
			bad = id
			break
	check("qdef finds the same quest the old walk did, for every quest (%d)" % Q.all().size(), all_ok, bad)
	check("...and nothing for an unknown id", Q.qdef("p198_no_such_quest").is_empty())
	Q.legacy_defs["p198_legacy"] = {"id": "p198_legacy", "name": "x", "stages": []}
	check("...and a line an inheritance opens", str(Q.qdef("p198_legacy").get("name", "")) == "x")
	Q.legacy_defs.erase("p198_legacy")
	var base: Array = Q.data.get("quests", [])
	base.append({"id": "p198_added", "name": "late"})
	check("...and one added to the book later", str(Q.qdef("p198_added").get("name", "")) == "late")
	base.pop_back()
	check("...and forgets it when it goes", Q.qdef("p198_added").is_empty())
	var t1 := Time.get_ticks_usec()
	for i in 200:
		G.log_event("p198_tick", {})
	var ev_ms := (Time.get_ticks_usec() - t1) / 1000.0 / 200.0
	check("a logged event costs well under half a millisecond (%.3f ms)" % ev_ms, ev_ms < 0.5)
	# ---- 6. the bag: the slot grid is kept and re-dressed
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 6:
		await process_frame
	for id in ["qi_pill", "iron_sword", "copper_ore", "moonpetal_tonic"]:
		if G.has_item_def(id):
			G.add_item(id, 3, false)
	G.counters["bag_view"] = 0.0
	hud._hub.show_page("Pack")
	for i in 3:
		await process_frame
	var K = hud._kit
	K.bag_filter = "All"
	K._refresh_now()
	var g1 = K._grid
	check("the bag has a slot grid", g1 != null and is_instance_valid(g1) and g1.get_parent() == K.pack_body)
	var slot_ids := []
	for c in g1.get_children():
		if c is Button:
			slot_ids.append(str(c.get_meta("id", "")))
	var shown := 0
	for id in G.inventory:
		if not G.is_treasure(id) and G.count(id) > 0:
			shown += 1
	check("one slot an item (%d)" % shown, slot_ids.size() == shown, "%d slots" % slot_ids.size())
	K._refresh_now()
	check("a redraw keeps the same grid", is_same(K._grid, g1))
	var first_id := str(slot_ids[0]) if slot_ids.size() > 0 else ""
	(g1.get_child(0) as Button).pressed.emit()
	for i in 2:
		await process_frame
	check("tapping a re-dressed slot picks its item", K.bag_sel == first_id and first_id != "", "%s vs %s" % [K.bag_sel, first_id])
	var nl := (g1.get_child(0) as Button).get_node("N") as Label
	check("...its count is shown", (G.count(first_id) > 1) == nl.visible and (not nl.visible or nl.text == str(G.count(first_id))))
	var reused := []
	for c in g1.get_children():
		if c is Button:
			reused.append(str(c.get_meta("id", "")))
	K._drop_grid()
	K._refresh_now()
	var fresh := []
	for c in K._grid.get_children():
		if c is Button:
			fresh.append(str(c.get_meta("id", "")))
	check("the re-dressed slots are in the order a fresh grid has", reused == fresh and fresh.size() == shown, "%d vs %d" % [reused.size(), fresh.size()])
	g1 = K._grid
	G.add_item("qi_pill", 1, false)
	K._refresh_now()
	var found := false
	for c in g1.get_children():
		if c is Button and str(c.get_meta("id", "")) == "qi_pill":
			found = (c.get_node("N") as Label).text == str(G.count("qi_pill"))
	check("a count that changed is redrawn", found)
	K._set_filter("Consumables")
	K._refresh_now()
	var cons := 0
	for c in K._grid.get_children():
		if c is Button:
			cons += 1
			if str(G.item_def(str(c.get_meta("id", ""))).get("type", "")) != "consumable":
				cons = -999
	check("a filter shows only its kind", cons > 0, str(cons))
	K._set_view("list")
	K._refresh_now()
	check("the list view lets the grid go", K._grid == null)
	K._set_view("grid")
	K._set_filter("All")
	K._refresh_now()
	check("...and the slots come back", K._grid != null and is_instance_valid(K._grid) and K._grid.get_child_count() >= shown)
	# ---- 7. the player's look catches up once a frame
	hud.queue_free()
	await process_frame
	load("res://Main.gd").force_veil = true
	root.add_child(load("res://Main.tscn").instantiate())
	for i in 4:
		await process_frame
	G.go_to("village", "<")
	var pl = null
	for i in 300:
		await process_frame
		pl = get_first_node_in_group("player")
		if pl != null and get_first_node_in_group("level") != null:
			break
	check("(the player is up)", pl != null)
	if pl != null:
		pl._dressed_as = ""
		for i in 20:
			G.stats_changed.emit()
		check("twenty changes in a frame: the look waits for the next frame", pl._dressed_as == "" and pl._look_due)
		await process_frame
		check("...then catches up, once", pl._dressed_as != "" and not pl._look_due)
	# ---- 8. a foe at rest checks its footing now and then, and moves at once when it must
	G.go_to("floor3", "<")
	var foe = null
	for i in 600:
		await process_frame
		var lv = get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == "floor3" and lv.stream_left() == 0 and i > 60:
			for e in get_nodes_in_group("enemy"):
				if not e._chasing and not e._dead:
					foe = e
					break
			break
	check("(a foe to watch)", foe != null, "level=%s foes=%d" % [str(get_first_node_in_group("level").level_id) if get_first_node_in_group("level") else "-", get_nodes_in_group("enemy").size()])
	if foe != null:
		for i in 30:
			await physics_frame
		var p0: Vector3 = foe.global_position
		check("an idle foe stays on its feet", foe.is_on_floor() and foe.global_position.distance_to(p0) < 0.05)
		foe._rest_t = 1.0
		foe.velocity = Vector3(3.0, 0.0, 0.0)
		foe._rest_slide(1.0 / 60.0)
		check("...and given a push it slides at once", foe.global_position.distance_to(p0) > 0.01 and foe._rest_t == 0.0, str(foe.global_position - p0))
	print("perf198_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
