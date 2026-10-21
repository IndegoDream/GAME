extends "res://scripts/systems/GameSystem.gd"
## Round 162: today's three goals (a card in the Quests page). Robert, 2026-10-19: "Yes add them all".
## Three small things, a different mix every real day, counted from what you do. Each pays a little gold and insight; all
## three pay a bonus; finishing all three on consecutive days builds a streak. It never takes anything away and nothing is sold.

var data := {}
var day := ""
var list := []             # [{"id","text","need","have","done"}]
var streak := 0
var last_all := ""         # the last day all three were done
var total_done := 0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/goals.json")


func reset() -> void:
	day = ""
	list = []
	streak = 0
	last_all = ""
	total_done = 0


func save_state() -> Dictionary:
	return {"day": day, "list": list, "streak": streak, "last_all": last_all, "total": total_done}


func load_state(d: Dictionary) -> void:
	reset()
	day = str(d.get("day", ""))
	for g in d.get("list", []):
		list.append({"id": str(g.get("id", "")), "text": str(g.get("text", "")), "need": int(g.get("need", 1)),
			"have": float(g.get("have", 0.0)), "done": bool(g.get("done", false))})
	streak = int(d.get("streak", 0))
	last_all = str(d.get("last_all", ""))
	total_done = int(d.get("total", 0))


func _def(id: String) -> Dictionary:
	for p in data.get("pool", []):
		if str(p.get("id", "")) == id:
			return p
	return {}


func goals() -> Array:
	if day != G.today() or list.is_empty():
		roll(G.today())
	return list


func roll(for_day: String) -> void:
	day = for_day
	list = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(for_day + "goals")
	var depth: int = G.reach_depth()
	var pool: Array = (data.get("pool", []) as Array).duplicate()
	var cats := {}
	var guard := 0
	while list.size() < 3 and not pool.is_empty() and guard < 80:
		guard += 1
		var p: Dictionary = pool[rng.randi() % pool.size()]
		if bool(p.get("rare", false)) and rng.randf() > 0.25:
			continue
		if cats.has(str(p.get("cat", ""))) and guard < 40:
			continue                                   # a mix: no two of one kind while there is a choice
		cats[str(p.get("cat", ""))] = true
		pool.erase(p)
		var need := int(round(float(p.get("need", 1)) + float(p.get("per_depth", 0.0)) * float(depth)))
		var txt := str(p.get("text", ""))
		list.append({"id": str(p["id"]), "text": txt, "need": maxi(1, need), "have": 0.0, "done": false})


func text_of(g: Dictionary) -> String:
	var t := I18n.t(str(g.get("text", "")))
	return t % int(g["need"]) if t.find("%d") >= 0 else t


func progress(g: Dictionary) -> int:
	return mini(int(g.get("have", 0.0)), int(g.get("need", 1)))


func all_done() -> bool:
	for g in goals():
		if not bool(g.get("done", false)):
			return false
	return true


func _count(id: String, n: float) -> void:
	goals()
	for g in list:
		if str(g["id"]) == id and not bool(g["done"]):
			g["have"] = float(g["have"]) + n
			if int(g["have"]) >= int(g["need"]):
				_finish(g)


func on_event(kind: String, d: Dictionary) -> void:
	if data.is_empty():
		return
	goals()
	for g in list:
		if bool(g["done"]):
			continue
		var df := _def(str(g["id"]))
		if (df.get("events", []) as Array).has(kind):
			if bool(df.get("success", false)) and not bool(d.get("success", false)):
				continue
			_count(str(g["id"]), 1.0)


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	if data.is_empty():
		return
	_count("sit", secs / 60.0)


func _finish(g: Dictionary) -> void:
	g["done"] = true
	total_done += 1
	var depth: int = G.reach_depth()
	var gold := int(data.get("gold_base", 20)) + int(data.get("gold_per_depth", 8)) * depth
	G.add_item("gold", gold, false)
	G.gain_insight(float(data.get("insight", 1.0)), "today's goals")
	G.message.emit(I18n.t("GOAL DONE: %s -- %d gold.") % [text_of(g), gold])
	if all_done():
		var bonus := int(data.get("bonus_base", 60)) + int(data.get("bonus_per_depth", 20)) * depth
		G.add_item("gold", bonus, false)
		var yesterday := Time.get_date_string_from_unix_time(int(G._now()) - 86400 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
		streak = streak + 1 if last_all == yesterday else 1
		last_all = day
		G.message.emit(I18n.t("ALL THREE DONE -- a bonus of %d gold%s.") % [bonus, (I18n.t(" (day %d in a row)") % streak) if streak > 1 else ""])
		G.log_event("goals_all", {"streak": streak})
	G.stats_changed.emit()
