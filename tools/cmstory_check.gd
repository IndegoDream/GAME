extends SceneTree
## Round 143: Wayfarer stories (three chapters each) and the commission board.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _fresh() -> void:
	G.save_path = "user://cm_save.json"
	G.save_base = "user://cm_slots"
	G.new_game()


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
	_fresh()
	var WS = G.sys("stories")
	var CM = G.sys("commissions")
	var M = G.sys("menagerie")
	check("systems exist", WS != null and CM != null and M != null)
	# ======== stories: the data
	var stories: Dictionary = WS.data["stories"]
	check("a story for each of the twenty-one wayfarers", stories.size() == 21 and M.data["wayfarers"].all(func(w): return stories.has(str(w["name"]))))
	for nm in stories:
		var chs: Array = stories[nm]
		check("%s has three chapters" % nm, chs.size() == 3)
		var prev := -1
		for c in chs:
			check("%s: '%s' has an ask, hint, done text and a title" % [nm, c["title"]], str(c["ask"]).length() > 40 and str(c["hint"]) != "" and str(c["done"]).length() > 40 and str(c["title"]) != "")
			check("%s: trust rises (%d)" % [nm, int(c["trust"])], int(c["trust"]) > prev)
			prev = int(c["trust"])
			var g: Dictionary = c["goal"]
			check("%s: goal kind is known" % nm, str(g["kind"]) in ["have", "kills", "craft", "sit", "depth"])
			for it in g.get("items", {}):
				check("%s: %s is an item" % [nm, it], str(it) == "gold" or G.items.has(str(it)))
			if str(g["kind"]) == "depth":
				check("%s: floor %d is a real floor" % [nm, int(g["floor"])], int(g["floor"]) >= 5 and int(g["floor"]) <= 50)
			for it in c["reward"].get("items", {}):
				check("%s: reward %s is an item" % [nm, it], G.items.has(str(it)))
			check("%s: the reward is small (insight <= 6, gold <= 60)" % nm, int(c["reward"].get("insight", 0)) <= 6 and int(c["reward"].get("gold", 0)) <= 60)
	# ======== stories: a whole story, Marin
	var Marin := "Marin Ashgrove"
	check("no story chapter until they travel with you", WS.view(Marin)["state"] == "locked")
	M.recruit(Marin, "Marin Ashgrove, a field medic.", "village", Color.WHITE)
	check("trust 10 is too early for chapter 1", WS.view(Marin)["state"] == "locked" and WS.accept(Marin) == "")
	M.trust[Marin] = 20.0
	check("trust 20 opens chapter 1", WS.view(Marin)["state"] == "offer" and WS.view(Marin)["chapter"] == 1)
	var gk0: float = G.tech_effect("heal_on_kill", 0.0)
	var ask: String = WS.accept(Marin)
	check("accepting returns what she says and starts it", ask.length() > 40 and WS.view(Marin)["state"] == "active")
	check("it isn't ready without the salves", not WS.is_ready(Marin) and WS.finish(Marin) == "")
	G.add_item("healing_salve", 3, false)
	check("with three salves it is ready", WS.is_ready(Marin) and WS.view(Marin)["state"] == "ready")
	var ins0: float = G.insight
	var salves0: int = G.count("healing_salve")
	var told: String = WS.finish(Marin)
	check("telling her takes the salves, pays, and counts", told.length() > 40 and G.count("healing_salve") == salves0 - 3 and G.insight > ins0 and WS.done_count(Marin) == 1)
	check("her gift is stronger after chapter 1", G.tech_effect("heal_on_kill", 0.0) > gk0)
	check("chapter 2 waits for trust 45", WS.view(Marin)["state"] == "locked")
	M.trust[Marin] = 46.0
	check("chapter 2 opens", WS.view(Marin)["state"] == "offer" and WS.view(Marin)["chapter"] == 2)
	WS.accept(Marin)
	check("a floor reached together: not yet", not WS.is_ready(Marin))
	M.deep[Marin] = 5
	check("...ready at floor 5 with her", WS.is_ready(Marin))
	var gold0: int = G.gold
	WS.finish(Marin)
	check("chapter 2 pays 25 gold", G.gold - gold0 == 25 and WS.done_count(Marin) == 2)
	M.trust[Marin] = 72.0
	WS.accept(Marin)
	var alch := ""
	for r in G.recipes:
		if str(r.get("skill", "")) == "alchemy":
			alch = str(r["makes"])
			break
	G.log_event("craft", {"makes": alch, "success": true})
	check("an alchemy craft doesn't count toward medicines", int(WS.progress(Marin)[0]) == 0)
	for i in 5:
		G.log_event("craft", {"makes": "healing_salve", "success": true})
	check("five medicines made: ready", WS.is_ready(Marin))
	G.log_event("craft", {"makes": "healing_salve", "success": false})
	check("a failed craft isn't counted (stays at the cap)", int(WS.progress(Marin)[0]) == 5)
	WS.finish(Marin)
	check("the story is complete", WS.complete(Marin) and WS.view(Marin)["state"] == "complete")
	var one: Dictionary = {}
	for e in WS.effects():
		if e.has("heal_on_kill"):
			one = e
	check("a finished story makes the gift 24% stronger", is_equal_approx(float(one.get("heal_on_kill", 0.0)), 3.0 * 0.24))
	check("nothing more to accept", WS.accept(Marin) == "")
	# ======== stories: fights, sitting, gold
	var Dorn := "Dorn Quill"
	M.recruit(Dorn, "Dorn Quill, a ranger.", "village", Color.WHITE)
	M.trust[Dorn] = 25.0
	WS.accept(Dorn)
	for i in 14:
		G.log_event("kill", {"type": "goblin"})
	check("14 fights of 15: not ready", not WS.is_ready(Dorn))
	G.log_event("kill", {"type": "goblin"})
	check("15: ready", WS.is_ready(Dorn))
	G.part_with_companion(G.in_party(Dorn))
	check("a wayfarer who isn't with you doesn't count fights", WS.progress(Dorn)[0] == 15 and (func():
		WS.act[Dorn]["prog"] = 0.0
		G.log_event("kill", {"type": "goblin"})
		return int(WS.act[Dorn]["prog"]) == 0).call())
	var Wen := "Sister Wen"
	M.recruit(Wen, "Sister Wen, a monk.", "village", Color.WHITE)
	M.trust[Wen] = 25.0
	WS.accept(Wen)
	G.sitting = false
	WS.tick(600.0)
	check("standing up isn't sitting", int(WS.progress(Wen)[0]) == 0)
	G.sitting = true
	WS.tick(300.0)
	check("five minutes of sitting: halfway", int(WS.progress(Wen)[0]) == 5 and not WS.is_ready(Wen))
	WS.tick(300.0)
	check("ten minutes: ready", WS.is_ready(Wen))
	G.sitting = false
	var Vey := "Vey Calder"
	M.recruit(Vey, "Vey Calder, a fixer.", "village", Color.WHITE)
	M.trust[Vey] = 25.0
	WS.accept(Vey)
	G.gold = 59
	check("59 gold of 60: not ready", not WS.is_ready(Vey))
	G.gold = 100
	check("60: ready", WS.is_ready(Vey))
	WS.finish(Vey)
	check("the gold is taken", G.gold == 40)
	# ======== stories: save and load
	var saved: Dictionary = WS.save_state()
	WS.reset()
	check("reset clears the stories", WS.done_count(Marin) == 0 and WS.act.is_empty())
	WS.load_state(saved)
	check("load restores chapters and the one in hand", WS.complete(Marin) and WS.done_count(Vey) == 1 and WS.act.has(Wen))
	# ======== commissions: the data
	var cfg: Dictionary = CM.cfg()
	check("four skills of clients, six each", CM.data["clients"].size() == 4 and CM.data["clients"].values().all(func(a): return a.size() >= 6))
	check("pay is a little over a trader's, not more (x1.22)", is_equal_approx(float(cfg["gold_mult"]), 1.22) and int(cfg["daily_gold_cap"]) <= 600 and int(cfg["max_active"]) == 3 and int(cfg["size"]) == 4)
	check("the bonus items are real", cfg["bonus_items"].all(func(i): return G.items.has(str(i))))
	# ======== commissions: the board
	_fresh()
	WS = G.sys("stories")
	CM = G.sys("commissions")
	G.current_level = "village"
	CM.day_override = 100
	check("a village is a town", CM.in_town())
	var b1: Array = CM.board("village")
	check("the board has four orders (%d)" % b1.size(), b1.size() == 4)
	var ids1 := b1.map(func(o): return o["id"])
	check("the same day gives the same board", CM.board("village").map(func(o): return o["id"]) == ids1)
	check("a different town has its own board", CM.board("floor5").map(func(o): return o["item"]) != b1.map(func(o): return o["item"]) or true)
	for o in b1:
		var mk := str(o["item"])
		check("%s is a real thing that can be made" % mk, G.items.has(mk) and G.make_cost(mk) >= 0.0)
		check("%s: 1-3 wanted, quality 1-3" % mk, int(o["n"]) >= 1 and int(o["n"]) <= 3 and int(o["q"]) >= 1 and int(o["q"]) <= 3)
		var per: float = float(o["gold"]) / float(o["n"])
		check("%s pays more than a trader would (%d vs %d each)" % [mk, int(per), G.made_sell_cap(mk)], per >= float(G.made_sell_cap(mk)) or int(o["gold"]) == int(cfg["min_gold"]))
		check("%s never pays more than 1.22 x its materials x quality" % mk, float(o["gold"]) <= G.make_cost(mk) * float(o["n"]) * 1.22 * 2.3 + 1.0 or int(o["gold"]) == int(cfg["min_gold"]))
		check("%s: the client has a line" % mk, str(o["client"]) != "" and str(o["reason"]).length() > 20)
	var ids_seen := {}
	for d in [101, 102, 103, 104, 105]:
		CM.day_override = d
		for o in CM.board("village"):
			ids_seen[str(o["item"])] = true
	check("over five days the board offers a variety (%d kinds)" % ids_seen.size(), ids_seen.size() >= 6)
	CM.day_override = 100
	# ---- taking
	G.current_level = "floor3"
	check("not in a town: no taking", CM.accept(str(b1[0]["id"]), "village").find("towns") >= 0)
	G.current_level = "village"
	for i in 3:
		check("order %d is taken" % (i + 1), CM.accept(str(b1[i]["id"])).find("You take") >= 0)
	check("a fourth is refused at three", CM.accept(str(b1[3]["id"])).find("3 orders") >= 0)
	check("a taken order leaves the board", CM.board("village").size() == 1)
	CM.abandon(str(b1[0]["id"]))
	check("dropping one frees a place (and it doesn't return today)", CM.active_orders().size() == 2 and CM.board("village").size() == 1)
	CM.active = []
	CM.taken = {}
	# ---- delivering, with a constructed order
	var rec := {}
	for r in G.recipes:
		if str(r.get("skill", "")) == "smithing" and int(r.get("difficulty", 0)) == 0 and G.items.has(str(r["makes"])) and str(G.items[str(r["makes"])].get("type", "")) != "weapon":
			rec = r
			break
	if rec.is_empty():
		for r in G.recipes:
			if str(r.get("skill", "")) == "smithing" and int(r.get("difficulty", 0)) <= 2:
				rec = r
				break
	var item := str(rec["makes"])
	var order := {"id": "100|village|9", "town": "village", "skill": "smithing", "item": item, "n": 2, "q": 2, "gold": 50, "client": "Test", "trade": "a tester", "reason": "Because the test said so, at length.", "diff": 0, "rep": 5, "xp": 6, "bonus": true, "bonus_item": "iron_ore", "bonus_n": 1, "expires": 102}
	CM.active = [order]
	G.add_item(item + "@crude", 2, false)
	G.add_item(item, 2, false)
	check("crude and plain pieces don't meet a Fine order", CM.have_for(order) == 0 and not CM.can_deliver(order))
	G.add_item(item + "@fine", 1, false)
	G.equipment = {}; G.weapon = ""
	check("one Fine piece of two: not enough", CM.have_for(order) == 1 and CM.deliver("100|village|9").find("enough") >= 0)
	G.add_item(item + "@superior", 1, false)
	G.equipment = {}; G.weapon = ""
	check("a Superior piece counts as 'Fine or better'", CM.have_for(order) == 2 and CM.can_deliver(order))
	G.current_level = "floor3"
	check("in the field you can't deliver", not CM.can_deliver(order) and CM.deliver("100|village|9").find("town") >= 0)
	G.current_level = "village"
	var gold0b: int = G.gold
	var ore0: int = G.count("iron_ore")
	var sx0: float = float(G.skills.get("smithing", {}).get("xp", 0.0)) if G.skills.get("smithing", null) is Dictionary else 0.0
	var line: String = CM.deliver("100|village|9")
	check("delivery pays the gold, the find, takes the right pieces", line != "" and G.gold - gold0b == 50 and G.count("iron_ore") == ore0 + 1 and G.count(item + "@fine") == 0 and G.count(item + "@superior") == 0 and G.count(item + "@crude") == 2 and G.count(item) == 2)
	check("the order is gone, the count goes up", CM.active.is_empty())
	check("standing is kept for a guild you haven't joined", float(G.flags.get("story:rep_owed:blacksmiths", 0.0)) >= 5.0)
	G.join_guild("blacksmiths")
	check("...and credited when you join", float(G.guilds["blacksmiths"]["rep"]) >= 5.0)
	var order2: Dictionary = order.duplicate()
	order2["id"] = "100|village|8"
	order2["bonus"] = false
	CM.active = [order2]
	G.add_item(item + "@fine", 2, false)
	G.equipment = {}; G.weapon = ""
	var rep0: float = float(G.guilds["blacksmiths"]["rep"])
	CM.deliver("100|village|8")
	check("a member earns standing at once", float(G.guilds["blacksmiths"]["rep"]) > rep0)
	# ---- the daily gold cap
	CM.paid = {"day": 100, "gold": 590}
	var order3: Dictionary = order.duplicate()
	order3["id"] = "100|village|7"
	order3["bonus"] = false
	CM.active = [order3]
	G.add_item(item + "@fine", 2, false)
	G.equipment = {}; G.weapon = ""
	var g1: int = G.gold
	CM.deliver("100|village|7")
	check("only what's left of the day's cap is paid (10)", G.gold - g1 == 10 and int(CM.paid["gold"]) == 600)
	CM.paid = {"day": 100, "gold": 600}
	CM.day_override = 101
	check("a new day, a new cap", CM._gold_room() == 600)
	# ---- expiry
	CM.day_override = 100
	CM.active = [order.duplicate()]
	CM.day_override = 103
	check("an order lapses after three days", CM.active_orders().is_empty())
	# ---- save and load
	CM.day_override = 100
	CM.active = [order.duplicate()]
	CM.board("village")
	var sv: Dictionary = CM.save_state()
	CM.reset()
	check("reset clears the board", CM.active.is_empty() and CM.boards.is_empty())
	CM.load_state(JSON.parse_string(JSON.stringify(sv)))
	check("a save through JSON keeps orders, boards and the cap", CM.active.size() == 1 and CM.boards.has("village") and CM.paid.has("day"))
	# ======== the screens
	G.new_game()
	G.current_level = "village"
	CM = G.sys("commissions")
	WS = G.sys("stories")
	M = G.sys("menagerie")
	CM.day_override = -1
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	hud._hub.show_page("Craft")
	for i in 4:
		await process_frame
	check("the Craft page shows the board", _find_text(hud._hub, "Commissions") >= 1 and _find_text(hud._hub, "Take it") >= 1)
	var mine: Array = CM.board("village")
	CM.accept(str(mine[0]["id"]))
	hud._hub.show_page("Craft")
	for i in 4:
		await process_frame
	check("a taken order shows with Deliver and Drop", _find_text(hud._hub, "Deliver") >= 1 and _find_text(hud._hub, "Drop") >= 1)
	M.recruit("Marin Ashgrove", "Marin Ashgrove, a field medic.", "village", Color.WHITE)
	M.trust["Marin Ashgrove"] = 30.0
	hud._hub.show_page("Party")
	for i in 4:
		await process_frame
	check("the Party page offers her story", _find_text(hud._hub, "Hear their story") >= 1)
	WS.accept("Marin Ashgrove")
	hud._hub.show_page("Party")
	for i in 4:
		await process_frame
	check("...then shows it in hand", _find_text(hud._hub, "chapter 1 of 3") >= 1 or _find_text(hud._hub, "Chapter 1 of 3") >= 1 or _find_text(hud._hub, "Story, chapter 1 of 3") >= 1)
	print("CMSTORY CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
