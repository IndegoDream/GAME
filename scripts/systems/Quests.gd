extends "res://scripts/systems/GameSystem.gd"
## Side quests (round 52). Robert, 2026-10-04: "build in multiple side quests
## ... as close to mainstream level of material as possible."
##
## Questlines given by the people of Eliet and of the deep's towns
## (data/sidequests.json). Each is a few stages:
##   talk      go and speak to someone (and hand over what they asked for)
##   find      things placed somewhere on a floor -- a gold diamond marks
##             each once you're near
##   hunt      a named foe on a floor, marked the same way
##   kill_floor  clear a floor of so many foes
##   gather    have so many of something
##   craft     make something
##   reach     get down to a floor
## Some end with a choice that changes the reward and who thinks well of
## you. A quest opens when you've been deep enough; whoever gives it wears a
## gold "!" over their head (and a "?" when you've something to tell them).
## The Quests page lists them all; the tracked one shows top right.
##
## Round 55 -- the sects' roads (Robert, 2026-10-04: "make several chain
## quests available at the sects for interesting rewards"). Every valley
## sect's elder has five: the first a guest can walk; the rest are for that
## sect's own disciples, opening rank by rank (unlock "sect", "sect_rank").
## They pay what nothing else does -- a keepsake, the sect's token, its
## secret art, the founder's heirloom, the heart canon -- plus contribution,
## element affinity and insight. A sect Dev writes later gets a road built
## from data/sidequests.json "sect_template". Two more chains wait where
## the sects meet in the deep (the Jade Pagoda, the Hollow Moon). A giver
## or a talk step can be pinned to a place ("giver_at", goal "where") so
## two people with one name in two towns aren't confused.

