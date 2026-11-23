extends "res://scripts/systems/GameSystem.gd"
## Round 145: a herb garden. Robert, 2026-10-18: "do them all" -- something quiet for the cozy player.
## Three plots at your lodging (any town). Plant one herb in a plot, come back later (real time, it grows while you're away or the game is
## closed), pick two. A day's cap on how much you can pick keeps it a pastime, not an income. data/garden.json.

var data := {}
var plots := []            # [{"herb": id, "ready": unix} or {}]
var day := ""
var picked_today := 0
var day_override := ""     # tests
var now_override := -1.0   # tests


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/garden.json")
	reset()


func reset() -> void:
	plots = []
	for i in int(data.get("plots", 3)):
		plots.append({})
	day = ""
	picked_today = 0


func save_state() -> Dictionary:
	return {"plots": plots, "day": day, "picked": picked_today}


func load_state(d: Dictionary) -> void:
	reset()
	var p = d.get("plots", [])
	if p is Array:
		for i in mini(p.size(), plots.size()):
			var e = p[i]
			if e is Dictionary and str(e.get("herb", "")) != "" and not herb_def(str(e["herb"])).is_empty():
				plots[i] = {"herb": str(e["herb"]), "ready": float(e.get("ready", 0.0))}
	day = str(d.get("day", ""))
	picked_today = int(d.get("picked", 0))


func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


func _roll_day() -> void:
	var t: String = day_override if day_override != "" else str(G.today())
	if day != t:
		day = t
		picked_today = 0


func herb_def(id: String) -> Dictionary:
	for h in data.get("herbs", []):
		if str(h.get("id", "")) == id:
			return h
	return {}


func herbs() -> Array:
	return (data.get("herbs", []) as Array).filter(func(h): return G.items.has(str(h["id"])))


func in_town() -> bool:
	var tr = G.sys("travel")
	return tr != null and tr.is_town(str(G.current_level))


func state(i: int) -> String:
	## "empty" / "growing" / "ready"
	var p: Dictionary = plots[i]
	if p.is_empty():
		return "empty"
	return "ready" if _now() >= float(p["ready"]) else "growing"


func minutes_left(i: int) -> int:
	var p: Dictionary = plots[i]
	if p.is_empty():
		return 0
	return maxi(0, int(ceil((float(p["ready"]) - _now()) / 60.0)))


func plant(i: int, herb: String) -> String:
	if i < 0 or i >= plots.size() or herb_def(herb).is_empty():
		return ""
	if not in_town():
		return I18n.t("The garden is at your lodging, in town.")
	if state(i) != "empty":
		return I18n.t("That plot is already in use.")
	if G.count(herb) < 1:
		return I18n.t("You have none of those to plant.")
	if not G.remove_item(herb, 1):
		return ""
	plots[i] = {"herb": herb, "ready": _now() + float(herb_def(herb).get("minutes", 180)) * 60.0}
	G.log_event("garden_plant", {"herb": herb})
	G.stats_changed.emit()
	return I18n.t("You plant %s. It will be ready in about %d minutes.") % [G.item_name(herb), int(herb_def(herb).get("minutes", 180))]


func pick(i: int) -> String:
	_roll_day()
	if i < 0 or i >= plots.size() or state(i) != "ready":
		return ""
	if not in_town():
		return I18n.t("The garden is at your lodging, in town.")
	var cap := int(data.get("daily_pick_cap", 6))
	var each := int(data.get("yield", 2))
	if picked_today + each > cap:
		return I18n.t("You have picked enough for today. The rest keeps until tomorrow.")
	var herb := str(plots[i]["herb"])
	plots[i] = {}
	picked_today += each
	G.add_item(herb, each, false)
	G.bump("garden_picks")
	G.log_event("garden_pick", {"herb": herb})
	G.stats_changed.emit()
	return I18n.t("GARDEN: you pick %d x %s.") % [each, G.item_name(herb)]
