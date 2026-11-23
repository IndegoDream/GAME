extends SceneTree
## 2026-11-06 -- the solo world, grown (Robert: "is our world too small for solo play ... do all the other stuff
## suggested for solo play and all the things i requested prior"). Proves:
##   the Lands ~3x the ground, with groves and caves and their caches; a road between every two linked Lands, each
##   with its waystation keeper (who trades) and warden, both ends' foes, the far gate reachable, and the way back
##   landing on the road; roaming merchants and elites spawn as events; the middle floors grew; the Common City
##   (every keeper reachable, a waystone, the road from Eliet both ways); the auction house can't be farmed; and
##   your own world opens at Worldkeeper, builds, redraws and pays a capped tithe.
##   godot --headless --path . --script res://tools/solo_world_check.gd
var passed := 0
var failed := 0
var G


func check(n: String, ok: bool, d: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))


func _walkable_area(lv) -> int:
	var n := 0
	for row in lv.def.get("map", []):
		for ch in str(row):
			if lv.is_walkable_char(ch):
				n += 1
	return n


func _reach(lv, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q := [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			var ch: String = lv.char_at(n)
			if ch == "" or ch == " ":
				continue
			if lv.is_walkable_char(ch) or lv.def.get("exits", {}).has(ch) or lv.def.get("npcs", {}).has(ch) or lv.def.get("chests", {}).has(ch) or lv.def.get("lore", {}).has(ch) or ch in ["f", "Z", "E", "C", "K"]:
				seen[n] = true
				if lv.is_walkable_char(ch):
					q.append(n)
	return seen


func _build(id: String):
	var lv = load("res://scripts/world/Level.gd").new()
	lv.build(G.load_level_def(id))
	root.add_child(lv)
	print("  built ", id, " ", lv.height, " rows")
	return lv


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://sw_save.json"; G.save_base = "user://sw_slots"; G.playlog_path = "user://sw.jsonl"
	G.new_game()
	await process_frame
	var F = G.FrontierGen
	var regs: Dictionary = F.data().get("regions", {})
	var lands := ["whisperwood", "mistfen", "bonefields", "jadehill", "sunken_mere", "stormcliffs", "emberwaste", "frostmere", "sandglass", "blighted_wood"]
	var roads := []
	for rid in regs:
		if bool(regs[rid].get("road", false)):
			roads.append(str(rid))
	check("eight roads between the Lands", roads.size() == 8, str(roads.size()))
	# ---- the Lands: grown, with sub-areas and their caches
	for rid in lands:
		var r: Dictionary = regs[rid]
		check("%s is ~3x the ground (%dx%d)" % [rid, int(r["w"]), int(r["h"])], int(r["w"]) * int(r["h"]) >= 140 * 112 * 2.8)
		var d: Dictionary = G.load_level_def("frontier:" + rid)
		var m: Array = d.get("map", [])
		var walk := 0
		for row in m:
			for ch in str(row):
				if ch in [".", ",", "h", "o", "^", "b", "L"]:
					walk += 1
		check("%s: open ground over 30,000 cells (%d)" % [rid, walk], walk > 30000, str(walk))
		check("%s keeps more caches (%d)" % [rid, (d.get("chests", {}) as Dictionary).size()], (d.get("chests", {}) as Dictionary).size() >= 4)
	# ---- one Land built for real: every exit and person reachable from the arrival
	var lvw = _build("frontier:whisperwood")
	var arrive: Vector2i = lvw.spawns.get("P", lvw.spawns.get("<", [Vector2i.ZERO]))[0]
	var seen := _reach(lvw, arrive)
	for ch in lvw.def.get("exits", {}):
		var cells: Array = lvw.spawns.get(str(ch), [])
		check("Whisperwood: exit '%s' (%s) can be walked to" % [ch, lvw.def["exits"][ch].get("label", "")], not cells.is_empty() and seen.has(cells[0]))
	check("Whisperwood is wider than a 30-second sprint now", _walkable_area(lvw) > 30000, str(_walkable_area(lvw)))
	lvw.queue_free()
	await process_frame
	# ---- the roads: wiring both ways, a keeper who trades, a warden, the far gate reachable
	for rid in roads:
		var r: Dictionary = regs[rid]
		var a := str(r["gate_from"])
		var b := ""
		for eg in (F.data()["extra_gates"].get(rid, []) as Array):
			b = str(eg["to"])
		check("%s leads from %s to %s" % [rid, a, b], a in lands and b in lands)
		var a_opens := false
		for eg in (F.data()["extra_gates"].get(a, []) as Array):
			if str(eg["to"]) == rid:
				a_opens = true
		check("%s's gate opens onto the road" % a, a_opens)
		check("%s's way back lands on the road's far gate" % b, str(regs[b].get("gate_from", "")) == rid and str(regs[b].get("gate_back", "")) == "1")
		var roles := []
		for n in r.get("npcs", []):
			roles.append(str(n.get("role", "")))
		check("%s has a waystation keeper who trades and a warden" % rid, "merchant" in roles and "villager" in roles)
		check("%s is at least as deep as its near end" % rid, int(r["depth"]) >= int(regs[a]["depth"]))
	var lvr = _build("frontier:" + roads[0])
	var ar: Vector2i = lvr.spawns.get("P", lvr.spawns.get("<", [Vector2i.ZERO]))[0]
	var sr := _reach(lvr, ar)
	var far: Array = lvr.spawns.get("1", [])
	check("%s: the far gate can be walked to" % roads[0], not far.is_empty() and sr.has(far[0]))
	var keeper_found := false
	for ch in lvr.def.get("npcs", {}):
		if str(lvr.def["npcs"][ch].get("role", "")) == "merchant" and not lvr.spawns.get(str(ch), []).is_empty() and sr.has(lvr.spawns[str(ch)][0]):
			keeper_found = true
	check("%s: the waystation keeper stands where you can reach" % roads[0], keeper_found)
	lvr.queue_free()
	await process_frame
	# ---- the demo still stops at the Lands (and their roads)
	var st = G.store
	var was: String = st.backend
	st.backend = "demo"
	var owned: Dictionary = st.owned
	st.owned = {}
	var leak := []
	for rid in roads:
		if st.travel_check("frontier:" + rid) != "locked":
			leak.append(rid)
	check("the demo stops at every road", leak.is_empty(), str(leak))
	st.backend = was
	st.owned = owned
	# ---- roaming: merchant and elite events spawn
	var lv2 = load("res://scripts/world/Level.gd").new()
	var d2: Dictionary = G.load_level_def("frontier:mistfen")
	lv2.build(d2)
	root.add_child(lv2)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stock: Array = lv2._cart_stock(rng)
	check("a travelling merchant carries six things", stock.size() == 6, str(stock))
	check("...never one-of-a-kind, never a clue, never gear", stock.all(func(s): return not G.is_treasure(s) and str(G.item_def(s).get("type", "")) in ["material", "consumable"]))
	lv2.event = {"id": "roaming_elite", "spawn": "elite"}
	lv2._place_round30()
	var elite = null
	for c in lv2.get_children():
		if c.has_meta("roaming_elite"):
			elite = c
	check("a roaming elite walks the Land", elite != null)
	if elite != null:
		check("...with a name and five times the life", ", " in str(elite.stats.get("name", "")) and int(elite.hp) >= 5 * int(G.enemies[str(elite.stats.get("id", elite.get("type")))].get("hp", 1)) - 1 if G.enemies.has(str(elite.get("type"))) else ", " in str(elite.stats.get("name", "")))
	lv2.event = {"id": "travelling_merchant", "spawn": "merchant"}
	lv2._place_round30()
	var cart := false
	for c in lv2.get_children():
		if c.get("role") == "merchant" and (c.get("def") as Dictionary).has("stock") and ((c.get("def") as Dictionary)["stock"] as Array).size() == 6:
			cart = true
	check("a travelling merchant's cart stops here", cart)
	lv2.queue_free()
	await process_frame
	var E: Dictionary = G.retention_data().get("events", {})
	check("events are four times as likely in the Lands", float(E.get("wild_mult", 1.0)) >= 4.0 and (E.get("list", {}) as Dictionary).has("travelling_merchant") and (E.get("list", {}) as Dictionary).has("roaming_elite"))
	# ---- the middle floors grew
	var X = load("res://scripts/world/Expanse.gd")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/floor12.json"))
	var grown: Dictionary = X.expand(raw)
	var w0 := 0
	for row in raw["map"]:
		for ch in str(row):
			if ch != " " and ch != "#": w0 += 1
	var w1 := 0
	for row in grown["map"]:
		for ch in str(row):
			if ch != " " and ch != "#": w1 += 1
	check("floor 12 grows by half again or more (%d -> %d)" % [w0, w1], w1 >= int(w0 * 1.45), "%d -> %d" % [w0, w1])
	check("floor 12 has ten or more side chambers", (grown.get("extras", []) as Array).size() >= 10, str((grown.get("extras", []) as Array).size()))
	# ---- the Common City
	check("the Common City exists", G.level_exists("city"))
	var lc = _build("city")
	var pc: Vector2i = lc.spawns["P"][0]
	var sc := _reach(lc, pc)
	for ch in lc.def.get("npcs", {}):
		var cells: Array = lc.spawns.get(str(ch), [])
		check("the city's %s (%s) can be reached" % [lc.def["npcs"][ch].get("name", ""), lc.def["npcs"][ch].get("role", "")], not cells.is_empty() and sc.has(cells[0]))
	check("the city's gate home can be reached", not lc.spawns.get("E", []).is_empty() and sc.has(lc.spawns["E"][0]))
	check("the city has a waystone", lc.waystone_cell.x >= 0)
	check("the city is a real city (over 15,000 cells to walk)", _walkable_area(lc) > 15000, str(_walkable_area(lc)))
	lc.queue_free()
	await process_frame
	var vd: Dictionary = G.load_level_def("village")
	check("Eliet's east road leads to the Common City", str(vd["exits"].get("C", {}).get("to", "")) == "city")
	check("...and the city's gate leads back to it", str(G.load_level_def("city")["exits"]["E"]["to"]) == "village" and str(G.load_level_def("city")["exits"]["E"]["arrive"]) == "C")
	# ---- the auction house can't be farmed
	var A = G.sys("auction")
	check("the auction system exists", A != null)
	A.reset()
	G.gold = 100000
	var mk: Array = A.market()
	check("the house has lots today (%d)" % mk.size(), mk.size() >= 8)
	var under := []
	for lot in mk:
		if int(lot["each"]) <= G.sell_price(str(lot["item"])):
			under.append(str(lot["item"]))
	check("nothing at the house is cheaper than a trader pays for it", under.is_empty(), str(under))
	var bres: String = A.buy(0)
	var bitem := str(mk[0]["item"])
	check("buying a lot", G.count(bitem) >= int(mk[0]["n"]), bres)
	check("the same lot can't be bought twice", A.buy(0).contains("got there first"))
	check("what you bought here can't be listed again", A.listable(bitem) != "" and A.free_to_list(bitem) == 0, A.listable(bitem))
	var held_b: int = G.count(bitem)
	G.remove_item(bitem, held_b)                      # sold to a trader / used up
	check("the bought-here mark leaves with the pieces", not A.bought.has(bitem), str(A.bought))
	G.add_item(bitem, 1, false)                       # a fresh one found later
	check("once the bought pieces are gone, a new find can be listed", A.free_to_list(bitem) == G.count(bitem) - G.equipped_count(bitem), "free %d held %d" % [A.free_to_list(bitem), G.count(bitem)])
	G.add_item("iron_ore", 20, false)
	var lres: String = A.list_item("iron_ore", 20, "fair")
	check("listing your own goods", A.lots.size() == 1, lres)
	check("the heirloom and quest things can't go up", A.listable("gold") != "")
	A.lots[0]["listed_at"] = Time.get_unix_time_from_system() - 3600.0 * 30.0          # a long while ago
	var sold: int = A.settle()
	check("buyers came while you were away", sold == 1 and A.proceeds > 0)
	check("the house keeps its fee", A.proceeds < A.price_for("iron_ore", "fair", 20))
	var g0: int = G.gold
	A.collect()
	check("collecting at the counter pays you", G.gold > g0 and A.proceeds == 0)
	A.sold_today = {"day": G.today(), "n": 10}
	G.add_item("bone_shard", 5, false)
	A.list_item("bone_shard", 5, "quick")
	A.lots[0]["listed_at"] = 0.0
	check("no more than ten of your lots sell in a day", A.settle() == 0)
	var stA: Dictionary = A.save_state()
	A.reset()
	A.load_state(stA)
	check("the house's book survives a save", A.lots.size() == 1)
	# ---- your own world
	var K = G.sys("worldkeeper")
	check("the worldkeeper system exists", K != null)
	G.realm = 3
	check("closed before Worldkeeper", not K.unlocked() and not G.level_exists("realm:own"))
	if G.titles is Array:
		G.titles.append("Worldkeeper")
	else:
		G.titles["Worldkeeper"] = true
	G.realm = 10
	check("open at Worldkeeper", K.unlocked() and G.level_exists("realm:own"))
	K.tick(0.1)
	check("its door opens on the waystones", G.sys("travel").stones.has("realm:own"))
	check("four plots at the start of it", K.plot_count() >= 4)
	G.gold = 99999
	var kb: String = K.build(0, "house")
	check("building a house", str(K.plots.get("0", "")) == "house", kb)
	K.build(1, "pond")
	K.build(2, "garden")
	var kd: Dictionary = G.load_level_def("realm:own")
	var has_h := false
	var has_w := false
	for row in kd["map"]:
		if "H" in str(row): has_h = true
		if "~" in str(row): has_w = true
	check("what you built is drawn", has_h and has_w)
	var lk = _build("realm:own")
	var pk: Vector2i = lk.spawns["P"][0]
	var sk := _reach(lk, pk)
	check("the keeper's lectern can be reached", not lk.spawns.get("K", []).is_empty() and sk.has(lk.spawns["K"][0]))
	check("the way home can be reached", not lk.spawns.get("E", []).is_empty() and sk.has(lk.spawns["E"][0]))
	lk.queue_free()
	await process_frame
	check("a plot not yet open can't be built", K.build(11, "house") != "" and not K.plots.has("11"))
	G.realm = 17
	check("more plots open as you climb", K.plot_count() == 12)
	K.last_tithe = 0.0
	var tp: Dictionary = K.tithe_preview()
	check("a day's tithe from a house and a garden", int(tp.get("gold", 0)) > 0 and int(tp.get("spirit_herb", 0)) > 0)
	K.collect_tithe()
	var tp2: Dictionary = K.tithe_preview()
	check("nothing more until it has grown again", int(tp2.get("gold", 0)) == 0)
	K.last_tithe = Time.get_unix_time_from_system() - 86400.0 * 9.0
	check("a long absence is still only a day's worth", int(K.tithe_preview().get("gold", 0)) == int(tp.get("gold", 0)))
	print("SOLO WORLD CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