var data := {}
var active := {}           # qid -> {"stage": int, "prog": int}
var done := {}             # qid -> ending id
var tracked := ""
var legacy_defs := {}      # round 119: the quest lines inheritances open (scripts/systems/LegacyLines.gd), made when taken up
var _t := 0.0
var quiet := false            # tools only: no offers (the older tests talk to townsfolk for other things)
var _snoozed := {}            # npc -> msec: a "Not now" isn't asked again for a while


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/sidequests.json")
	_sect_roads()
	var dr = G._load_json("res://data/drafts/side_quests.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and str(it.get("text", "")).strip_edges() != "":
				var q := qdef(str(it.get("id", "")))
				if not q.is_empty():
					q["pitch"] = str(it["text"]).strip_edges()
	_register()


func _register() -> void:
	for tid in data.get("techniques", {}):
		if not G.technique_defs.has(tid):
			var t: Dictionary = data["techniques"][tid]
			G.technique_defs[tid] = {"name": t.get("name", tid), "kind": "passive", "desc": t.get("desc", ""),
				"effect": (t.get("effect", {}) as Dictionary).duplicate(), "realm": 0, "source": "quest"}
	for id in data.get("quest_items", {}):
		if not G.items.has(id):
			G.items[id] = {"name": str(data["quest_items"][id]), "type": "quest", "value": 0, "desc": "Something someone is waiting for. (A quest item.)"}
	for id in data.get("uniques", {}):
		if not G.items.has(id):
			var u: Dictionary = data["uniques"][id]
			G.items[id] = {"name": u.get("name", id), "type": "treasure", "value": int(u.get("value", 100)), "effect": (u.get("effect", {}) as Dictionary).duplicate(), "desc": u.get("desc", ""), "quest_reward": true}


# ---- round 55: a road for any sect without one --------------------------------------------

func _sect_roads() -> void:
	## the authored roads name their sect; any valley sect without one gets
	## the template's, with its own names, element and gifts filled in
	var tpl: Dictionary = data.get("sect_template", {})
	if tpl.is_empty() or not (data.get("quests", null) is Array):
		return
	var have := {}
	for q in all():
		if str(q.get("sect", "")) != "":
			have[str(q["sect"])] = true
	for sd in G.valley_data().get("sects", []):
		var sid := str(sd.get("id", ""))
		if sid == "" or have.has(sid):
			continue
		var el := str(sd.get("element", "earth"))
		var elder := str(sd.get("elder", {}).get("name", "the Elder")) if sd.get("elder", {}) is Dictionary else "the Elder"
		var discs: Array = sd.get("disciples", []) if sd.get("disciples", []) is Array else []
		var sub := {"{sid}": sid, "{sect}": str(sd.get("name", sid)), "{elder}": elder, "{el}": el,
			"{d1}": str(discs[0]) if discs.size() > 0 else elder, "{d2}": str(discs[1]) if discs.size() > 1 else elder}
		var qs: Array = _fill(tpl.get("quests", []), sub)
		for i in qs.size():
			var q: Dictionary = qs[i]
			var u := {"floor": int(q.get("floor", 1))}
			q.erase("floor")
			if i >= 1:
				u["sect"] = sid
				u["after"] = "%s_%d" % [sid, i]
			if i >= 2:
				u["sect_rank"] = i - 1
			q["id"] = "%s_%d" % [sid, i + 1]
			q["kind"] = "sect"
			q["sect"] = sid
			q["giver"] = elder
			q["giver_at"] = "valley"
			q["place"] = "valley"
			q["unlock"] = u
			data["quests"].append(q)
		var gifts: Dictionary = tpl.get("gifts", {}).get(el, tpl.get("gifts", {}).get("earth", {}))
		if not data.has("uniques"):
			data["uniques"] = {}
		if not data.has("techniques"):
			data["techniques"] = {}
		if not data.has("quest_items"):
			data["quest_items"] = {}
		var nm: String = sub["{sect}"]
		for row in [["token", "Token of the %s" % nm, 150], ["sash", "Sash of the %s" % nm, 600], ["heirloom", "Heirloom of the %s" % nm, 4000]]:
			var eff: Dictionary = (gifts.get(row[0], {}) as Dictionary).duplicate()
			data["uniques"]["sq_%s_%s" % [sid, row[0]]] = {"name": row[1], "desc": I18n.t("From the %s: %s.") % [nm, G.effect_text(eff)], "effect": eff, "value": row[2]}
		for row2 in [["inner_way", "inner", "Inner Way of the %s" % nm], ["heart_canon", "canon", "Heart Canon of the %s" % nm]]:
			var eff2: Dictionary = (gifts.get(row2[1], {}) as Dictionary).duplicate()
			data["techniques"]["%s_%s" % [sid, row2[0]]] = {"name": row2[2], "desc": I18n.t("The %s's own: %s.") % [nm, G.effect_text(eff2)], "effect": eff2}
		var its: Dictionary = _fill(tpl.get("items", {}), sub)
		for id in its:
			data["quest_items"][id] = its[id]


func _fill(v, sub: Dictionary):
	## a copy of v with every {placeholder} filled in (keys too)
	if v is String:
		var s: String = v
		for k in sub:
			s = s.replace(str(k), str(sub[k]))
		return s
	if v is Array:
		var out := []
		for x in v:
			out.append(_fill(x, sub))
		return out
	if v is Dictionary:
		var out2 := {}
		for k in v:
			out2[_fill(str(k), sub)] = _fill(v[k], sub)
		return out2
	return v


func reset() -> void:
	active = {}
	done = {}
	tracked = ""
	legacy_defs = {}
	_snoozed = {}


func save_state() -> Dictionary:
	return {"active": active, "done": done, "tracked": tracked, "legacy_defs": legacy_defs}


func load_state(d: Dictionary) -> void:
	active = {}
	var a = d.get("active", {})
	if a is Dictionary:
		for k in a:
			active[str(k)] = {"stage": int(a[k].get("stage", 0)), "prog": int(a[k].get("prog", 0))}
	done = d.get("done", {}) if d.get("done", {}) is Dictionary else {}
	tracked = str(d.get("tracked", ""))
	var ld = d.get("legacy_defs", {})
	legacy_defs = ld if ld is Dictionary else {}


# ---- what there is -------------------------------------------------------------------------------

func all() -> Array:
	var base: Array = data.get("quests", [])
	if legacy_defs.is_empty():
		return base
	return base + legacy_defs.values()


func qdef(qid: String) -> Dictionary:
	for q in all():
		if str(q.get("id", "")) == qid:
			return q
	return {}


func unlocked(qid: String) -> bool:
	var q := qdef(qid)
	if q.is_empty() or active.has(qid) or done.has(qid):
		return false
	if str(q.get("expansion", "")) != "" and not G.expansion_open(str(q["expansion"])):
		return false                      # round 58: an expansion's quest, and the expansion isn't here
	var u: Dictionary = q.get("unlock", {})
	if str(u.get("after", "")) != "" and not done.has(str(u["after"])):
		return false                      # (the next step of a craft's road, after the last)
	if str(u.get("sect", "")) != "" and not G.in_sect(str(u["sect"])):
		return false                      # round 55: a sect's own road is for its own disciples
	if u.has("sect_rank") and int(G.sect.get("rank", 0)) < int(u["sect_rank"]):
		return false
	return G.reach_depth() >= int(u.get("floor", 0)) and G.realm >= int(u.get("realm", 0))


func offers_for(npc: String) -> Array:
	var out := []
	for q in all():
		if str(q.get("giver", "")) == npc and _here(str(q.get("giver_at", ""))) and unlocked(str(q["id"])):
			out.append(str(q["id"]))
	return out


func stage(qid: String) -> Dictionary:
	if not active.has(qid):
		return {}
	var st: Array = qdef(qid).get("stages", [])
	var i := int(active[qid]["stage"])
	return st[i] if i >= 0 and i < st.size() else {}


func goal(qid: String) -> Dictionary:
	return stage(qid).get("goal", {})


func waiting_talk(npc: String) -> String:
	## an active quest whose current stage is to come and talk to this person
	for qid in active:
		var g := goal(qid)
		if str(g.get("talk", "")) == npc and _here(str(g.get("where", ""))):
			return str(qid)
	return ""


func _here(place: String) -> bool:
	## a giver or a talk pinned to a place: only there (two Master Yuns, two towns)
	return place == "" or G.current_level == place


func sect_locked(qid: String) -> bool:
	## a sect road's step you can't take because you're not of that sect
	var s := str(qdef(qid).get("unlock", {}).get("sect", ""))
	return s != "" and not G.in_sect(s)


func sect_road(sid: String) -> Array:
	var out := []
	for q in all():
		if str(q.get("sect", "")) == sid:
			out.append(str(q["id"]))
	return out


func sect_line(sid: String) -> String:
	## what the elder's dialog says about the sect's road
	var road := sect_road(sid)
	if road.is_empty():
		return ""
	var n := 0
	for id in road:
		if done.has(id):
			n += 1
	var nxt := ""
	for id in road:
		if done.has(id):
			continue
		var q := qdef(id)
		var u: Dictionary = q.get("unlock", {})
		if active.has(id):
			nxt = "On it now: %s." % q.get("name", "")
		elif unlocked(id):
			nxt = "Ask about \"%s\"." % q.get("name", "")
		elif str(u.get("sect", "")) != "" and not G.in_sect(str(u["sect"])):
			nxt = "The rest is for the sect's own disciples."
		elif u.has("sect_rank") and int(G.sect.get("rank", 0)) < int(u["sect_rank"]):
			nxt = I18n.t("Next, when you're %s: %s.") % [G.sect_rank_name(int(u["sect_rank"])), q.get("name", "")]
		elif G.reach_depth() < int(u.get("floor", 0)):
			nxt = I18n.t("Next, once you've been down to floor %d: %s.") % [int(u.get("floor", 0)), q.get("name", "")]
		else:
			nxt = "Next: %s." % q.get("name", "")
		break
	return I18n.t("The sect's road: %d of %d done.%s") % [n, road.size(), (" " + nxt) if nxt != "" else " You've walked all of it."]


func marker_for(npc: String) -> String:
	if waiting_talk(npc) != "":
		return "?"
	return "!" if not offers_for(npc).is_empty() else ""


func goal_floor(qid: String) -> int:
	return _floor_of(goal(qid))


func deepest_floor(qid: String) -> int:
	## round 58: the deepest any stage of a quest goes (for one not yet taken)
	var best := 0
	for stg in qdef(qid).get("stages", []):
		if stg is Dictionary:
			best = maxi(best, _floor_of(stg.get("goal", {})))
	return best


func _floor_of(g: Dictionary) -> int:
	for k in ["find", "hunt", "kill_floor"]:
		if g.has(k):
			return int(g[k].get("floor", 0))
	if g.has("reach"):
		return int(g["reach"])
	if g.has("event") and str(g["event"].get("where", "")).begins_with("floor"):
		return int(str(g["event"]["where"]).trim_prefix("floor"))
	return 0


func kind_of(qid: String) -> String:
	return str(qdef(qid).get("kind", "side"))


const KINDS := [["side", "Side quests"], ["sect", "Sects"], ["gathering", "Gathering"], ["social", "People"], ["master", "Masters"],
	["smithing", "Blacksmithing"], ["alchemy", "Alchemy"], ["medicine", "Medicine"], ["jewelcrafting", "Jewelcrafting"],
	["hunting", "Hunting and taming"], ["exploration", "Exploration"], ["legacy", "Legacy tasks"], ["heirloom", "Heirloom"]]


func kind_name(k: String) -> String:
	for row in KINDS:
		if str(row[0]) == k:
			return str(row[1])
	return k.capitalize()


# ---- talking ---------------------------------------------------------------------------------------

func talk(npc_node, hud, after: Callable) -> bool:
	## true if this conversation was about a quest (the dialog is open)
	var npc := str(npc_node.npc_name)
	var qid := waiting_talk(npc)
	if qid != "":
		_talk_stage(qid, hud, after)
		return true
	var offers := offers_for(npc)
	if offers.is_empty() or quiet or int(_snoozed.get(npc, 0)) > Time.get_ticks_msec():
		return false
	if offers.size() > 1:
		# round 54: someone with more than one thing to ask -- pick which to hear
		var opts := []
		for oid in offers:
			var o := str(oid)
			opts.append(["%s  (%s)" % [str(qdef(o).get("name", "")), kind_name(kind_of(o))], func():
				hud.close_dialog()
				_offer(o, npc, hud, after)])
		opts.append(["Not now", func():
			_snoozed[npc] = Time.get_ticks_msec() + 300000
			hud.close_dialog()
			after.call()])
		hud.open_dialog(npc, "\"I could use a hand -- more than one, if I'm honest.\"", opts)
		return true
	_offer(str(offers[0]), npc, hud, after)
	return true


func _offer(qid: String, npc: String, hud, after: Callable) -> void:
	var q := qdef(qid)
	hud.open_dialog("%s -- %s" % [npc, str(q.get("name", ""))], str(q.get("pitch", "")) + I18n.t("\n\n(%s quest%s.)") % [kind_name(kind_of(qid)).trim_suffix(" quests"), locked_tag(qid).replace(" (", ": ").trim_suffix(")")],
		[["I'll do it", func():
			hud.close_dialog()
			accept(str(q["id"]))],
		["Not now", func():
			_snoozed[npc] = Time.get_ticks_msec() + 300000      # (asked again in five minutes, not every time)
			hud.close_dialog()
			after.call()]])


func _missing_takes(st: Dictionary) -> Array:
	var miss := []
	var tk: Dictionary = st.get("take", {})
	for id in tk:
		if G.count(str(id)) < int(tk[id]):
			miss.append("%s (%d/%d)" % [G.item_name(str(id)), G.count(str(id)), int(tk[id])])
	return miss


func _talk_stage(qid: String, hud, after: Callable) -> void:
	var q := qdef(qid)
	var st := stage(qid)
	var miss := _missing_takes(st)
	if not miss.is_empty():
		hud.open_dialog(str(q.get("giver", "")) + " -- " + str(q.get("name", "")), I18n.t("\"Have you got it?\"\n\n(Still needed: %s.)") % ", ".join(miss),
			[["Not yet", func():
				hud.close_dialog()
				after.call()]])
		return
	var body := str(st.get("say", ""))
	var choices: Array = st.get("choices", [])
	var opts := []
	if choices.is_empty():
		opts.append(["Go on", func():
			hud.close_dialog()
			advance(qid)])
	else:
		for c in choices:
			var cc: Dictionary = c
			opts.append([str(cc.get("text", "")), func():
				hud.close_dialog()
				advance(qid, str(cc.get("ending", "")))])
	hud.open_dialog(str(q.get("name", "")), (body + "\n\n" if body != "" else "") + "(%s)" % str(st.get("log", "")), opts)


# ---- the flow ----------------------------------------------------------------------------------------

func accept(qid: String) -> void:
	if not unlocked(qid):
		return
	active[qid] = {"stage": 0, "prog": 0}
	if tracked == "" or not active.has(tracked):
		tracked = qid
	G.message.emit(I18n.t("QUEST: %s -- %s") % [str(qdef(qid).get("name", "")), str(stage(qid).get("log", ""))])
	G.log_event("side_quest_start", {"quest": qid})
	_spawn_here(qid)
	_check(qid)
	G.stats_changed.emit()


func advance(qid: String, ending: String = "") -> void:
	## the current stage is done: take what it asked for, say what it says, go on
	if not active.has(qid):
		return
	var st := stage(qid)
	var tk: Dictionary = st.get("take", {})
	for id in tk:
		G.remove_item(str(id), int(tk[id]))
	var sts: Array = qdef(qid).get("stages", [])
	var i := int(active[qid]["stage"]) + 1
	if ending != "" or i >= sts.size():
		_finish(qid, ending if ending != "" else "default")
		return
	active[qid] = {"stage": i, "prog": 0}
	G.message.emit(I18n.t("QUEST: %s -- %s") % [str(qdef(qid).get("name", "")), str(stage(qid).get("log", ""))])
	G.log_event("side_quest_stage", {"quest": qid, "stage": i})
	_spawn_here(qid)
	_check(qid)
	G.stats_changed.emit()


func _spawn_here(qid: String) -> void:
	## the next stage is on the floor you're standing on: put it there now
	if not G.is_inside_tree():
		return
	var lv = G.get_tree().get_first_node_in_group("level")
	if lv and lv.has_method("place_quests") and str(lv.level_id) == "floor%d" % goal_floor(qid):
		lv.place_quests.call_deferred(qid)


func _stage_done(qid: String) -> void:
	## a stage finished out in the world (not by talking)
	var line := str(stage(qid).get("say", ""))
	if line != "":
		G.message.emit(line)
	advance(qid)


func _finish(qid: String, ending: String) -> void:
	var q := qdef(qid)
	var ends: Dictionary = q.get("endings", {})
	var e: Dictionary = ends.get(ending, ends.get("default", ends.values()[0] if ends.size() > 0 else {}))
	active.erase(qid)
	done[qid] = ending
	if tracked == qid:
		tracked = str(active.keys()[0]) if active.size() > 0 else ""
	var hud = G.get_tree().get_first_node_in_group("hud") if G.is_inside_tree() else null
	if hud and str(e.get("say", "")) != "":
		hud.open_dialog(str(q.get("name", "")) + I18n.t(" -- done"), str(e.get("say", "")) + "\n\n" + reward_text(qid, e.get("reward", {})), [["Thank you", hud.close_dialog]])
	_reward(qid, e.get("reward", {}))
	# what's left of the quest's own things goes
	for id in data.get("quest_items", {}):
		if _quest_uses(q, str(id)) and G.count(str(id)) > 0:
			G.remove_item(str(id), G.count(str(id)))
	G.message.emit("QUEST COMPLETE: %s" % str(q.get("name", "")))
	G.log_event("side_quest_done", {"quest": qid, "ending": ending})
	G.stats_changed.emit()


func _quest_uses(q: Dictionary, id: String) -> bool:
	if str(q.get("hunt_drop", "")) == id:
		return true
	for st in q.get("stages", []):
		var g: Dictionary = st.get("goal", {})
		if str(g.get("find", {}).get("item", "")) == id:
			return true
	return false


func reward_qi(qid: String, rw: Dictionary) -> float:
	## qi as so many kills' worth of the quest's own depth
	var depth := maxi(1, _depth_of(qid))
	var tot := 0.0
	var n := 0
	for eid in G.enemies:
		var s: Dictionary = G.enemies[eid]
		if int(s.get("floor", -1)) == depth and not bool(s.get("passive", false)) and not bool(s.get("boss", false)):
			tot += float(s.get("qi", 0))
			n += 1
	var per := tot / n if n > 0 else 10.0 * pow(1.4, depth)
	return float(rw.get("qi", 0)) + float(rw.get("qi_kills", 0)) * per * G.KILL_QI_MULT


func _depth_of(qid: String) -> int:
	var d := 0
	for st in qdef(qid).get("stages", []):
		var g: Dictionary = st.get("goal", {})
		for k in ["find", "hunt", "kill_floor"]:
			if g.has(k):
				d = maxi(d, int(g[k].get("floor", 0)))
		if g.has("reach"):
			d = maxi(d, int(g["reach"]))
	return d if d > 0 else int(qdef(qid).get("unlock", {}).get("floor", 1))


func reward_text(qid: String, rw: Dictionary) -> String:
	var parts := []
	if int(rw.get("gold", 0)) > 0:
		parts.append(I18n.t("%d gold") % int(rw["gold"]))
	var qi := reward_qi(qid, rw)
	if qi > 0:
		parts.append("%d qi" % int(qi))
	for id in rw.get("items", {}):
		parts.append("%d x %s" % [int(rw["items"][id]), G.item_name(str(id))])
	if str(rw.get("title", "")) != "":
		parts.append(I18n.t("the name \"%s\"") % str(rw["title"]))
	if str(rw.get("technique", "")) != "":
		parts.append(I18n.t("the art %s") % str(G.technique_defs.get(str(rw["technique"]), {}).get("name", rw["technique"])))
	for sk in rw.get("skill_xp", {}):
		parts.append(I18n.t("practice in %s") % str(sk))
	for npc in rw.get("bond", {}):
		parts.append(I18n.t("%s's friendship") % str(npc))
	if float(rw.get("contrib", 0)) > 0:
		parts.append(I18n.t("%d sect contribution") % int(rw["contrib"]))
	for el in rw.get("affinity", {}):
		parts.append(I18n.t("+%d %s affinity") % [int(rw["affinity"][el]), str(el)])
	if float(rw.get("insight", 0)) > 0:
		parts.append(I18n.t("%d insight") % int(rw["insight"]))
	var F = G.sys("factions")
	for fid in rw.get("standing", {}):
		var v := float(rw["standing"][fid])
		parts.append(I18n.t("%s%d with %s") % ["+" if v >= 0 else "", int(v), F.name_of(str(fid)) if F else str(fid)])
	return I18n.t("(Reward: %s.)") % ", ".join(parts) if parts.size() > 0 else ""


func _reward(qid: String, rw: Dictionary) -> void:
	if int(rw.get("gold", 0)) > 0:
		G.add_item("gold", int(rw["gold"]))
	var qi := reward_qi(qid, rw)
	if qi > 0:
		G.add_qi(qi, I18n.t("quest: ") + str(qdef(qid).get("name", "")))
	for id in rw.get("items", {}):
		G.add_item(str(id), int(rw["items"][id]))
	for npc in rw.get("bond", {}):
		G.warm_bond(str(npc), float(rw["bond"][npc]))
	for sk in rw.get("skill_xp", {}):
		G.add_skill_xp(str(sk), float(rw["skill_xp"][sk]), "a quest")
	if str(rw.get("technique", "")) != "":
		G.learn(str(rw["technique"]), I18n.t("quest: ") + str(qdef(qid).get("name", "")))
	if float(rw.get("contrib", 0)) > 0:
		# round 55: a sect's road pays that sect; anyone else's favour pays whichever sect you're in
		var qs := str(qdef(qid).get("sect", ""))
		if (qs == "" and G.in_sect()) or (qs != "" and G.in_sect(qs)):
			G.sect_contrib(float(rw["contrib"]), "a sect task")
	for el in rw.get("affinity", {}):
		if G.affinity.has(str(el)):
			G.affinity[str(el)] = minf(float(G.affinity[str(el)]) + float(rw["affinity"][el]), 100.0)
	if float(rw.get("insight", 0)) > 0:
		G.gain_insight(float(rw["insight"]), "a quest")
	var t := str(rw.get("title", ""))
	if t != "" and not G.titles.has(t):
		G.titles.append(t)
		G.message.emit("TITLE: %s." % t)
	var F = G.sys("factions")
	if F:
		for fid in rw.get("standing", {}):
			F.change(str(fid), float(rw["standing"][fid]), I18n.t("a favour: ") + str(qdef(qid).get("name", "")))


# ---- progress out in the world ----------------------------------------------------------------------

func _check(qid: String) -> void:
	## stages that are already met (you had the herbs; you've been that deep)
	if not active.has(qid):
		return
	var g := goal(qid)
	if g.has("gather") and G.count(str(g["gather"].get("item", ""))) >= int(g["gather"].get("count", 1)):
		_stage_done(qid)
	elif g.has("reach") and G.reach_depth() >= int(g["reach"]):
		_stage_done(qid)
	elif g.has("find") and G.count(str(g["find"].get("item", ""))) >= int(g["find"].get("count", 1)):
		_stage_done(qid)
	elif g.has("skill") and G.skill_level(str(g["skill"].get("id", ""))) >= int(g["skill"].get("level", 1)):
		_stage_done(qid)
	elif g.has("bond") and float(G.bond(str(g["bond"].get("npc", ""))).get("warmth", 0.0)) >= float(g["bond"].get("warmth", 15)):
		_stage_done(qid)
	elif g.has("realm") and G.realm >= int(g["realm"]):
		_stage_done(qid)
	elif g.has("learn") and G.has_tech(str(g["learn"])):
		_stage_done(qid)


func tick(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or active.is_empty():
		return
	_t = 2.0
	for qid in active.keys():
		_check(str(qid))


func on_event(kind: String, d: Dictionary) -> void:
	if active.is_empty():
		return
	for qid in active.keys():
		var g := goal(str(qid))
		if kind == "kill" and g.has("kill_floor") and G.current_level == "floor%d" % int(g["kill_floor"].get("floor", 0)):
			active[qid]["prog"] = int(active[qid]["prog"]) + 1
			if int(active[qid]["prog"]) >= int(g["kill_floor"].get("count", 1)):
				_stage_done(str(qid))
			elif int(active[qid]["prog"]) % 3 == 0:
				G.message.emit("%s: %d / %d" % [str(qdef(str(qid)).get("name", "")), int(active[qid]["prog"]), int(g["kill_floor"].get("count", 1))])
		elif kind == "craft" and bool(d.get("success", false)) and g.has("craft") and str(d.get("makes", "")) == str(g["craft"]):
			_stage_done(str(qid))
		elif kind == "craft" and bool(d.get("success", false)) and g.has("craft_n") and _craft_matches(g["craft_n"], d):
			active[qid]["prog"] = int(active[qid]["prog"]) + 1
			if int(active[qid]["prog"]) >= int(g["craft_n"].get("count", 1)):
				_stage_done(str(qid))
		elif (kind == "craft" or kind == "forge") and bool(d.get("success", false)) and g.has("craft_q") and _craft_matches(g["craft_q"], d) \
				and _q_rank(str(d.get("quality", ""))) >= _q_rank(str(g["craft_q"].get("quality", "fine"))):
			_stage_done(str(qid))
		elif g.has("event") and _event_matches(g["event"], kind, d):
			active[qid]["prog"] = int(active[qid]["prog"]) + int(d.get("n", 1)) if bool(g["event"].get("sum_n", false)) else int(active[qid]["prog"]) + 1
			var need := int(g["event"].get("count", 1))
			if int(active[qid]["prog"]) >= need:
				_stage_done(str(qid))
			elif need >= 5 and int(active[qid]["prog"]) % maxi(1, need / 4) == 0:
				G.message.emit("%s: %d / %d" % [str(qdef(str(qid)).get("name", "")), int(active[qid]["prog"]), need])


const QRANK := {"crude": 0, "": 1, "fine": 2, "superior": 3, "masterwork": 4}


func _q_rank(q: String) -> int:
	return int(QRANK.get(q, 1))


func _craft_skill(item: String) -> String:
	for r in G.recipes:
		if str(r.get("makes", "")) == item:
			return str(r.get("skill", ""))
	return ""


func _craft_matches(c: Dictionary, d: Dictionary) -> bool:
	var made := str(d.get("makes", d.get("made", "")))
	if c.has("item") and G.base_id(made) != str(c["item"]) and made != str(c["item"]):
		return false
	if c.has("skill") and _craft_skill(G.base_id(made)) != str(c["skill"]) and _craft_skill(made) != str(c["skill"]):
		return false
	return true


func _event_matches(e: Dictionary, kind: String, d: Dictionary) -> bool:
	## an "event" goal: this kind of thing happening (what the play log records),
	## optionally only somewhere, or only with certain details
	if str(e.get("kind", "")) != kind:
		return false
	if e.has("where") and G.current_level != str(e["where"]):
		return false
	var m: Dictionary = e.get("match", {})
	for k in m:
		if str(d.get(k, "")) != str(m[k]):
			return false
	return true


func found(qid: String, item: String) -> void:
	## a quest thing picked up on a floor
	if not active.has(qid):
		return
	G.add_item(item, 1)
	var g := goal(qid)
	var n := int(g.get("find", {}).get("count", 1))
	var have: int = G.count(item)
	if have < n:
		G.message.emit("%s: %d / %d" % [G.item_name(item), have, n])
	_check(qid)


func hunted(qid: String) -> void:
	if not active.has(qid) or not goal(qid).has("hunt"):
		return
	var drop := str(qdef(qid).get("hunt_drop", ""))
	if drop != "":
		G.add_item(drop, 1)
	_stage_done(qid)


func spawns_for(level_id: String) -> Array:
	## what this floor should hold for the quests you're on
	var out := []
	for qid in active:
		var g := goal(str(qid))
		if g.has("find") and level_id == "floor%d" % int(g["find"].get("floor", 0)):
			var f: Dictionary = g["find"]
			var left: int = int(f.get("count", 1)) - int(G.count(str(f.get("item", ""))))
			for i in maxi(left, 0):
				out.append({"qid": qid, "kind": "find", "item": f.get("item", ""), "what": f.get("what", "something"), "look": f.get("look", "satchel"), "index": i})
		elif g.has("hunt") and level_id == "floor%d" % int(g["hunt"].get("floor", 0)):
			var h: Dictionary = g["hunt"]
			out.append({"qid": qid, "kind": "hunt", "name": h.get("name", I18n.t("a named foe")), "type": h.get("type", "strongest"), "hp_mult": float(h.get("hp_mult", 3.0)), "index": 0})
	return out


# ---- the lines the HUD and the menu show -----------------------------------------------------------

func progress_text(qid: String) -> String:
	return _progress(qid) + locked_tag(qid)


func locked_tag(qid: String) -> String:
	## round 58: a quest whose goal is below the free floors, on a phone without the full game
	var st = G.store
	if st == null or st.full_game() or st.model() != "locked":
		return ""
	var f := goal_floor(qid) if active.has(qid) else deepest_floor(qid)
	if f <= st.free_depth():
		return ""
	return " (%s)" % str(st.data().get("pitch", {}).get("locked_quest", I18n.t("full game")))


func _progress(qid: String) -> String:
	var g := goal(qid)
	if g.has("find"):
		return " (%d/%d)" % [mini(G.count(str(g["find"].get("item", ""))), int(g["find"].get("count", 1))), int(g["find"].get("count", 1))] if int(g["find"].get("count", 1)) > 1 else ""
	if g.has("kill_floor"):
		return " (%d/%d)" % [int(active[qid]["prog"]), int(g["kill_floor"].get("count", 1))]
	if g.has("gather"):
		return " (%d/%d)" % [mini(G.count(str(g["gather"].get("item", ""))), int(g["gather"].get("count", 1))), int(g["gather"].get("count", 1))]
	if g.has("event"):
		return " (%d/%d)" % [mini(int(active[qid]["prog"]), int(g["event"].get("count", 1))), int(g["event"].get("count", 1))]
	if g.has("craft_n"):
		return " (%d/%d)" % [int(active[qid]["prog"]), int(g["craft_n"].get("count", 1))]
	if g.has("skill"):
		return " (%d/%d)" % [mini(G.skill_level(str(g["skill"].get("id", ""))), int(g["skill"].get("level", 1))), int(g["skill"].get("level", 1))]
	if g.has("bond"):
		return " (%s)" % G.bond_stage(str(g["bond"].get("npc", "")))
	return ""


func tracked_line() -> String:
	if tracked == "" or not active.has(tracked):
		return ""
	return I18n.t("Quest: %s%s") % [str(stage(tracked).get("log", "")), progress_text(tracked)]


func rumours() -> Array:
	## quests waiting to be picked up, and where
	var out := []
	for q in all():
		if unlocked(str(q["id"])):
			out.append([str(q["id"]), str(q.get("giver", "")), str(q.get("place", ""))])
	return out
