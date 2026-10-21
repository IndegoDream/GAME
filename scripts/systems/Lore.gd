extends "res://scripts/systems/GameSystem.gd"
## Words that give something (round 42). Robert, 2026-10-04: "the story and
## explanations should be easy to understand and be meaningful, or give
## something more to the game -- either filling out its history or giving
## hints and tips through conversation, reading, secrets, treasure and
## inheritance."
##
## pick(where) hands back one thing worth reading, for wherever the world has
## something to say -- a lore stone, a hidden wall, a chest, a dead master's
## last words, anyone you ask for advice:
##   a TIP      true, and about where you are and what you need: a secret
##              still on this floor, what the next gate wants, what the gate's
##              item is made of, what a material in your pouch is for, how to
##              beat this floor's master, a hidden master's rumour ...
##   HISTORY    one plain fragment of the story of Eliet and the deep,
##              unlocked by how deep you've been, never twice
## Everything found is kept (the Road page: "What you've learned").
## data/tips.json; Dev's words: briefs `tips` and `history`.

var data := {}
var seen := {}            # tip id -> times given
var history_found := []   # history ids, in the order found
var notes := []           # [{"text", "where", "kind"}], newest last (kept to 40)


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/tips.json")
	# Dev's words: templates only if they keep every {placeholder}; history adds
	var dt = G._load_json("res://data/drafts/tips.json", {})
	if dt is Dictionary:
		for it in dt.get("items", []):
			if not (it is Dictionary):
				continue
			var k := str(it.get("id", ""))
			var mine := str(data.get("templates", {}).get(k, ""))
			var theirs := str(it.get("text", "")).strip_edges()
			if mine != "" and theirs != "" and _holes(mine) == _holes(theirs):
				data["templates"][k] = theirs
	var dh = G._load_json("res://data/drafts/history.json", {})
	if dh is Dictionary:
		var have := {}
		for h in data.get("history", []):
			have[str(h.get("id", ""))] = true
		for it in dh.get("items", []):
			if not (it is Dictionary) or str(it.get("text", "")).strip_edges() == "":
				continue
			var hid := str(it.get("id", ""))
			if hid == "":
				hid = "dev:" + str(it.get("title", it["text"])).to_lower().left(40)
			if have.has(hid):
				continue
			have[hid] = true
			data["history"].append({"id": hid, "floor": int(it.get("floor", 0)), "title": str(it.get("title", "")), "text": str(it["text"]).strip_edges()})


func _holes(s: String) -> Array:
	var out := []
	var re := RegEx.new()
	re.compile("\\{[a-z]+\\}")
	for m in re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


func reset() -> void:
	seen = {}
	history_found = []
	notes = []


func save_state() -> Dictionary:
	return {"seen": seen, "history": history_found, "notes": notes}


func load_state(d: Dictionary) -> void:
	seen = d.get("seen", {}) if d.get("seen", {}) is Dictionary else {}
	history_found = d.get("history", []) if d.get("history", []) is Array else []
	notes = d.get("notes", []) if d.get("notes", []) is Array else []


# ---- what's true right now ---------------------------------------------------------------

func _t(kind: String, fill: Dictionary = {}) -> String:
	var s := str(data.get("templates", {}).get(kind, ""))
	for k in fill:
		s = s.replace("{%s}" % k, str(fill[k]))
	return s


func _level():
	if not G.is_inside_tree():
		return null
	for lv in G.get_tree().get_nodes_in_group("level"):
		if is_instance_valid(lv) and not lv.is_queued_for_deletion():
			return lv
	return null


