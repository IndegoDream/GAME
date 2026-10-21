extends "res://scripts/systems/GameSystem.gd"
## Round 148: the road workshop and the sects' techniques. Robert, 2026-10-18: "build a crafting table and whatever I need to do crafts on the go.
## Make this like a resource quest, and a quest to the sects to find a more reliable technique for building the world and other game-altering
## skills and techniques ... long and challenging, especially as the items become more useful."
##   WORKSHOP LINES (four, in order): the Folding Table (crafting anywhere, no no-bench penalty), the Field Forge (a forge anywhere), the
##     Alchemist's Roll (rune table and alchemy bench anywhere), the Master's Kit (steadier, finer work). Each is a chain of things to hand in,
##     craft, reach and fell; the materials and the difficulty climb steeply.
##   SECT LINES: the Reliable Seed (Lotus Ascent Academy: the inner world grows half again as fast, holds more, opens its workshop room),
##     the Steady Hands Method (Blacksmiths), the Wayfinder's Step (Lodge), the Hearth-Fire Breath (Alchemists), the Gatherer's Eye (Hall),
##     and the World-Seed (needs the Seed and the Master's Kit; the longest chain in the game).
## At most two lines in hand. A step is either a thing you hand over ("give"), or a standing fact that is checked for you (depth, skill, rank,
## inner world level), or a count (crafts, kills, minutes sitting) that starts when you take the line. Offline game only. data/workshop.json.

var data := {}
var done := {}               # line id -> true
var act := {}                # line id -> {"step": int, "prog": float}
var _acc := 0.0
var _skill_of := {}          # a made thing -> its craft
var _diff_of := {}           # a made thing -> its recipe difficulty


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/workshop.json")
	for r in G.recipes:
		_skill_of[str(r.get("makes", ""))] = str(r.get("skill", ""))
		_diff_of[str(r.get("makes", ""))] = int(r.get("difficulty", 0))


func reset() -> void:
	done = {}
	act = {}
	_acc = 0.0


func save_state() -> Dictionary:
	return {"done": done, "act": act}


func load_state(d: Dictionary) -> void:
	reset()
	for k in d.get("done", {}):
		if not line(str(k)).is_empty() and bool(d["done"][k]):
			done[str(k)] = true
	for k in d.get("act", {}):
		var a: Dictionary = d["act"][k]
		var ln := line(str(k))
		if not ln.is_empty() and not done.has(str(k)):
			act[str(k)] = {"step": clampi(int(a.get("step", 0)), 0, (ln["steps"] as Array).size() - 1), "prog": maxf(0.0, float(a.get("prog", 0.0)))}


func lines() -> Array:
	return data.get("lines", [])


func line(id: String) -> Dictionary:
	for l in lines():
		if str(l["id"]) == id:
			return l
	return {}


func has(unlock: String) -> bool:
	return bool(done.get(unlock, false))


func _kit() -> bool:
	var t = G.sys("tester")
	return t != null and t.portable_bench()


func road_table() -> bool:
	return has("table") or _kit()


func field_forge() -> bool:
	return has("forge") or _kit()


func rune_table() -> bool:
	return has("roll") or _kit()


func status(id: String) -> String:
	## done / active / open / locked
	if done.has(id):
		return "done"
	if act.has(id):
		return "active"
	for n in line(id).get("needs", []):
		if not done.has(str(n)):
			return "locked"
	return "open"


func missing_needs(id: String) -> Array:
	var out := []
	for n in line(id).get("needs", []):
		if not done.has(str(n)):
			out.append(str(line(str(n)).get("name", n)))
	return out


func start(id: String) -> String:
	if status(id) != "open":
		return ""
	if G.OnlineGen.is_online(str(G.current_level)):
		return I18n.t("This is not a thing for the online world.")
	if act.size() >= int(data.get("max_active", 2)):
		return I18n.t("You have two lines in hand. Finish or set one aside first.")
	act[id] = {"step": 0, "prog": 0.0}
	G.message.emit(I18n.t("WORKSHOP: %s begun.") % I18n.t(str(line(id)["name"])))
	G.log_event("workshop_start", {"id": id})
	G.stats_changed.emit()
	return I18n.t(str(line(id)["text"]))


func abandon(id: String) -> void:
	if act.erase(id):
		G.stats_changed.emit()


func cur(id: String) -> Dictionary:
	var a: Dictionary = act.get(id, {})
	if a.is_empty():
		return {}
	return line(id)["steps"][int(a["step"])]


