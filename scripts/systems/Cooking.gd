extends "res://scripts/systems/GameSystem.gd"
## Round 164: cooking. Robert, 2026-10-19: "Yes add them all".
## Fish, meat and herbs become meals (data/cooking.json): each heals and gives a buff for a while. A meal is an ordinary
## consumable, eaten from the bag (Game.use_item already knows "buff"), so several different meals can run together.
## A town's hearth is enough (anywhere with the test kit). Survival stretches how long a meal lasts. Never sold for power.

var data := {}
var made := {}            # meal id -> times cooked
var total := 0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/cooking.json")
	for m in data.get("meals", []):
		var id := str(m["id"])
		G.items[id] = {"name": m["name"], "type": "consumable", "heal": int(m.get("heal", 0)), "value": int(m.get("value", 30)),
			"desc": m.get("desc", ""), "buff": (m["buff"] as Dictionary).duplicate(true), "meal": true}
		G.buff_names[id] = str(m["name"])


func reset() -> void:
	made = {}
	total = 0


func save_state() -> Dictionary:
	return {"made": made, "total": total}


func load_state(d: Dictionary) -> void:
	reset()
	for k in d.get("made", {}):
		made[str(k)] = int(d["made"][k])
	total = int(d.get("total", 0))


func meals() -> Array:
	return data.get("meals", [])


func meal(id: String) -> Dictionary:
	for m in meals():
		if str(m["id"]) == id:
			return m
	return {}


func why_not(id: String) -> String:
	var m := meal(id)
	if m.is_empty():
		return I18n.t("No such meal.")
	if not (G.havens.has(G.current_level) or G.tester_unlocked()):
		return I18n.t("Cook at a hearth -- in any town.")
	for it in m["needs"]:
		if G.count(str(it)) < int(m["needs"][it]):
			return I18n.t("You need %d %s.") % [int(m["needs"][it]), G.item_name(str(it))]
	return ""


func needs_text(id: String) -> String:
	var m := meal(id)
	var bits := []
	for it in m.get("needs", {}):
		bits.append("%d %s (%d)" % [int(m["needs"][it]), G.item_name(str(it)), G.count(str(it))])
	return ", ".join(bits)


func stretch() -> float:
	return 1.0 + minf(float(data.get("stretch_cap", 0.5)), float(data.get("stretch_per_level", 0.02)) * float(G.skill_level("survival")))


func cook(id: String) -> String:
	var why := why_not(id)
	if why != "":
		return why
	var m := meal(id)
	for it in m["needs"]:
		G.remove_item(str(it), int(m["needs"][it]))
	G.add_item(id, 1)
	made[id] = int(made.get(id, 0)) + 1
	total += 1
	G.add_skill_xp("survival", float(data.get("xp", 6)), "cooking")
	G.log_event("cook", {"meal": id})
	G.message.emit(I18n.t("You cook %s.") % I18n.t(str(m["name"])))
	G.stats_changed.emit()
	return ""


func lines(id: String) -> String:
	var m := meal(id)
	var secs := int(float(m["buff"].get("seconds", 600)) * stretch())
	return I18n.t(str(m.get("desc", ""))) + "  (" + G._dur(float(secs)) + ")"
