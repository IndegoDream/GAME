extends SceneTree
## Round 188: guilds with a group chat, your own guild, your own sect -- and that none of it is power.
##   godot --headless --path . --script res://tools/fellowship_check.gd
var _pass := 0
var _fail := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _ticks(FS, secs: float) -> void:
	var t := 0.0
	while t < secs:
		FS.tick(0.5)
		t += 0.5


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://fellowship_check_save.json"
	G.new_game()
	G.char_name = "Rob"
	var FS = G.sys("fellowship")
	var OS_ = G.sys("own_sect")
	check("the guild system is there", FS != null)
	check("the sect system is there", OS_ != null)
	if FS == null or OS_ == null:
		_end()
		return
	for id in ["spirit_herb", "iron_ore", "bone_shard", "beast_hide", "moonpetal", "rough_jade"]:
		G.note_item(id)
	G.gold = 100000
	# ---- joining --------------------------------------------------------------------------------------------------
	check("no guild at first", not FS.in_guild())
	var msg: String = FS.join("lantern_wardens")
	check("join the Lantern Wardens", FS.in_guild() and str(FS.g["name"]) == "Lantern Wardens", msg)
	check("...six guildmates", (FS.g["members"] as Array).size() == 6)
	check("...four tasks this week", FS.tasks.size() == 4, FS.tasks.size())
	check("...the chat says so", FS.chat.size() >= 1)
	check("a second guild has to wait", FS.join_check("jade_kettle") != "")
	check("a guild adds no power (effects empty)", FS.effects().is_empty())
	# ---- the chat ------------------------------------------------------------------------------------------------
	var n0: int = FS.chat.size()
	FS.on_event("boss_kill", {"type": "goblin_king"})
	_ticks(FS, 14.0)
	var reacted := false
	for l in FS.chat.slice(n0):
		if str(l.get("who", "")) != "" and str(l.get("kind", "")) == "line":
			reacted = true
	check("a floor master down: the guild cheers", reacted, FS.chat.slice(n0))
	n0 = FS.chat.size()
	FS.say("hi everyone")
	_ticks(FS, 10.0)
	check("you say hi: your line, then someone answers", FS.chat.size() >= n0 + 2 and str(FS.chat[n0]["kind"]) == "you", FS.chat.slice(n0))
	n0 = FS.chat.size()
	FS.say("how do I get past the gate?")
	_ticks(FS, 10.0)
	var tip_ok := false
	for l in FS.chat.slice(n0 + 1):
		if str(l.get("text", "")).length() > 12:
			tip_ok = true
	check("you ask: a veteran answers with a tip", tip_ok, FS.chat.slice(n0))
	FS._amb_t = 0.0
	n0 = FS.chat.size()
	_ticks(FS, 1.0)
	check("the guild talks on its own", FS.chat.size() > n0)
	var fmt_ok := true
	for l in FS.chat:
		if "{" in str(l.get("text", "")) and "}" in str(l.get("text", "")):
			fmt_ok = false
	check("no line shows a raw {placeholder}", fmt_ok)
	# ---- gifts ---------------------------------------------------------------------------------------------------
	var allowed: Array = FS.allowed_items()
	check("guildmates deal only in materials you've found", allowed.size() > 0 and allowed.all(func(i): return G.journal["items"].has(i)), allowed)
	check("...worth no more than your realm's cap", allowed.all(func(i): return int(G.items[i]["value"]) <= FS.item_value_cap()))
	check("...never something you haven't found (salt of the earth is not in your journal)", not "drake_blood" in allowed)
	var before_val := 0
	for i in 60:
		FS.maybe_gift()
	check("gifts stop at the day's cap (%d of %d)" % [FS.gift_value_today, FS.gift_cap()], FS.gift_value_today <= FS.gift_cap() and FS.gift_value_today > 0)
	# ---- trades --------------------------------------------------------------------------------------------------
	G.inventory["spirit_herb"] = 60
	G.inventory["rough_jade"] = 1
	var tr: Dictionary = {}
	for i in 30:
		FS.trades.clear()
		tr = FS.offer_trade()
		if not tr.is_empty():
			break
	check("a swap is offered when you carry plenty of one thing", not tr.is_empty())
	if not tr.is_empty():
		check("...at the shops' own prices (within 5%%: %.3f)" % FS.trade_value_gap(tr), FS.trade_value_gap(tr) <= 0.05)
		var a := str(tr["give"][0])
		var ca: int = G.count(a)
		var b := str(tr["get"][0])
		var cb: int = G.count(b)
		FS.accept_trade(int(tr["id"]))
		var free_a: bool = G.sys("tester") != null and G.sys("tester").free_item(a)       # (the test kit's free stock is never used up)
		check("...and accepting it swaps them", (G.count(a) == ca - int(tr["give"][1]) or free_a) and G.count(b) == cb + int(tr["get"][1]), [a, ca, G.count(a), b, cb, G.count(b)])
	# ---- requests ------------------------------------------------------------------------------------------------
	check("can't ask for something you've never found", FS.request_check("drake_blood", 3) != "")
	check("can't ask for 11", FS.request_check("iron_ore", 11) != "")
	var g0: int = G.gold
	var c0: int = G.count("iron_ore")
	FS.request("iron_ore", 5)
	check("an ask costs what a shop would (%d)" % (g0 - G.gold), g0 - G.gold == FS.request_price("iron_ore", 5) and FS.request_price("iron_ore", 5) == int(G.items["iron_ore"]["value"]) * 5 * 2)
	check("...it isn't there at once", G.count("iron_ore") == c0)
	FS.request("bone_shard", 2)
	FS.request("beast_hide", 2)
	check("three asks out: a fourth waits", FS.request_check("moonpetal", 2) != "")
	FS.time_shift += 1300.0
	FS._sim_t = 0.0
	_ticks(FS, 1.0)
	check("...after a while it arrives", G.count("iron_ore") == c0 + 5 and FS.requests.is_empty(), [G.count("iron_ore"), FS.requests])
	FS.time_shift = 0.0
	# ---- tasks and renown ----------------------------------------------------------------------------------------
	FS.tasks = [{"id": "slay", "text": "Together, defeat 3 foes", "event": "kill", "goal": 3, "have": 0.0, "renown": 40, "done": false}]
	var r0: int = FS.renown
	for i in 3:
		G.log_event("kill", {"type": "goblin"})
	check("your deeds fill the guild's task", bool(FS.tasks[0]["done"]) and FS.renown == r0 + 40, [FS.tasks, FS.renown])
	FS.tasks = [{"id": "craft", "text": "x", "event": "craft", "goal": 100, "have": 0.0, "renown": 30, "done": false}]
	FS._members_work(3600.0)
	check("...and so do your guildmates' (a little)", float(FS.tasks[0]["have"]) > 0.5 and float(FS.tasks[0]["have"]) < 30.0, FS.tasks[0]["have"])
	FS.renown = 0
	check("renown short: no title", FS.buy("title_heart") != "" and FS.title == "")
	FS.renown = 500
	FS.buy("title_heart")
	FS.buy("crest_violet")
	FS.buy("emblem_moon")
	check("renown buys a title, a crest, an emblem", FS.title == "title_heart" and FS.crest == "crest_violet" and FS.emblem == "emblem_moon")
	check("...shown by your name", FS.badge().contains("[LW]") and FS.title_text() == "Guild Heart", FS.badge())
	check("...and still no power", FS.effects().is_empty())
	var shop_ok := true
	for s in FS.shop():
		for k in s:
			if k in ["effect", "damage", "hp", "qi", "mult", "stat"]:
				shop_ok = false
	check("nothing in the renown shop carries a number that matters", shop_ok)
	# ---- save and load ------------------------------------------------------------------------------------------
	var st: Dictionary = FS.save_state()
	FS.reset()
	FS.load_state(JSON.parse_string(JSON.stringify(st)))
	check("the guild survives a save", FS.in_guild() and str(FS.g["name"]) == "Lantern Wardens" and FS.title == "title_heart" and FS.renown == int(st["renown"]))
	# ---- leaving and founding ------------------------------------------------------------------------------------
	FS.leave()
	check("leave the guild", not FS.in_guild())
	check("...not back the same day", FS.join_check("jade_kettle") != "")
	FS.left_day = ""
	check("a guild name needs letters", FS.found_check("ab", "AB") != "")
	check("a tag is 2-4 letters", FS.found_check("Moon Hall", "TOOLONG") != "")
	check("a taken name is refused", FS.found_check("Lantern Wardens", "LW") != "")
	var gold_b: int = G.gold
	var fm: String = FS.found("Moon Hall", "mh", "We rise at night.", 4)
	check("found your own guild", FS.in_guild() and str(FS.g["kind"]) == "own" and str(FS.g["tag"]) == "MH", fm)
	check("...for 500 gold", gold_b - G.gold == 500)
	check("...three founders", (FS.g["members"] as Array).size() == 3)
	check("...a join key for friends online", str(FS.g["key"]).begins_with("own:MH:"))
	var rc: Array = FS.recruits()
	check("recruits answer the notice (three a day, the same all day)", rc.size() == 3 and str(FS.recruits()) == str(rc))
	FS.recruit(str(rc[0]["name"]))
	check("...take one on", (FS.g["members"] as Array).size() == 4)
	check("founder's title is yours", FS.can_have(FS.shop_item("title_founder")))
	# ---- your own sect -------------------------------------------------------------------------------------------
	G.realm = 0
	check("a sect wants Core Formation", OS_.found_check() != "")
	G.realm = 3
	G.gold = 100
	check("...and 3,000 gold", OS_.found_check() != "")
	G.gold = 100000
	G.join_sect("iron_fist_clan")
	check("...and no other sect", OS_.found_check() != "")
	G.leave_sect()
	G.flags.erase("sect_left_day")
	var arts := []
	for a in G.techniques:
		arts.append(str(a))
	var fr: String = OS_.found("Ember Gate", "fire", 2, "Strike once, strike true.", arts.slice(0, 2))
	check("found the Ember Gate", OS_.founded(), fr)
	check("...you lead it (Game.sect = own)", str(G.sect.get("id", "")) == "own" and G.sect_rank_name() == "Sect Master", G.sect)
	check("...the valley knows its name", str(G.sect_def("own").get("name", "")) == "Ember Gate")
	check("...two disciples answered the call", OS_.disciples.size() == 2)
	check("...a master can't just walk out", G.leave_sect().contains("Disband") and str(G.sect.get("id", "")) == "own")
	check("a young sect gives nothing extra yet", G.sect_effect().is_empty())
	check("...and no effects of its own", OS_.effects().is_empty())
	var cs: Array = OS_.candidates()
	check("hopefuls at the gate (three, the same all day)", cs.size() == 3 and str(OS_.candidates()) == str(cs))
	# (round 191) on some days a hopeful shared a name with a disciple and was dropped -- every day, three
	var short := 0
	var real_name: String = str(OS_.sect["name"])
	for k in 300:
		OS_.sect["name"] = "%s %d" % [real_name, k]          # (the name seeds the draw like a new day does)
		if OS_.candidates().size() != 3:
			short += 1
	OS_.sect["name"] = real_name
	check("...three every day, never two (300 draws)", short == 0, short)
	OS_.recruit(str(cs[0]["name"]))
	OS_.recruit(str(cs[1]["name"]))
	check("take two in (4 of 4)", OS_.disciples.size() == 4)
	check("...the hall is full", OS_.recruit(str(cs[2]["name"])).contains("Raise the hall") and OS_.disciples.size() == 4)
	var d0: Dictionary = OS_.disciples[0]
	var p0 := float(d0["prog"])
	OS_.teach(str(d0["name"]))
	check("teaching helps", float(OS_.disciples[0]["prog"]) > p0 or int(OS_.disciples[0]["realm"]) > 0)
	check("...once a day", OS_.teach(str(d0["name"])).contains("today"))
	var r_before := int(OS_.disciples[1]["realm"]) + float(OS_.disciples[1]["prog"])
	OS_.time_shift = 10.0 * 3600.0
	OS_.catch_up()
	check("hours away: they kept training", int(OS_.disciples[1]["realm"]) + float(OS_.disciples[1]["prog"]) > r_before)
	OS_.time_shift = 500.0 * 3600.0
	for k in 30:
		OS_.time_shift += 24.0 * 3600.0
		OS_.catch_up()
	var cap_ok := true
	for d in OS_.disciples:
		if int(d["realm"]) > OS_.realm_cap():
			cap_ok = false
	check("disciples never pass one realm below you", cap_ok and OS_.realm_cap() == 2)
	var dn := str(OS_.disciples[2]["name"])
	var em: String = OS_.send_errand(dn)
	var er: Dictionary = OS_.disciple(dn)["errand"]
	check("send one on an errand", not er.is_empty(), em)
	if not er.is_empty():
		check("...within the day's cap", OS_.errand_value_today <= OS_.errand_cap())
		var eid := str(er["item"])
		if G.count(eid) + int(er["n"]) > G.pouch_cap() and not G.has_home():
			G.inventory[eid] = 0          # (a full pouch with no home leaves the rest behind -- the random errand item was sometimes one already at the cap)
		var have0: int = G.count(eid) + int(G.stash_ref().get(eid, 0))          # (a full pouch sends the rest to the chest)
		OS_.time_shift += 3.0 * 3600.0
		OS_.catch_up()
		var have1: int = G.count(eid) + int(G.stash_ref().get(eid, 0))
		check("...they come home with it", have1 == have0 + int(er["n"]) and (OS_.disciple(dn)["errand"] as Dictionary).is_empty(), "%s %d -> %d (+%d)" % [eid, have0, have1, int(er["n"])])
	check("raising the hall wants materials of the sect's element", OS_.upgrade_check() != "")
	for id in G.items:
		if str(G.items[id].get("type", "")) == "material" and str(G.items[id].get("element", "")) == "fire":
			G.inventory[id] = 50
	OS_.upgrade()
	check("hall level 2: room for 8", int(OS_.sect["hall"]) == 2 and OS_.slots() == 8)
	check("...still young", G.sect_effect().is_empty())
	OS_.upgrade()
	check("hall level 3: the sect has matured -- x1.15, what any sect's top rank gives", float(G.sect_effect().get("meditate_mult", 0.0)) == 1.15)
	# ---- the valley ----------------------------------------------------------------------------------------------
	var vd: Dictionary = G.load_level_def("valley")
	var ok_s := false
	for s in vd.get("sects", []):
		if str(s.get("id", "")) == "own":
			ok_s = true
	check("the valley puts your sect's hall at the Empty Seat", ok_s)
	check("...and the seat knows it's yours", bool(vd.get("own_seat", {}).get("founded", false)) and str(vd["own_seat"].get("name", "")) == "Ember Gate")
	var oc: Array = vd["own_seat"]["cell"]
	var g: Array = vd["map"]
	var row_n: String = g[int(oc[1]) - 7]
	check("...a walled compound", row_n[int(oc[0])] == "#")
	var gate_road := true
	for y in range(int(oc[1]) + 8, int(oc[1]) + 14):
		if (g[y] as String)[int(oc[0])] != ",":
			gate_road = false
	check("...with a road from its gate", gate_road)
	var V = load("res://scripts/world/Valley.gd")
	var clash := false
	for sl in V.SECT_SLOTS:
		if absi(sl.x - V.OWN_SEAT.x) < 22 and absi(sl.y - V.OWN_SEAT.y) < 16:
			clash = true
	for tl in V.TOWER_SLOTS:
		if absi(tl.x - V.OWN_SEAT.x) < 16 and absi(tl.y - V.OWN_SEAT.y) < 12:
			clash = true
	check("...clear of the other seats and the towers", not clash)
	# the place, built
	load("res://scripts/world/Level.gd").stream_on = false
	var lv = load("res://scripts/world/Level.gd").new()
	lv.name = "Level"
	lv.build(vd)
	root.add_child(lv)
	await process_frame
	await process_frame
	await process_frame
	var site = lv.get_tree().get_first_node_in_group("own_sect_site")
	check("the seat is built in the valley", site != null)
	var own_hall := false
	for h in lv.get_tree().get_nodes_in_group("sect_hall"):
		if str(h.sid) == "own":
			own_hall = true
	check("...with your hall (sit there: x%.1f)" % G.SECT_HALL_AID, own_hall)
	check("...and your disciples in the yard (%d)" % lv.get_tree().get_nodes_in_group("own_disciple").size(), lv.get_tree().get_nodes_in_group("own_disciple").size() >= 3)
	var board = site.get_node_or_null("Board") if site != null else null
	check("...and a board at the gate", board != null and board.is_in_group("interactable") and str(board.prompt()).contains("Ember Gate"))
	lv.queue_free()
	await process_frame
	var st2: Dictionary = OS_.save_state()
	OS_.reset()
	OS_.load_state(JSON.parse_string(JSON.stringify(st2)))
	check("the sect survives a save", OS_.founded() and str(OS_.sect["name"]) == "Ember Gate" and OS_.disciples.size() == 4)
	OS_.disband()
	check("disband: the seat is empty again", not OS_.founded() and G.sect.is_empty())
	var vd2: Dictionary = G.load_level_def("valley")
	check("...the valley shows the Empty Seat", not bool(vd2.get("own_seat", {}).get("founded", true)))
	_end()


func _end() -> void:
	print("FELLOWSHIP CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