func tips() -> Array:
	## every tip that's true and useful now: [{id, kind, text, weight}], most useful first
	var out := []
	var lv = _level()
	# secrets still on this floor
	if lv and "level_id" in lv:
		var left := 0
		var hidden_chests := 0
		var hidden_traps := 0
		for n in lv.get_children():
			var sc = n.get_script()
			if sc == null:
				continue
			var path := str(sc.resource_path)
			if path.ends_with("SecretWall.gd") and not G.has_flag(str(n._key)):
				left += 1
			elif path.ends_with("Chest.gd") and bool(n.hidden) and not G.has_flag(str(n._key)):
				hidden_chests += 1
			elif path.ends_with("Trap.gd") and bool(n.hidden):
				hidden_traps += 1
		if left > 0:
			out.append({"id": "secrets:%s:%d" % [lv.level_id, left], "kind": "secrets", "weight": 9, "text": _t("secrets", {"n": left})})
		if hidden_traps > 0 and G.skill_level("survival") < 10:
			out.append({"id": "traps:" + str(lv.level_id), "kind": "traps", "weight": 6, "text": _t("traps")})      # round 46
		if hidden_chests > 0:
			out.append({"id": "hidden_chest:%s" % lv.level_id, "kind": "hidden_chest", "weight": 6, "text": _t("hidden_chest")})
		# the floor's master
		var boss := ""
		for ch in lv.def.get("enemies", {}):
			var et := str(lv.def["enemies"][ch])
			if bool(G.enemies.get(et, {}).get("boss", false)) and not G.has_flag("%s:boss:%s" % [lv.level_id, et]):
				boss = str(G.enemies[et].get("name", et))
		if boss != "":
			out.append({"id": "boss:%s" % lv.level_id, "kind": "boss", "weight": 5, "text": _t("boss", {"boss": boss})})
	# the next gate, and what its item is made of
	var ng: Dictionary = G.next_gate()
	if not ng.is_empty():
		var fl := int(ng.get("floor", 0))
		var miss: Array = G.gate_missing(fl)
		if not miss.is_empty() and fl <= G.reach_depth() + 6:
			out.append({"id": "gate:%d:%s" % [fl, ",".join(miss)], "kind": "gate", "weight": 8, "text": _t("gate", {"floor": fl, "needs": " and ".join(miss)})})
			var item := str(ng.get("need", {}).get("item", ""))
			if item != "" and G.count(item) <= 0:
				var r: Dictionary = G._recipe_for(item)
				if not r.is_empty():
					var mats := []
					for m in r.get("needs", {}):
						mats.append("%d %s" % [int(r["needs"][m]), G.item_name(str(m))])
					out.append({"id": "gate_item:%s" % item, "kind": "gate_item", "weight": 8, "text": _t("gate_item", {"item": G.item_name(item), "mats": ", ".join(mats)})})
	# a material in the pouch with no known use
	for id in G.inventory.keys():
		if str(G.item_def(str(id)).get("type", "")) != "material":
			continue
		var known: Array = G.journal.get("items", {}).get(G.base_id(str(id)), {}).get("uses", [])
		if not known.is_empty():
			continue
		for r2 in G.recipes:
			if r2.get("needs", {}).has(G.base_id(str(id))) and G.skill_known(str(r2.get("skill", "smithing"))):
				out.append({"id": "material:%s" % G.base_id(str(id)), "kind": "material", "weight": 4,
					"text": _t("material", {"item": G.item_name(str(id)), "made": G.item_name(str(r2["makes"]))})})
				break
	# masters, crafts
	var hh: String = G.hm_hint()
	if hh != "":
		out.append({"id": "master:" + hh.left(30), "kind": "master", "weight": 6, "text": _t("master", {"rumour": hh})})
	for sk in ["runecraft", "talismans"]:
		if not G.skill_known(sk) and G.reach_depth() >= (14 if sk == "runecraft" else 19):
			out.append({"id": "craft:" + sk, "kind": "craft", "weight": 5, "text": _t("craft", {"rumour": G.craft_teacher_hint(sk)})})
	# the inner road
	var C = G.sys("cleansing")
	if C and C.total_grades() == 0 and C.current() != "":
		out.append({"id": "cleanse", "kind": "cleanse", "weight": 5, "text": _t("cleanse")})
	var R = G.sys("research")
	if R and R.researched.is_empty() and G.nanite_tier() >= 1:
		out.append({"id": "research", "kind": "research", "weight": 4, "text": _t("research")})
	for e in G.ELEMENTS:
		var o: String = G.OVERCOMES[e]
		if not G.all_aspects_alive() and float(G.affinity[e]) >= G.AFFINITY_ACTIVE and float(G.affinity[o]) >= G.AFFINITY_ACTIVE and absf(float(G.affinity[e]) - float(G.affinity[o])) < G.CLASH_GAP:
			var between := str(G.GENERATES[e])
			out.append({"id": "clash:%s:%s" % [e, o], "kind": "clash", "weight": 7, "text": _t("clash", {"a": str(e).capitalize(), "b": o.capitalize(), "c": between.capitalize()})})
	# people
	if G.party_free_slot() >= 0:
		for nm in G.bonds:
			if G.in_party(str(nm)) < 0 and float(G.bond(str(nm)).get("warmth", 0.0)) >= G.COMPANION_WARMTH:
				out.append({"id": "friend:" + str(nm), "kind": "friend", "weight": 3, "text": _t("friend", {"name": nm})})
				break
	# round 45: the world -- camps, the old age, the calendar, the clans
	out.append_array(_world_tips())
	out.append_array(_tell_tips())
	# the basics, for anyone new
	if float(G.counters.get("shrine_seconds", 0.0)) < 120.0:
		out.append({"id": "sitting", "kind": "sitting", "weight": 2, "text": _t("sitting")})
	if float(G.counters.get("parries", G.counters.get("parry", 0.0))) <= 0.0 and G.reach_depth() >= 2:
		out.append({"id": "parry", "kind": "parry", "weight": 2, "text": _t("parry")})
	out.sort_custom(func(a, b): return int(a["weight"]) - 3 * int(seen.get(str(a["id"]), 0)) > int(b["weight"]) - 3 * int(seen.get(str(b["id"]), 0)))
	return out.filter(func(t): return str(t["text"]).strip_edges() != "")


