extends "res://scripts/systems/GameSystem.gd"
## Peoples in the deep (round 44). Robert, 2026-10-04: "bring more depth to the
## world ... peoples in the deep ... a sense of continuity in the world."
##
## Camps of real people on the dungeon floors (data/settlements.json): the
## mushroom farmers of Rootlight, Tallowmark's candle-makers, a Hollow Clan
## war-camp, the last disciples of a fallen sect, the Heirs singing to their
## machines ... Each is placed in an open hall when its floor is built (no
## level file changes), and each grows as you look after it:
##   CAMP -> OUTPOST (a trader) -> HAVEN (a smith, a healer or a still; a shrine)
##   -> TOWN (an inn you can wake at, their best stock, and your statue by the fire)
## Every stage changes what you SEE: more tents, a fence, stalls, lanterns,
## banners in their colours, people at work.
## ONE NEED A DAY: bring them something, or thin out the floor's beasts. Meet
## it and the camp prospers, its people think better of you (Factions.gd) and
## you're paid. Or just give supplies. Leave a camp a few days with nobody
## helping and it slips back toward the start of its stage -- never below it.
## When you come back, they tell you what happened while you were gone.

var data := {}
var state := {}           # settlement id -> {pros, peak, last_help, last_seen, decayed_to, need_day, done_day, kills, met}


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/settlements.json")
	var dr = G._load_json("res://data/drafts/settlements.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and data.get("settlements", {}).has(str(it.get("id", ""))) and str(it.get("text", "")).strip_edges() != "":
				data["settlements"][str(it["id"])]["desc"] = str(it["text"]).strip_edges()


func reset() -> void:
	state = {}


func save_state() -> Dictionary:
	return {"state": state}


func load_state(d: Dictionary) -> void:
	state = {}
	var s = d.get("state", {})
	if s is Dictionary:
		for k in s:
			if s[k] is Dictionary:
				var r: Dictionary = (s[k] as Dictionary).duplicate()
				for ik in ["peak", "last_help", "last_seen", "decayed_to", "need_day", "done_day", "kills"]:
					if r.has(ik):
						r[ik] = int(r[ik])         # (JSON brings numbers back as floats)
				state[str(k)] = r


func ids() -> Array:
	var out: Array = data.get("settlements", {}).keys()
	return out


func sdef(sid: String) -> Dictionary:
	return data.get("settlements", {}).get(sid, {})


func at_level(level_id: String) -> Array:
	var out := []
	for sid in ids():
		if str(sdef(sid).get("level", "")) == level_id:
			out.append(sid)
	return out


func _day() -> int:
	var W = G.sys("world")
	return W.day() if W else 0


func st(sid: String) -> Dictionary:
	if not state.has(sid):
		state[sid] = {"pros": 0.0, "peak": 0, "last_help": -1, "last_seen": -1, "decayed_to": -1, "need_day": -1, "done_day": -1, "kills": 0, "met": false}
	return state[sid]


# ---- growth -----------------------------------------------------------------------------------

func stage(sid: String) -> int:
	var p := float(st(sid).get("pros", 0.0))
	var out := 0
	var ss: Array = data.get("stages", [])
	for i in ss.size():
		if p >= float(ss[i].get("from", 0)):
			out = i
	return out


func stage_name(sid: String) -> String:
	var ss: Array = data.get("stages", [])
	return str(ss[clampi(stage(sid), 0, ss.size() - 1)].get("name", "")) if ss.size() > 0 else ""


func next_stage_at(sid: String) -> float:
	var ss: Array = data.get("stages", [])
	var i := stage(sid) + 1
	return float(ss[i].get("from", 0)) if i < ss.size() else -1.0


func _decay(sid: String) -> float:
	## a few days with nobody helping: the camp slips back toward the start of its stage
	var s := st(sid)
	var d := _day()
	var N: Dictionary = data.get("neglect", {})
	var since := int(s.get("last_help", -1))
	if since < 0:
		return 0.0
	var from := maxi(since + int(N.get("grace_days", 3)), int(s.get("decayed_to", -1)))
	if d <= from:
		return 0.0
	var ss: Array = data.get("stages", [])
	var floor_p := float(ss[clampi(int(s.get("peak", 0)), 0, ss.size() - 1)].get("from", 0)) if ss.size() > 0 else 0.0
	var before := float(s.get("pros", 0.0))
	var lost := minf(float(N.get("per_day", 4)) * (d - from), maxf(before - floor_p, 0.0))
	s["pros"] = before - lost
	s["decayed_to"] = d
	return lost


func _grow(sid: String, by: float, why: String) -> void:
	var s := st(sid)
	var before := stage(sid)
	s["pros"] = float(s.get("pros", 0.0)) + by
	s["last_help"] = _day()
	s["decayed_to"] = -1
	var after := stage(sid)
	if after > int(s.get("peak", 0)):
		s["peak"] = after
	if after > before:
		var nm := str(sdef(sid).get("name", sid))
		G.jingle("discovery")
		G.big_moment.emit("%s -- %s" % [nm, stage_name(sid)], _stage_line(sid))
		G.message.emit(I18n.t("%s has grown into a %s. Go and see.") % [nm, stage_name(sid).to_lower()])
		G.log_event("settlement_grew", {"settlement": sid, "stage": after, "why": why})
		G.note_place(I18n.t("%s became a %s") % [nm, stage_name(sid).to_lower()])
	G.stats_changed.emit()


func _stage_line(sid: String) -> String:
	var ls: Array = sdef(sid).get("stage_lines", [])
	return str(ls[clampi(stage(sid), 0, ls.size() - 1)]) if ls.size() > 0 else ""


# ---- today's need ---------------------------------------------------------------------------

func need(sid: String) -> Dictionary:
	## today's need: {type, item, n, why} (bring) or {type, n, why} (cull); {} if done today
	var s := st(sid)
	var d := _day()
	if int(s.get("done_day", -1)) == d:
		return {}
	var pool := []
	for nd in sdef(sid).get("needs", []):
		if str(nd.get("type", "")) == "bring" and not G.has_item_def(str(nd.get("item", ""))):
			continue
		pool.append(nd)
	if pool.is_empty():
		pool = [{"type": "cull", "n": 6, "why": "Clear some of the beasts from this floor."}]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("need|%s|%d" % [sid, d])
	var nd2: Dictionary = (pool[rng.randi() % pool.size()] as Dictionary).duplicate()
	if int(s.get("need_day", -1)) != d:
		s["need_day"] = d
		s["kills"] = 0
	return nd2


func need_text(sid: String) -> String:
	var nd := need(sid)
	if nd.is_empty():
		return I18n.t("Nothing more today. Come back tomorrow.")
	if str(nd["type"]) == "bring":
		return I18n.t("\"%s\" -- bring %d %s (you have %d).") % [str(nd.get("why", "")), int(nd["n"]), G.item_name(str(nd["item"])), _have(str(nd["item"]))]
	return I18n.t("\"%s\" -- kill %d on this floor today (%d so far).") % [str(nd.get("why", "")), int(nd["n"]), int(st(sid).get("kills", 0))]


func _have(base: String) -> int:
	var n := 0
	for id in G.inventory:
		if G.base_id(str(id)) == base:
			n += G.count(str(id))
	return n


func _take(base: String, n: int) -> void:
	var left := n
	for id in G.inventory.keys():
		if left <= 0:
			break
		if G.base_id(str(id)) == base and G.equipped_count(str(id)) < G.count(str(id)):
			var k := mini(left, G.count(str(id)) - G.equipped_count(str(id)))
			G.remove_item(str(id), k)
			left -= k


func can_meet(sid: String) -> String:
	## "" if today's need can be met now, else why not
	var nd := need(sid)
	if nd.is_empty():
		return I18n.t("Their need is met for today.")
	if str(nd["type"]) == "bring":
		return "" if _have(str(nd["item"])) >= int(nd["n"]) else I18n.t("You have %d of %d %s.") % [_have(str(nd["item"])), int(nd["n"]), G.item_name(str(nd["item"]))]
	return "" if int(st(sid).get("kills", 0)) >= int(nd["n"]) else I18n.t("%d of %d killed on this floor today.") % [int(st(sid).get("kills", 0)), int(nd["n"])]


func meet(sid: String) -> String:
	var why := can_meet(sid)
	if why != "":
		return why
	var nd := need(sid)
	if str(nd["type"]) == "bring":
		_take(str(nd["item"]), int(nd["n"]))
	var R: Dictionary = data.get("need_reward", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("reward|%s|%d" % [sid, _day()])
	var pr: Array = R.get("prosperity", [22, 34])
	var by := rng.randf_range(float(pr[0]), float(pr[1]))
	var depth := _depth_of(sid)
	var gold := int(R.get("gold_per_depth", 9)) * maxi(depth, 1)
	G.gold += gold
	st(sid)["done_day"] = _day()
	var F = G.sys("factions")
	if F:
		F.change(str(sdef(sid).get("faction", "")), float(R.get("standing", 12)), I18n.t("helped ") + str(sdef(sid).get("name", sid)))
	G.log_event("settlement_help", {"settlement": sid, "need": nd.get("type", "")})
	G.bump("settlement_help")
	_grow(sid, by, "need")
	return I18n.t("%s is grateful. (+%d gold; the camp grows.)") % [str(sdef(sid).get("name", sid)), gold]


func supplies_price(sid: String) -> int:
	return int(data.get("supplies", {}).get("gold_per_depth", 12)) * maxi(_depth_of(sid), 1)


func give_supplies(sid: String) -> String:
	var p := supplies_price(sid)
	if G.gold < p:
		return I18n.t("You need %d gold for a cartload of supplies.") % p
	G.gold -= p
	var S: Dictionary = data.get("supplies", {})
	var F = G.sys("factions")
	if F:
		F.change(str(sdef(sid).get("faction", "")), float(S.get("standing", 2)), I18n.t("supplies for ") + str(sdef(sid).get("name", sid)))
	G.log_event("settlement_supplies", {"settlement": sid, "gold": p})
	_grow(sid, float(S.get("prosperity", 6)), "supplies")
	return I18n.t("You hand over %d gold of supplies.") % p


func _depth_of(sid: String) -> int:
	var lid := str(sdef(sid).get("level", ""))
	var n := int(lid.trim_prefix("floor")) if lid.begins_with("floor") else 1
	return maxi(n, 1)


func rest_price(sid: String) -> int:
	var F = G.sys("factions")
	var fid := str(sdef(sid).get("faction", ""))
	if F and ((fid == "deepfolk" and F.camp_rest_free()) or F.at_least(fid, "honoured")):
		return 0
	return int(data.get("rest_price_per_depth", 4)) * _depth_of(sid)


func rest(sid: String) -> String:
	var p := rest_price(sid)
	if G.gold < p:
		return I18n.t("A spot by the fire costs %d gold.") % p
	G.gold -= p
	G.hp = G.max_hp()
	G.log_event("rest", {"at": str(sdef(sid).get("level", "")), "price": p, "camp": sid})
	G.stats_changed.emit()
	return I18n.t("You sleep by the fire and wake whole.%s") % (I18n.t(" (They wouldn't take your coin.)") if p == 0 else "")


func hostile(sid: String) -> bool:
	var F = G.sys("factions")
	return F != null and not F.at_least(str(sdef(sid).get("faction", "")), "wary")


func make_amends(sid: String) -> String:
	var p := supplies_price(sid) * 2
	if G.gold < p:
		return I18n.t("They want %d gold in tribute before they'll talk.") % p
	G.gold -= p
	var F = G.sys("factions")
	if F:
		F.change(str(sdef(sid).get("faction", "")), 60.0, I18n.t("tribute paid at ") + str(sdef(sid).get("name", sid)), false)
	G.log_event("settlement_amends", {"settlement": sid})
	return I18n.t("The tribute is taken without a word. Something has changed.")


# ---- coming back -----------------------------------------------------------------------------

func visit(sid: String) -> String:
	## what happened while you were gone (said once per visit day)
	var s := st(sid)
	var d := _day()
	var lost := _decay(sid)
	var seen := int(s.get("last_seen", -1))
	s["last_seen"] = d
	if not bool(s.get("met", false)):
		s["met"] = true
		G.log_event("settlement_met", {"settlement": sid})
		G.note_place(I18n.t("Met the people of ") + str(sdef(sid).get("name", sid)))
		return str(sdef(sid).get("desc", ""))
	if seen < 0 or seen == d:
		return ""
	var away := d - seen
	var out := I18n.t("It's been %d day%s since you were here.") % [away, "" if away == 1 else "s"]
	if lost > 0.5:
		out += I18n.t(" Nobody's been helping; things have got harder (%d prosperity lost).") % int(lost)
	elif int(s.get("last_help", -1)) >= seen:
		out += I18n.t(" What you did last time is still paying off.")
	var F = G.sys("factions")
	var fid := str(sdef(sid).get("faction", ""))
	if F and str(F.fdef(fid).get("rival", "")) != "" and F.value(str(F.fdef(fid)["rival"])) > F.value(fid) + 150:
		out += I18n.t(" People here have heard you've been friendly with the %s. They're cooler with you.") % str(F.fdef(str(F.fdef(fid)["rival"])).get("short", ""))
	return out


func on_event(kind: String, d: Dictionary) -> void:
	if kind != "kill":
		return
	for sid in at_level(str(G.current_level)):
		var nd := need(sid)
		if not nd.is_empty() and str(nd["type"]) == "cull" and not bool(G.enemies.get(str(d.get("type", "")), {}).get("passive", false)):
			var s := st(sid)
			s["kills"] = int(s.get("kills", 0)) + 1
			if int(s["kills"]) == int(nd["n"]):
				G.message.emit(I18n.t("%s's hunt is done -- go back and tell %s.") % [str(sdef(sid).get("name", sid)), str(sdef(sid).get("headman", {}).get("name", "them"))])


# ---- the headman's dialog (NPC.gd role "headman") ---------------------------------------------

func talk(npc, extra: String = "") -> void:
	var hud = G.get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var sid := str(npc.def.get("settlement", ""))
	var sd := sdef(sid)
	var title := "%s -- %s" % [str(npc.npc_name), str(sd.get("name", ""))]
	var body := extra
	var opts := []
	if hostile(sid):
		body = (body + "\n\n" if body != "" else "") + I18n.t("\"You're no friend of ours. Say your piece and go.\"\n\n(%s are %s toward you. Paying tribute will mend it.)") % [str(G.sys("factions").name_of(str(sd.get("faction", "")))), str(G.sys("factions").tier(str(sd.get("faction", ""))).get("name", "")).to_lower()]
		opts.append(["Pay tribute (%d gold)" % (supplies_price(sid) * 2), func(): talk(npc, make_amends(sid))])
		opts.append(["Leave", hud.close_dialog])
		hud.open_dialog(title, body, opts)
		return
	var back := visit(sid)
	var head := "\"%s\"" % str(sd.get("headman", {}).get("line", "")) if back == "" else back
	if market_day(sid):
		head += I18n.t("\n\n(%s has gone up to Eliet to sell today. Every third day, now we're a town.)") % trader_name(sid)
	body = ((body + "\n\n") if body != "" else "") + head
	body += "\n\n%s: %s  ·  %s" % [stage_name(sid), _stage_line(sid), _progress_text(sid)]
	body += I18n.t("\n\nToday: ") + need_text(sid)
	var can := can_meet(sid)
	var nd := need(sid)
	if not nd.is_empty():
		var label := (I18n.t("Hand over %d %s") % [int(nd["n"]), G.item_name(str(nd["item"]))]) if str(nd["type"]) == "bring" else I18n.t("Report the hunt")
		opts.append([label + ("" if can == "" else "  [" + can + "]"), func(): talk(npc, meet(sid))])
	opts.append(["Give supplies (%d gold)" % supplies_price(sid), func(): talk(npc, give_supplies(sid))])
	var rp := rest_price(sid)
	opts.append(["Rest by the fire (%s)" % ("free" if rp == 0 else I18n.t("%d gold") % rp), func(): talk(npc, rest(sid))])
	opts.append(["Ask about %s" % str(sd.get("name", "")), func(): talk(npc, str(sd.get("desc", "")) + "\n\n(" + _faction_line(sid) + ")")])
	opts.append(["Goodbye", hud.close_dialog])
	hud.open_dialog(title, body, opts)


func _faction_line(sid: String) -> String:
	var F = G.sys("factions")
	var fid := str(sdef(sid).get("faction", ""))
	if F == null:
		return ""
	return I18n.t("They are of %s, who count you as %s.") % [F.name_of(fid), str(F.tier(fid).get("name", "")).to_lower()]


func _progress_text(sid: String) -> String:
	var nx := next_stage_at(sid)
	if nx < 0:
		return I18n.t("it can't grow any further")
	return I18n.t("%d / %d to grow") % [int(float(st(sid).get("pros", 0.0))), int(nx)]


# ---- placing a camp ----------------------------------------------------------------------------

func place(level) -> int:
	## put this floor's camps in open halls (Level.gd calls this as the floor is built)
	var n := 0
	for sid in at_level(str(level.level_id)):
		# an open square one wider than the camp, so nothing it puts down can close a way through
		var rad := 3
		var c: Vector2i = level.open_spot(4, "camp|" + sid)
		if c.x < 0:
			rad = 2
			c = level.open_spot(3, "camp|" + sid)
		if c.x < 0:
			level.warnings.append(I18n.t("no room for the camp ") + sid)
			continue
		level._spawn_script("res://scripts/world/Settlement.gd", level.cell_to_world(c), {"cell": c, "sid": sid, "radius": rad})
		level._count("settlements")
		n += 1
	return n


# ---- round 45: a town trades with Eliet -------------------------------------------------------

func trader_name(sid: String) -> String:
	for p in sdef(sid).get("people", []):
		if str(p.get("role", "")) == "merchant":
			return str(p.get("name", ""))
	return ""


func market_day(sid: String, d: int = -1) -> bool:
	## once a camp is a town, its trader goes up to Eliet every third day
	if stage(sid) < 3 or trader_name(sid) == "":
		return false
	if d < 0:
		d = _day()
	return (d + absi(hash(sid))) % 3 == 0


func visitors() -> Array:
	## who's up in Eliet from the deep today: [{sid, name, stock, line, faction}]
	var out := []
	for sid in ids():
		if not market_day(sid):
			continue
		var sd := sdef(sid)
		var spec: Array = sd.get("specialty", [])
		var stock: Array = (sd.get("stock", []) as Array).duplicate()
		stock.append_array(spec)
		var sname: String = G.item_name(str(spec[0])) if spec.size() > 0 and G.has_item_def(str(spec[0])) else "our goods"
		out.append({"sid": sid, "name": "%s of %s" % [trader_name(sid), str(sd.get("name", sid))], "stock": stock, "faction": str(sd.get("faction", "")),
			"line": I18n.t("Up from %s, on floor %d. %s -- you won't find it anywhere else up here. We're a town now, thanks to you.") % [str(sd.get("name", sid)), _depth_of(sid), sname]})
	return out


func place_visitors(level) -> int:
	var n := 0
	for v in visitors():
		var c: Vector2i = level.near_spot(level.fountain_cell(), 14, "visitor|" + str(v["sid"]), level.plaza_rmin())
		if c.x < 0:
			continue
		level._spawn_script("res://scripts/actors/NPC.gd", level.cell_to_world(c), {"cell": c, "role": "merchant", "name": str(v["name"]), "line": str(v["line"]),
			"def": {"settlement": str(v["sid"]), "faction": str(v["faction"]), "stock": v["stock"], "stays": true, "visitor": true}})
		level._count("visitors")
		n += 1
	return n
