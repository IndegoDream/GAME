extends "res://scripts/systems/GameSystem.gd"
## Round 143: a story for each Wayfarer (Menagerie.gd). Three chapters open as trust grows (20, 45, 70); each asks one thing --
## items, fights, a floor reached together, crafts, sitting still -- and pays a little insight, gold or pills. Finishing a
## chapter also makes that Wayfarer's gift 8% stronger while they travel with you (24% after the third), so a story is also
## a way to grow a companion that doesn't cost anyone anything.
## State per Wayfarer: chapters done, and the one in hand (its progress). data/wayfarer_stories.json.

var data := {}
var done := {}               # name -> chapters finished
var act := {}                # name -> {"ch": index, "prog": float}   (accepted, not yet told)
var _skill_of := {}          # a made thing -> its craft


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/wayfarer_stories.json")
	for r in G.recipes:
		_skill_of[str(r.get("makes", ""))] = str(r.get("skill", ""))


func reset() -> void:
	done = {}
	act = {}


func save_state() -> Dictionary:
	return {"done": done, "act": act}


func load_state(d: Dictionary) -> void:
	reset()
	for k in d.get("done", {}):
		done[str(k)] = clampi(int(d["done"][k]), 0, 3)
	for k in d.get("act", {}):
		var a: Dictionary = d["act"][k]
		act[str(k)] = {"ch": int(a.get("ch", 0)), "prog": float(a.get("prog", 0.0))}


func chapters(name: String) -> Array:
	return data.get("stories", {}).get(name, [])


func done_count(name: String) -> int:
	return int(done.get(name, 0))


func complete(name: String) -> bool:
	return done_count(name) >= chapters(name).size() and chapters(name).size() > 0


func _MN():
	return G.sys("menagerie")


func goal_of(name: String) -> Dictionary:
	var chs := chapters(name)
	var i := done_count(name)
	return (chs[i] as Dictionary).get("goal", {}) if i < chs.size() else {}


func _have(goal: Dictionary) -> bool:
	for it in goal.get("items", {}):
		var need := int(goal["items"][it])
		var have: int = G.gold if str(it) == "gold" else G.count(str(it))
		if have < need:
			return false
	return true


func progress(name: String) -> Array:
	## [have, need] for the chapter in hand
	var g := goal_of(name)
	var a: Dictionary = act.get(name, {})
	match str(g.get("kind", "")):
		"have":
			var have := 0
			var need := 0
			for it in g.get("items", {}):
				var n := int(g["items"][it])
				need += n
				var h: int = G.gold if str(it) == "gold" else G.count(str(it))
				have += mini(h, n)
			return [have, need]
		"kills", "craft":
			return [mini(int(a.get("prog", 0.0)), int(g.get("count", 1))), int(g.get("count", 1))]
		"sit":
			return [mini(int(a.get("prog", 0.0)), int(g.get("minutes", 1))), int(g.get("minutes", 1))]
		"depth":
			var m = _MN()
			return [mini(int(m.deep.get(name, 0)) if m != null else 0, int(g.get("floor", 1))), int(g.get("floor", 1))]
	return [0, 1]


func is_ready(name: String) -> bool:
	if not act.has(name) or goal_of(name).is_empty():
		return false
	var p := progress(name)
	return int(p[0]) >= int(p[1])


func view(name: String) -> Dictionary:
	## what the Party page shows: {"state": none/locked/offer/active/ready/complete, "title", "text", "hint", "have", "need", "chapter", "of", "trust"}
	var chs := chapters(name)
	if chs.is_empty():
		return {"state": "none"}
	var i := done_count(name)
	if i >= chs.size():
		return {"state": "complete", "chapter": chs.size(), "of": chs.size()}
	var c: Dictionary = chs[i]
	var m = _MN()
	var tr_now: float = m.trust_of(name) if m != null else 0.0
	var v := {"title": str(c["title"]), "text": str(c["ask"]), "hint": str(c["hint"]), "chapter": i + 1, "of": chs.size(), "trust": int(c["trust"])}
	var p := progress(name)
	v["have"] = int(p[0])
	v["need"] = int(p[1])
	if tr_now < float(c["trust"]):
		v["state"] = "locked"
	elif not act.has(name):
		v["state"] = "offer"
	elif is_ready(name):
		v["state"] = "ready"
	else:
		v["state"] = "active"
	return v