func next_history() -> Dictionary:
	## the next fragment you can know (by how deep you've been), never twice
	var d: int = G.reach_depth()
	var best := {}
	for h in data.get("history", []):
		if str(h.get("id", "")) in history_found or int(h.get("floor", 0)) > d:
			continue
		if best.is_empty() or int(h.get("floor", 0)) < int(best.get("floor", 0)):
			best = h
	return best


# ---- handing them out ----------------------------------------------------------------------

func pick(where: String, prefer: String = "") -> Dictionary:
	## {text, kind ("tip"/"history"), frame} -- or {} when there's nothing new worth saying
	var ts := tips()
	var t: Dictionary = {}
	for x in ts:
		if int(seen.get(str(x["id"]), 0)) == 0:
			t = x
			break
	var h := next_history()
	var use_history := false
	if prefer == "history":
		use_history = not h.is_empty()
	elif prefer == "tip":
		use_history = t.is_empty() and not h.is_empty()
	else:
		# reading leans to history, everything else to a tip -- whichever there is
		use_history = not h.is_empty() and (t.is_empty() or (where in ["stele", "secret"] and history_found.size() * 2 <= seen.size()))
	var frame := str(data.get("frames", {}).get(where, ""))
	if use_history:
		history_found.append(str(h["id"]))
		var txt := "%s -- %s" % [str(h.get("title", "")), str(h.get("text", ""))] if str(h.get("title", "")) != "" else str(h.get("text", ""))
		_keep(txt, where, "history")
		G.log_event("history_found", {"id": h["id"], "where": where})
		return {"text": txt, "kind": "history", "frame": frame}
	if t.is_empty() and not ts.is_empty() and where == "npc":
		t = ts[0]                     # (asked directly, someone always has something to say)
	if t.is_empty():
		return {}
	seen[str(t["id"])] = int(seen.get(str(t["id"]), 0)) + 1
	_keep(str(t["text"]), where, "tip")
	G.log_event("tip_found", {"kind": t["kind"], "where": where})
	return {"text": str(t["text"]), "kind": "tip", "frame": frame}


func _keep(text: String, where: String, kind: String) -> void:
	for n in notes:
		if str(n.get("text", "")) == text:
			return
	notes.append({"text": text, "where": where, "kind": kind})
	if notes.size() > 40:
		notes = notes.slice(notes.size() - 40)
	G.stats_changed.emit()


