extends SceneTree
## Round 144: blessings/hardships per trip, the pedlar, the shrine, the quarry.
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
	G.save_path = "user://bo_save.json"
	G.save_base = "user://bo_slots"
	G.new_game()
	G.current_level = "village"
	var BO = G.sys("boons")
	BO.day_override = "2026-10-18"
	# ---- data
	check("12 blessings, 6 hardships, 7 shrines", BO.data["boons"].size() == 12 and BO.data["curses"].size() == 6 and BO.data["shrines"].size() == 7)
	var keys_ok := true
	for e in BO.data["boons"] + BO.data["curses"] + BO.data["shrines"]:
		if not (e.get("fx", {}) is Dictionary) or (e["fx"] as Dictionary).is_empty():
			keys_ok = false
	check("every entry has an effect", keys_ok)
	for it in BO.data["merchant_stock"]:
		check("pedlar stock %s is an item" % it, G.items.has(str(it)))
	for c in BO.data["curses"]:
		check("%s: a hardship pays something and is a real penalty" % c["id"], float(c["reward"]) > 0.0 and float(c["reward"]) <= 0.12)
	# ---- offers: three, stable for the day, different on another
	var b1: Array = BO.boon_offers()
	var c1: Array = BO.curse_offers()
	check("three blessings and three hardships", b1.size() == 3 and c1.size() == 3)
	check("the same offers all day", BO.boon_offers() == b1 and BO.curse_offers() == c1)
	var differ := false
	for d in ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22"]:
		BO.day_override = d
		if BO.boon_offers() != b1:
			differ = true
	check("other days offer other blessings", differ)
	BO.day_override = "2026-10-18"
	# ---- picking
	check("a blessing not on offer is refused", BO.pick("boon", "nonsense") == "")
	var base_dmg: float = G.tech_effect("damage_mult", 1.0)
	var base_taken: float = G.tech_effect("damage_taken", 1.0)
	var base_move: float = G.tech_effect("move_mult", 1.0)
	var bid := ""
	for id in b1:
		if BO.boon_def(str(id)).get("fx", {}).has("damage_mult") or BO.boon_def(str(id)).get("fx", {}).has("move_mult") or BO.boon_def(str(id)).get("fx", {}).has("damage_taken"):
			bid = str(id)
			break
	if bid == "":
		bid = str(b1[0])
	check("picking a blessing says so", BO.pick("boon", bid).find(str(BO.boon_def(bid)["name"])) >= 0 and BO.run["boon"] == bid)
	var fx: Dictionary = BO.boon_def(bid)["fx"]
	var k0: String = str(fx.keys()[0])
	var after: float = G.tech_effect(k0, 1.0 if not k0 in G.ADDITIVE_KEYS else 0.0)
	var before: float = {"damage_mult": base_dmg, "damage_taken": base_taken, "move_mult": base_move}.get(k0, 1.0 if not k0 in G.ADDITIVE_KEYS else 0.0)
	check("the blessing changes the number (%s)" % k0, not is_equal_approx(after, before))
	BO.pick("boon", "")
	check("putting it down clears it", BO.run["boon"] == "" and BO.effects().is_empty())
	check("a hardship pays and clears", (func():
		BO.pick("curse", str(c1[0]))
		var r1: float = BO.reward()
		var dr: float = G.diff_reward()
		BO.pick("curse", "")
		return r1 > 0.0 and dr > 1.0 and is_equal_approx(G.diff_reward(), 1.0)).call())
	# ---- online: nothing applies
	BO.pick("boon", bid)
	BO.pick("curse", str(c1[0]))
	var lv: String = G.current_level
	G.current_level = "online:gate1"
	check("online instances ignore both (server numbers)", G.OnlineGen.is_online("online:gate1") and BO.effects().is_empty() and BO.reward() == 0.0)
	G.current_level = lv
	# ---- a trip ends when you are back in a town
	BO.pick("boon", bid)
	BO._last_level = ""
	BO.tick(0.1)
	check("still in town: nothing ends", BO.run["boon"] == bid)
	G.current_level = "floor1"
	BO.tick(0.1)
	check("out on the floors: it is kept and marked", BO.run["boon"] == bid and bool(BO.run["out"]))
	check("not changeable out there", BO.pick("boon", "") .find("town") >= 0 and BO.run["boon"] == bid)
	G.current_level = "village"
	BO.tick(0.1)
	check("back in town: the trip is over", BO.run["boon"] == "" and BO.run["curse"] == "" and not bool(BO.run["out"]))
	# ---- the pedlar
	var st: Array = BO.merchant_stock()
	check("three goods, two of each", st.size() == 3 and st.all(func(s): return int(s["left"]) == 2))
	var mid := str(st[0]["id"])
	var price := int(st[0]["price"])
	check("priced at double the base value", price == int(round(float(G.items[mid]["value"]) * 2.0)))
	check("sold for much less than that (never a money loop)", G.sell_price(mid) < price)
	G.gold = price * 3
	var g0: int = G.gold
	var n0: int = G.count(mid)
	check("buying works", BO.merchant_buy(mid).find("buy") >= 0 and G.gold == g0 - price and G.count(mid) == n0 + 1)
	BO.merchant_buy(mid)
	check("only two a day", BO.merchant_buy(mid).find("no more") >= 0 and G.count(mid) == n0 + 2)
	G.gold = 0
	var other := str(st[1]["id"])
	check("not enough gold is refused", BO.merchant_buy(other).find("gold") >= 0)
	G.current_level = "floor1"
	check("only in town", BO.merchant_buy(other).find("town") >= 0)
	G.current_level = "village"
	BO.day_override = "2026-10-19"
	var st2: Array = BO.merchant_stock()
	check("a new day restocks", st2.all(func(s): return int(s["left"]) == 2))
	BO.day_override = "2026-10-18"
	# ---- the shrine
	BO.day_override = "2026-10-18"
	BO._roll_day()
	var sh: Dictionary = BO.shrine_today()
	check("a shrine today", not sh.is_empty() and BO.shrine_ready())
	var msg: String = BO.shrine_use()
	check("kneeling gives a half-hour blessing", msg.find("answers") >= 0 and G.buff_left("shrine_" + str(sh["id"])) > 1700.0)
	check("once a day", BO.shrine_use().find("already") >= 0 and not BO.shrine_ready())
	check("the shrine is the same all day", BO.shrine_today()["id"] == sh["id"])
	# ---- the quarry
	G.journal["places"] = {"floor5": true}
	BO.day_override = "2026-10-20"
	var q: Dictionary = BO.quarry()
	check("a quarry from floors you know", str(q["species"]) != "" and int(G.enemies[str(q["species"])]["floor"]) <= G.reach_depth() and int(G.enemies[str(q["species"])]["floor"]) >= 1)
	var gold0: int = G.gold
	var ins0: float = float(G.insight) if G.get("insight") != null else 0.0
	G.log_event("kill", {"type": "something_else"})
	check("other beasts don't count", BO.quarry_kills == 0)
	for i in 2:
		G.log_event("kill", {"type": str(q["species"])})
	check("two of three: not yet paid", BO.quarry_kills == 2 and not BO.quarry_paid)
	G.log_event("kill", {"type": str(q["species"])})
	check("the third pays gold once", BO.quarry_paid and G.gold - gold0 == int(q["gold"]))
	G.log_event("kill", {"type": str(q["species"])})
	check("and only once", G.gold - gold0 == int(q["gold"]))
	# ---- save/load
	var keep_id: String = str(BO.boon_offers()[0])
	BO.pick("boon", keep_id)
	var sd: Dictionary = BO.save_state()
	var js: String = JSON.stringify(sd)
	BO.reset()
	BO.load_state(JSON.parse_string(js))
	check("the pick survives save and load", BO.run["boon"] == keep_id)
	check("quarry kills and bought survive", BO.quarry_paid and BO.day == "2026-10-20")
	# ---- UI
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 10:
		await process_frame
	G.current_level = "village"
	hud._hub.show_page("Road")
	for i in 4:
		await process_frame
	check("the Road page shows Today", _find_text(hud._hub, "Today") >= 1)
	check("...the blessings", _find_text(hud._hub, BO.boon_def(str(BO.boon_offers()[0]))["name"]) >= 1)
	check("...the pedlar", _find_text(hud._hub, "is in town today") >= 1)
	check("...the shrine", _find_text(hud._hub, "The day's shrine") >= 1)
	check("...the quarry", _find_text(hud._hub, "The day's quarry") >= 1)
	print("BOONS CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
