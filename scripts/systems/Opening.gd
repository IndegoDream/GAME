extends "res://scripts/systems/GameSystem.gd"
## The opening (round 121). Robert: "first 30 minutes hook". The first half hour
## should hold a fight, a pickup, a choice and a reward, each one noticed.
## data/opening.json lists a handful of FIRST-TIMES -- first blood, first chest,
## first road (a Path chosen), first step up, first floor cleared, first great
## foe. Each one fires once per save, says so in one line, and pays something
## small (never enough to matter later). The line also says what comes next.
## Nothing here opens a window or blocks play.

var cfg := {}


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/opening.json", {})
	cfg = d if d is Dictionary else {}


func milestones() -> Array:
	return cfg.get("milestones", [])


func done(id: String) -> bool:
	return G.has_flag("op:" + id)


func count_done() -> int:
	var n := 0
	for m in milestones():
		if done(str(m.get("id", ""))):
			n += 1
	return n


func on_event(kind: String, data: Dictionary) -> void:
	for m in milestones():
		var id := str(m.get("id", ""))
		if str(m.get("ev", "")) != kind or done(id):
			continue
		if m.has("min_depth") and G.reach_depth() < int(m["min_depth"]):
			continue
		G.set_flag("op:" + id)
		_pay(m)


func _pay(m: Dictionary) -> void:
	var r: Dictionary = m.get("reward", {})
	var bits := []
	if r.has("qi"):
		G.add_qi(float(r["qi"]), I18n.t("a first time"))          # (the game says "+N qi" itself)
	if r.has("gold"):
		G.gold += int(r["gold"])
		bits.append(I18n.t("%d gold") % int(r["gold"]))
	for it in r.get("items", {}):
		G.add_item(str(it), int(r["items"][it]))          # (and I18n.t("+1 Healing Salve"))
	var line := str(m.get("text", ""))
	if bits.size() > 0:
		line += " (+" + ", ".join(bits) + ")"
	G.message.emit(line)
	if str(m.get("next", "")) != "":
		G.message.emit(str(m["next"]))
	G.log_event("opening", {"id": str(m.get("id", ""))})
	G.stats_changed.emit()
