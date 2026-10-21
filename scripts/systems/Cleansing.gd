extends "res://scripts/systems/GameSystem.gd"
## Meridian cleansing (round 40). Robert, 2026-10-04: "have there be meridian
## cleansing that needs to be done both for major and minor nodes; this
## amplifies the base stats of the player, a percentage boost -- figure out
## a fair metric to manage that."
##
## MINOR NODES: the 36 points of the Meridian Lattice (open one, K, before you
## can cleanse it). MAJOR NODES: twelve great points (data/cleansing.json)
## that open with your realm. Each is cleansed through five grades -- murky,
## clouded, clear, pure, radiant -- by sitting with Cleanse as your focus.
##
## THE METRIC: every stat has a ceiling; the nodes that feed it share it by
## weight (minor 1, major 4, the two crown nodes 2 to every stat); a node gives
## its share times its grade (0 / 20 / 45 / 70 / 100%). Everything radiant is
## exactly the ceiling. The page shows each stat as "x% of y%".

var data := {}
var grade := {}           # node id -> 0..4
var progress := {}        # node id -> seconds toward its next grade
var target := ""
var _nodes := []          # (built once: the lattice and the majors don't change)
var _by_id := {}
var _eff := []            # effects, recomputed only when a grade changes
var _eff_dirty := true


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/cleansing.json")
	for pid in data.get("pills", {}):
		var p: Dictionary = data["pills"][pid]
		if not G.items.has(pid):
			G.items[pid] = {"name": p.get("name", pid), "type": "consumable", "value": int(p.get("value", 50)), "desc": p.get("desc", ""), "cleanse": float(p.get("seconds", 600))}
		if G._recipe_for(pid).is_empty():
			G.recipes.append({"makes": pid, "needs": (p.get("needs", {}) as Dictionary).duplicate(), "gold": 0,
				"skill": str(p.get("skill", "alchemy")), "difficulty": int(p.get("difficulty", 3)), "round40": true})


func reset() -> void:
	_eff_dirty = true
	grade = {}
	progress = {}
	target = ""


func save_state() -> Dictionary:
	return {"grade": grade, "progress": progress, "target": target}


func load_state(d: Dictionary) -> void:
	grade = {}
	var gd = d.get("grade", {})
	if gd is Dictionary:
		for k in gd:
			grade[str(k)] = int(gd[k])           # (JSON brings numbers back as floats)
	progress = d.get("progress", {}) if d.get("progress", {}) is Dictionary else {}
	target = str(d.get("target", ""))
	_eff_dirty = true


# ---- the nodes ------------------------------------------------------------------------

func nodes() -> Array:
	## every node: {id, name, meaning, major, ring|realm, stats}
	if not _nodes.is_empty():
		return _nodes
	var out := []
	var mm: Dictionary = data.get("minor_map", {})
	for p in G.lattice_data().get("points", []):
		var row: Array = mm.get(str(p.get("meridian", "")), [])
		var ring := int(p.get("ring", 1))
		var st := str(row[clampi(ring - 1, 0, row.size() - 1)]) if row.size() > 0 else "health"
		out.append({"id": str(p["id"]), "name": str(p.get("name", "")), "meaning": str(p.get("meaning", "")), "major": false,
			"ring": ring, "realm": 0, "stats": [st], "meridian": str(p.get("meridian", ""))})
	for m in data.get("majors", []):
		out.append({"id": str(m["id"]), "name": str(m.get("name", "")), "meaning": str(m.get("meaning", "")), "major": true,
			"ring": 0, "realm": int(m.get("realm", 0)), "stats": m.get("stats", []), "where": str(m.get("where", ""))})
	_nodes = out
	for n in out:
		_by_id[str(n["id"])] = n
	return out


func node(nid: String) -> Dictionary:
	if _nodes.is_empty():
		nodes()
	return _by_id.get(nid, {})


func grade_of(nid: String) -> int:
	return int(grade.get(nid, 0))


func grade_name(g: int) -> String:
	var gs: Array = data.get("grades", [])
	return str(gs[clampi(g, 0, gs.size() - 1)].get("name", "")) if gs.size() > 0 else ""


func seconds_for(nid: String, g: int) -> float:
	## sitting time from grade g-1 to grade g
	var n := node(nid)
	var gs: Array = data.get("grades", [])
	var mult := float(gs[clampi(g, 0, gs.size() - 1)].get("mult", 1)) if gs.size() > 0 else 1.0
	if bool(n.get("major", false)):
		return (float(data.get("major_seconds_base", 1200)) + float(data.get("major_seconds_per_realm", 240)) * int(n.get("realm", 0))) * mult
	return float(data.get("minor_seconds_per_ring", 240)) * int(n.get("ring", 1)) * mult


func can_cleanse(nid: String) -> String:
	## "" if the next grade of this node can be worked now, else why not
	var n := node(nid)
	if n.is_empty():
		return I18n.t("There's no such node.")
	var g := grade_of(nid)
	var gs: Array = data.get("grades", [])
	if g >= gs.size() - 1:
		return I18n.t("%s is radiant -- nothing left to wash out.") % n["name"]
	if bool(n["major"]):
		if G.realm < int(n["realm"]):
			return I18n.t("%s opens to cleansing at %s.") % [n["name"], G.realm_name_of(int(n["realm"]))]
	elif not G.lattice.has(nid):
		return I18n.t("Open %s first (the Meridian Lattice, K).") % n["name"]
	var need_realm := int(gs[g + 1].get("realm", 0)) + (1 if bool(n["major"]) and g + 1 >= 3 else 0)
	if G.realm < need_realm:
		return I18n.t("To make %s %s you need %s.") % [n["name"], grade_name(g + 1).to_lower(), G.realm_name_of(need_realm)]
	return ""