func framed(where: String, prefer: String = "") -> String:
	## the frame and the words, ready to append to what's being shown ("" = nothing)
	var p := pick(where, prefer)
	if p.is_empty():
		return ""
	return "%s\n%s" % [str(p["frame"]), str(p["text"])] if str(p["frame"]) != "" else str(p["text"])


func _world_tips() -> Array:
	## round 45: the world's news, as tips -- a camp that needs you, a relic waiting,
	## a festival coming, hunters on your trail, a trader up from the deep
	var out := []
	var S = G.sys("settlements")
	var R = G.sys("ruins")
	var W = G.sys("world")
	var F = G.sys("factions")
	var reach: int = G.reach_depth()
	if S:
		var ids: Array = S.ids()
		ids.sort_custom(func(a, b): return S._depth_of(a) < S._depth_of(b))
		for sid in ids:
			var dep: int = S._depth_of(sid)
			if not bool(S.st(sid).get("met", false)) and dep <= reach + 3:
				out.append({"id": "camp_unmet:" + sid, "kind": "camp_unmet", "weight": 5, "text": _t("camp_unmet", {"floor": dep})})
				break
		for sid2 in ids:
			if not bool(S.st(sid2).get("met", false)):
				continue
			var nd: Dictionary = S.need(sid2)
			if nd.is_empty():
				continue
			var nt := (I18n.t("bring %d %s") % [int(nd["n"]), G.item_name(str(nd["item"]))]) if str(nd["type"]) == "bring" else (I18n.t("thin out the beasts on their floor (%d)") % int(nd["n"]))
			out.append({"id": "camp_need:%s:%d" % [sid2, W.day() if W else 0], "kind": "camp_need", "weight": 6,
				"text": _t("camp_need", {"camp": str(S.sdef(sid2).get("name", sid2)), "floor": S._depth_of(sid2), "need": nt})})
			break
		for v in S.visitors():
			out.append({"id": "market:%s:%d" % [str(v["sid"]), W.day() if W else 0], "kind": "market", "weight": 4, "text": _t("market", {"trader": str(v["name"])})})
			break
	if R and reach >= 4 and R.found.size() < R.data.get("relics", {}).size():
		var ptr: String = R.pointer(maxi(int(G.depth), 4))
		out.append({"id": "relic:" + ptr.right(12), "kind": "relic", "weight": 4, "text": _t("relic", {"pointer": ptr})})
	if W and not W.calm:
		var nf: int = W.next_festival_in()
		if nf >= 1 and nf <= 2:
			var fd: Dictionary = W.festival(W.day() + nf)
			out.append({"id": "festival:%d" % (W.day() + nf), "kind": "festival", "weight": 5,
				"text": _t("festival", {"name": str(fd.get("name", "")), "days": "a day" if nf == 1 else "%d days" % nf})})
		var tip := str(W.season().get("tip", ""))
		if tip != "":
			out.append({"id": "season:" + W.season_id(), "kind": "season", "weight": 2, "text": _t("season", {"tip": tip})})
	if F and F.hunters_hunting():
		out.append({"id": "hunters", "kind": "hunters", "weight": 8, "text": _t("hunters")})
	return out


func _tell_tips() -> Array:
	## round 60: how to read a foe -- Dev's words (brief foe_tells) for the
	## moves you've met, once there are any
	var out := []
	var dr: Dictionary = G.draft_texts("foe_tells")
	if dr.is_empty():
		return out
	var met := {"brawler": G.has_flag("tut:heavy_tell"), "boss_slam": G.has_flag("tut:boss_move"), "boss_sweep": G.has_flag("tut:boss_move"),
		"charger": G.reach_depth() >= 2, "ranged": G.reach_depth() >= 2, "guardian": G.reach_depth() >= 2, "skulker": G.reach_depth() >= 2,
		"swarmer": G.reach_depth() >= 2, "mender": G.reach_depth() >= 2, "boss_enrage": G.reach_depth() >= 1}
	for k in dr:
		var txt: String = str(dr[k])
		if bool(met.get(str(k), G.reach_depth() >= 3)):
			out.append({"id": "tell:" + str(k), "kind": "tell", "weight": 3, "text": txt})
	return out