func accept(name: String) -> String:
	var v := view(name)
	if str(v.get("state", "")) != "offer":
		return ""
	act[name] = {"ch": done_count(name), "prog": 0.0}
	G.message.emit(I18n.t("STORY: %s -- %s. %s") % [name, str(v["title"]), I18n.t("Needed: %s.") % str(v["hint"])])
	G.stats_changed.emit()
	return str(v["text"])


func finish(name: String) -> String:
	## tell them: take what they asked for, pay the chapter
	if not is_ready(name):
		return ""
	var chs := chapters(name)
	var c: Dictionary = chs[done_count(name)]
	var g: Dictionary = c.get("goal", {})
	for it in g.get("items", {}):
		if not G.remove_item(str(it), int(g["items"][it])):
			return ""
	var r: Dictionary = c.get("reward", {})
	var bits := []
	if r.has("insight"):
		G.gain_insight(float(r["insight"]), name)
		bits.append(I18n.t("%d insight") % int(r["insight"]))
	if r.has("gold"):
		G.add_item("gold", int(r["gold"]), false)
		bits.append(I18n.t("%d gold") % int(r["gold"]))
	for it in r.get("items", {}):
		G.add_item(str(it), int(r["items"][it]), false)
		bits.append("%s x%d" % [G.item_name(str(it)), int(r["items"][it])])
	done[name] = done_count(name) + 1
	act.erase(name)
	var m = _MN()
	if m != null:
		m._gain(name, 4.0)
	G.warm_bond(name, 2.0)
	var extra := I18n.t(" Their gift is stronger now (+%d%%).") % int(round(float(data.get("bonus_per_chapter", 0.08)) * 100.0 * done_count(name)))
	G.message.emit(I18n.t("STORY: %s -- chapter %d done%s.%s") % [name, done_count(name), (" (+" + ", ".join(bits) + ")") if bits.size() > 0 else "", extra])
	G.log_event("wayfarer_story", {"name": name, "chapter": done_count(name)})
	G.stats_changed.emit()
	return str(c["done"])


func effects() -> Array:
	var out := []
	var m = _MN()
	if m == null:
		return out
	var per := float(data.get("bonus_per_chapter", 0.08))
	for nm in m.party_wayfarers():
		var n := done_count(str(nm))
		if n <= 0:
			continue
		var one := {}
		m._scale(m.wayfarer(str(nm)).get("gift", {}), per * float(n), one)
		out.append(one)
	return out


func _party_acting(kind: String) -> Array:
	var out := []
	var m = _MN()
	if m == null:
		return out
	for nm in m.party_wayfarers():
		var a: Dictionary = act.get(str(nm), {})
		if not a.is_empty() and str(goal_of(str(nm)).get("kind", "")) == kind:
			out.append(str(nm))
	return out


func tick(delta: float) -> void:
	if not G.sitting:
		return
	for nm in _party_acting("sit"):
		act[nm]["prog"] = float(act[nm].get("prog", 0.0)) + delta / 60.0


func on_event(kind: String, d: Dictionary) -> void:
	if kind == "kill":
		for nm in _party_acting("kills"):
			var want := str(goal_of(nm).get("type", ""))
			if want == "" or want == str(d.get("type", "")):
				act[nm]["prog"] = float(act[nm].get("prog", 0.0)) + 1.0
	elif (kind == "craft" or kind == "forge") and bool(d.get("success", false)):
		var sk: String = "smithing" if kind == "forge" else str(_skill_of.get(str(d.get("makes", "")), ""))
		for nm in _party_acting("craft"):
			var want_s := str(goal_of(nm).get("skill", ""))
			if want_s == "" or want_s == sk:
				act[nm]["prog"] = float(act[nm].get("prog", 0.0)) + 1.0