func set_target(nid: String) -> String:
	var why := can_cleanse(nid)
	if why != "":
		return why
	target = nid
	G.stats_changed.emit()
	return I18n.t("Cleansing: %s (%s), toward %s.") % [node(nid)["name"], node(nid)["meaning"], grade_name(grade_of(nid) + 1).to_lower()]


func auto_target() -> String:
	## the cheapest node you can work now
	var best := ""
	var bc := INF
	for n in nodes():
		var nid := str(n["id"])
		if can_cleanse(nid) != "":
			continue
		var c := seconds_for(nid, grade_of(nid) + 1) - float(progress.get(nid, 0.0))
		if c < bc:
			bc = c
			best = nid
	return best


func current() -> String:
	if target == "" or can_cleanse(target) != "":
		target = auto_target()
	return target


func speed() -> float:
	return G.tech_effect("cleanse_speed", 1.0) * G.tech_effect("focus_mult", 1.0)


func push(secs: float, scaled: bool = true) -> int:
	## secs of cleansing on the current node; returns grades gained
	var gained := 0
	var left := secs * (speed() if scaled else 1.0)
	var guard := 0
	while left > 0.0 and guard < 50:
		guard += 1
		var nid := current()
		if nid == "":
			return gained
		var need := seconds_for(nid, grade_of(nid) + 1)
		var have := float(progress.get(nid, 0.0)) + left
		if have < need:
			progress[nid] = have
			return gained
		left = have - need
		progress.erase(nid)
		grade[nid] = grade_of(nid) + 1
		_eff_dirty = true
		gained += 1
		_graded(nid)
	return gained


func _graded(nid: String) -> void:
	var n := node(nid)
	var g := grade_of(nid)
	G.message.emit(I18n.t("CLEANSED: %s is %s now -- %s.") % [n["name"], grade_name(g).to_lower(), ", ".join((n["stats"] as Array).map(func(s): return stat_name(str(s))))])
	G.log_event("cleansed", {"node": nid, "grade": g})
	G.bump("cleansings")
	G.gain_insight(0.5 * g * (3.0 if bool(n["major"]) else 1.0), "a node cleansed")
	if g >= 4:
		G.jingle("discovery")
		G.big_moment.emit(I18n.t("%s -- Radiant") % n["name"], I18n.t("Nothing is left in %s but light. %s") % [n["meaning"], I18n.t("A great node, wholly clean: you feel it in everything you do.") if bool(n["major"]) else "The meridian runs clear through it."])
	G.stats_changed.emit()


func meditate(secs: float, shares: Dictionary, aid: float) -> void:
	var c := float(shares.get("cleanse", 0.0))
	if c <= 0.0:
		return
	var eff: float = G.sys("mind").split_efficiency(shares)
	push(secs * aid * c * eff)


func background(secs: float, shares: Dictionary) -> void:
	var c := float(shares.get("cleanse", 0.0))
	if c > 0.0:
		push(secs * c)


func use_pill(seconds: float) -> String:
	var nid := current()
	if nid == "":
		return I18n.t("There's nothing you can cleanse right now.")
	var before := grade_of(nid)
	push(seconds, false)
	return I18n.t("The pill burns through %s.%s") % [node(nid)["name"], (I18n.t(" It's %s now.") % grade_name(grade_of(nid)).to_lower()) if grade_of(nid) > before else ""]


# ---- the metric ------------------------------------------------------------------------

func stat_name(s: String) -> String:
	return str(data.get("stats", {}).get(s, {}).get("name", s))


func _weight(n: Dictionary, stat: String) -> float:
	var W: Dictionary = data.get("weights", {})
	var sts: Array = n.get("stats", [])
	if "all" in sts:
		return float(W.get("all", 2))
	if stat in sts:
		return float(W.get("major" if bool(n.get("major", false)) else "minor", 1))
	return 0.0


func stat_fraction(stat: String) -> float:
	## how much of this stat's ceiling you've earned (0..1)
	var gs: Array = data.get("grades", [])
	var tot := 0.0
	var got := 0.0
	for n in nodes():
		var w := _weight(n, stat)
		if w <= 0.0:
			continue
		tot += w
		got += w * float(gs[clampi(grade_of(str(n["id"])), 0, gs.size() - 1)].get("frac", 0.0))
	return got / maxf(tot, 0.0001)


func stat_bonus(stat: String) -> float:
	return float(data.get("stats", {}).get(stat, {}).get("cap", 0.0)) * stat_fraction(stat)


func effects() -> Array:
	if not _eff_dirty:
		return _eff
	_eff_dirty = false
	var e := {}
	for s in data.get("stats", {}):
		var b := stat_bonus(str(s))
		if b <= 0.0:
			continue
		var sd: Dictionary = data["stats"][s]
		var k := str(sd.get("key", ""))
		if bool(sd.get("inverse", false)):
			e[k] = float(e.get(k, 1.0)) * (1.0 - b)
		else:
			e[k] = float(e.get(k, 1.0)) * (1.0 + b)
	_eff = [e] if not e.is_empty() else []
	return _eff


func radiant_count() -> int:
	var n := 0
	for k in grade:
		if int(grade[k]) >= 4:
			n += 1
	return n


func total_grades() -> int:
	var n := 0
	for k in grade:
		n += int(grade[k])
	return n


func max_grades() -> int:
	return nodes().size() * 4