func progress(id: String) -> Array:
	## [have, need] for the step in hand
	var s := cur(id)
	var a: Dictionary = act.get(id, {})
	match str(s.get("kind", "")):
		"give":
			var have := 0
			var need := 0
			for it in s["items"]:
				var n := int(s["items"][it])
				need += n
				have += mini(G.count(str(it)), n)
			return [have, need]
		"craft", "kills":
			return [mini(int(a.get("prog", 0.0)), int(s["count"])), int(s["count"])]
		"sit":
			return [mini(int(a.get("prog", 0.0)), int(s["minutes"])), int(s["minutes"])]
		"depth":
			return [mini(G.reach_depth(), int(s["floor"])), int(s["floor"])]
		"skill":
			return [mini(G.skill_level(str(s["skill"])), int(s["level"])), int(s["level"])]
		"inner":
			var IW = G.sys("inner_world")
			return [mini(IW.level() if IW != null else 0, int(s["level"])), int(s["level"])]
		"rank":
			var r: int = G.guild_rank(str(s["guild"]))
			return [mini(maxi(r + 1, 0), int(s["rank"]) + 1), int(s["rank"]) + 1]
	return [0, 1]


func ready(id: String) -> bool:
	if not act.has(id):
		return false
	var p := progress(id)
	return int(p[0]) >= int(p[1])


func items_text(s: Dictionary) -> String:
	var bits := []
	for it in s.get("items", {}):
		bits.append("%s x%d (%d)" % [G.item_name(str(it)), int(s["items"][it]), G.count(str(it))])
	return ", ".join(bits)


func hand_over(id: String) -> String:
	## the give step: take the items
	var s := cur(id)
	if str(s.get("kind", "")) != "give" or not ready(id):
		return ""
	for it in s["items"]:
		if G.count(str(it)) < int(s["items"][it]):
			return ""
	for it in s["items"]:
		G.remove_item(str(it), int(s["items"][it]))
	_advance(id)
	return I18n.t("You hand it over.")


func _advance(id: String) -> void:
	var ln := line(id)
	var a: Dictionary = act[id]
	var n: int = (ln["steps"] as Array).size()
	a["step"] = int(a["step"]) + 1
	a["prog"] = 0.0
	if int(a["step"]) >= n:
		_finish(id)
	else:
		G.message.emit(I18n.t("WORKSHOP: %s -- step %d of %d.") % [I18n.t(str(ln["name"])), int(a["step"]) + 1, n])
	G.stats_changed.emit()


func _finish(id: String) -> void:
	var ln := line(id)
	act.erase(id)
	done[id] = true
	var r: Dictionary = ln.get("reward", {})
	G.gain_insight(float(data.get("finish_insight", 6.0)) * float((ln["steps"] as Array).size()) / 5.0, str(ln["name"]))
	G.message.emit(I18n.t("WORKSHOP COMPLETE -- %s. %s") % [I18n.t(str(ln["name"])), I18n.t(str(r.get("text", "")))])
	G.log_event("workshop_done", {"id": id})
	G.bump("workshop_lines")


func effects() -> Array:
	var out := []
	for id in done:
		var e: Dictionary = line(str(id)).get("reward", {}).get("effects", {})
		if not e.is_empty():
			out.append(e)
	if has("seed"):
		var IW = G.sys("inner_world")
		if IW != null and IW.open() and IW.level() >= 5:
			out.append({"craft_success": 0.02})
	return out


func _auto() -> void:
	## the steps that are checked for you
	for id in act.keys():
		if not act.has(id):
			continue
		var k := str(cur(id).get("kind", ""))
		if k != "give" and ready(id):
			_advance(id)


func tick(delta: float) -> void:
	if act.is_empty():
		return
	if G.sitting:
		for id in act:
			if str(cur(str(id)).get("kind", "")) == "sit":
				act[id]["prog"] = float(act[id].get("prog", 0.0)) + delta / 60.0
	_acc += delta
	if _acc >= 2.0:
		_acc = 0.0
		_auto()


func on_event(kind: String, d: Dictionary) -> void:
	if act.is_empty() or G.OnlineGen.is_online(str(G.current_level)):
		return
	if kind == "kill":
		var en: Dictionary = G.enemies.get(str(d.get("type", "")), {})
		var fl := int(en.get("floor", en.get("depth", 0)))
		for id in act:
			var s := cur(str(id))
			if str(s.get("kind", "")) == "kills" and fl >= int(s.get("floor", 0)):
				act[id]["prog"] = float(act[id].get("prog", 0.0)) + 1.0
	elif (kind == "craft" or kind == "forge") and bool(d.get("success", false)):
		var mk := str(d.get("makes", ""))
		var sk: String = "smithing" if kind == "forge" else str(_skill_of.get(mk, ""))
		var df := int(_diff_of.get(mk, 40 if kind == "forge" else 0))
		for id in act:
			var s := cur(str(id))
			if str(s.get("kind", "")) != "craft":
				continue
			if int(s.get("min_diff", 0)) > df:
				continue
			if str(s.get("skill", "")) != "" and str(s["skill"]) != sk:
				continue
			act[id]["prog"] = float(act[id].get("prog", 0.0)) + 1.0
	_auto()
