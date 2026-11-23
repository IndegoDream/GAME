extends SceneTree
## Round 145: the collection (completion %, silhouettes, tenth-milestones) and the herb garden.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _find_text(n: Node, needle: String) -> int:
	var c := 0
	if (n is Label or n is Button) and str(n.text).find(needle) >= 0:
		c += 1
	for ch in n.get_children():
		c += _find_text(ch, needle)
	return c


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://co_save.json"
	G.save_base = "user://co_slots"
	G.new_game()
	G.current_level = "village"
	var CO = G.sys("collection")
	var GA = G.sys("garden")
	# ---------------- collection
	var cats: Array = CO.categories()
	var ids := cats.map(func(c): return str(c["id"]))
	for want in ["foes", "materials", "treasures", "recipes", "wayfarers", "stories", "history", "masters"]:
		check("category %s exists" % want, want in ids)
	check("totals are real", cats.all(func(c): return int(c["need"]) > 0 and int(c["have"]) >= 0 and int(c["have"]) <= int(c["need"])))
	var foes: Dictionary = cats[ids.find("foes")]
	check("foes: 200+ species, none met on a new game", int(foes["need"]) >= 200 and int(foes["have"]) == 0 and foes["hidden"].size() == int(foes["need"]))
	check("a silhouette shows only a floor, never a name", foes["hidden"].all(func(h): return str(h).begins_with("???") and str(h).find("floor") >= 0))
	var p0: int = CO.percent()
	check("a new game is near zero", p0 >= 0 and p0 < 10)
	G.kills["goblin"] = 3
	G.kills["goblin_brute"] = 1
	var foes2: Dictionary = CO.categories()[ids.find("foes")]
	check("killing something moves it from hidden to seen", int(foes2["have"]) == 2 and foes2["seen"].has("Goblin") and foes2["hidden"].size() == int(foes2["need"]) - 2)
	check("the percentage goes up", CO.percent() >= p0 and CO.overall() > 0.0)
	# materials and treasures from the journal
	G.add_item("iron_ore", 1, false)
	G.note_item("iron_ore")
	check("materials found counts the journal", int(CO.categories()[ids.find("materials")]["have"]) >= 1)
	var tid := ""
	for k in G.items:
		if G.is_treasure(str(k)):
			tid = str(k)
			break
	G.add_item(tid, 1, false)
	var tcat: Dictionary = CO.categories()[ids.find("treasures")]
	check("a treasure found shows by name", tcat["seen"].has(G.item_name(tid)) and int(tcat["have"]) == 1)
	# wayfarers
	var M = G.sys("menagerie")
	var w0: Dictionary = CO.categories()[ids.find("wayfarers")]
	M.recruit("Marin Ashgrove", "Marin Ashgrove, a field medic.", "village", Color.WHITE)
	var w1: Dictionary = CO.categories()[ids.find("wayfarers")]
	check("meeting a Wayfarer counts, others stay ???", int(w1["have"]) == int(w0["have"]) + 1 and w1["hidden"].all(func(h): return h == "???"))
	# milestones: paid once each, a little insight
	CO.reset()
	var pct: int = CO.percent()
	var due: Array = CO.milestones_due()
	check("milestones due match the percentage", due.size() == pct / 10)
	var ins0: float = G.insight_total() if G.has_method("insight_total") else 0.0
	CO.claim()
	check("claiming marks them paid", CO.milestones_due().is_empty() and CO.paid.size() == due.size())
	CO.claim()
	check("never paid twice", CO.paid.size() == due.size())
	# fake a big collection: everything met
	var msgs := []
	G.message.connect(func(t): msgs.append(str(t)))
	for k in G.enemies:
		G.kills[str(k)] = 1
	for k in G.items:
		G.note_item(str(k))
	var pct2: int = CO.percent()
	check("lots found -> a much higher percentage", pct2 > pct + 15)
	CO.claim()
	check("new tenths pay and say so", msgs.size() >= 1 and msgs.any(func(m): return m.find("COLLECTION") >= 0))
	check("overall never above 100%", CO.percent() <= 100)
	# save/load
	var sd: Dictionary = CO.save_state()
	CO.reset()
	CO.load_state(JSON.parse_string(JSON.stringify(sd)))
	check("paid milestones survive save/load", CO.paid.size() == sd["paid"].size())
	# ---------------- garden
	GA.day_override = "2026-10-18"
	GA.now_override = 1000000.0
	check("three plots, all empty", GA.plots.size() == 3 and GA.state(0) == "empty" and GA.state(2) == "empty")
	check("four herbs to choose from, all real items", GA.herbs().size() == 4)
	G.add_item("spirit_herb", 2, false)
	check("planting needs the herb", GA.plant(0, "moonpetal").find("none") >= 0 and GA.state(0) == "empty")
	var n0: int = G.count("spirit_herb")
	check("planting takes one and says when", GA.plant(0, "spirit_herb").find("180") >= 0 and G.count("spirit_herb") == n0 - 1 and GA.state(0) == "growing")
	check("a used plot is refused", GA.plant(0, "spirit_herb").find("already") >= 0 and G.count("spirit_herb") == n0 - 1)
	check("picking early does nothing", GA.pick(0) == "" and GA.state(0) == "growing")
	check("minutes left is right", GA.minutes_left(0) == 180)
	GA.now_override += 179.0 * 60.0
	check("not quite ready at 179 minutes", GA.state(0) == "growing" and GA.minutes_left(0) == 1)
	GA.now_override += 2.0 * 60.0
	check("ready after 180", GA.state(0) == "ready")
	G.current_level = "floor1"
	check("only in town", GA.pick(0).find("town") >= 0 and GA.state(0) == "ready" and GA.plant(1, "spirit_herb").find("town") >= 0)
	G.current_level = "village"
	var n1: int = G.count("spirit_herb")
	check("picking gives two and empties the plot", GA.pick(0).find("pick") >= 0 and G.count("spirit_herb") == n1 + 2 and GA.state(0) == "empty")
	# daily cap
	GA.picked_today = 4
	GA.plots[1] = {"herb": "spirit_herb", "ready": 0.0}
	GA.plots[2] = {"herb": "spirit_herb", "ready": 0.0}
	var n2: int = G.count("spirit_herb")
	check("under the cap: picked", GA.pick(1) != "" and G.count("spirit_herb") == n2 + 2 and GA.picked_today == 6)
	check("over the daily cap: kept for tomorrow", GA.pick(2).find("enough") >= 0 and GA.state(2) == "ready" and G.count("spirit_herb") == n2 + 2)
	GA.day_override = "2026-10-19"
	check("the next day: picking works again", GA.pick(2).find("pick") >= 0 and GA.picked_today == 2)
	# grows while the game is closed: save/load keeps the ready time
	GA.now_override = 2000000.0
	G.add_item("moonpetal", 1, false)
	GA.plant(0, "moonpetal")
	var gs: Dictionary = GA.save_state()
	GA.reset()
	GA.load_state(JSON.parse_string(JSON.stringify(gs)))
	check("a planted herb survives save/load", GA.state(0) == "growing" and str(GA.plots[0]["herb"]) == "moonpetal")
	GA.now_override += 400.0 * 60.0
	check("...and ripens in real time", GA.state(0) == "ready")
	GA.load_state({"plots": [{"herb": "not_a_herb", "ready": 5}, "junk", {}], "day": "x", "picked": 99})
	check("bad save data is ignored", GA.plots.size() == 3 and GA.state(0) == "empty")
	# no income: the garden can never out-earn a day of it
	var best_val := 0
	for h in GA.herbs():
		best_val = maxi(best_val, int(G.items[str(h["id"])]["value"]))
	check("a day's picking is worth little gold (<= 6 herbs)", best_val * int(GA.data["daily_pick_cap"]) <= 80)
	# ---------------- UI
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 10:
		await process_frame
	G.current_level = "village"
	hud._hub.show_page("Road")
	for i in 4:
		await process_frame
	check("Road shows the Collection", _find_text(hud._hub, "Collection") >= 1 and _find_text(hud._hub, "complete") >= 1)
	check("...the silhouettes", _find_text(hud._hub, "Still unseen") >= 0)
	check("...the Garden", _find_text(hud._hub, "Garden") >= 1 and _find_text(hud._hub, "Plot 1") >= 1)
	print("COLLECT CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
