extends "res://scripts/systems/GameSystem.gd"
## The Balance (round 119). Robert, 2026-10-13: "Allow for guidance in how to
## balance all aspects maybe this is part of the ultimate legacy inheritance.
## The ultimate quest could provide an easy passage through danger to achieve
## the same thing. Both quest must be worked on to an extent there can only be
## a 50% disparity before it starts hurting game play but can be done if
## maximizing potential."
##
## main road   = the story's chapters done (Game.mq)
## legacy road = how far along the masters' task lines are, over the seats
##               you have come across (a task line you never met is not held
##               against you)
## gap <= limit: nothing. Past it: Imbalance (less qi, slower sitting, a little
## harder foes), growing to its cap and gone again as the roads draw level.
## Holding the ultimate legacy (the technique the_balance) also shows the
## aspect gauges with a hint for the weakest, and, with the roads within the
## limit and the legacy road begun, gives the Even Road: an easier passage
## through danger. Numbers: data/balance.json.

var cfg := {}
var seats := {}                  # inheritance key -> tier, the ones you have met
var _t := 0.0
var _main := 0.0
var _leg := -1.0
var _imb := 0.0
var _even := false
var _fx: Array = []


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/balance.json", {})
	cfg = d if d is Dictionary else {}
	_recompute()


func reset() -> void:
	seats = {}
	_recompute()


func save_state() -> Dictionary:
	return {"seats": seats}


func load_state(d: Dictionary) -> void:
	var s = d.get("seats", {})
	seats = s if s is Dictionary else {}
	_recompute()


func note_seat(key: String, tier: String) -> void:
	if not seats.has(key):
		seats[key] = tier
		_recompute()


func holds() -> bool:
	return G.has_tech("the_balance")


func main_pct() -> float:
	var n: int = G.mq_chapters().size()
	return 100.0 * float(G.mq_index()) / float(maxi(1, n))


func legacy_pct() -> float:
	## -1 when you have met no seat yet
	if seats.is_empty():
		return -1.0
	var Q = G.sys("quests")
	if Q == null:
		return -1.0
	var tot := 0.0
	for key in seats:
		var qid := "legacy:" + str(key)
		if Q.done.has(qid):
			tot += 1.0
		elif Q.active.has(qid):
			var n: int = Q.qdef(qid).get("stages", []).size()
			tot += float(int(Q.active[qid].get("stage", 0))) / float(maxi(1, n))
	return 100.0 * tot / float(seats.size())


func gap() -> float:
	return 0.0 if _leg < 0.0 else absf(_main - _leg)


func limit() -> float:
	return float(cfg.get("limit", 50))


func imbalance() -> float:
	return _imb


func even_road() -> bool:
	return _even


func _recompute() -> void:
	_main = main_pct()
	_leg = legacy_pct()
	var over := maxf(0.0, gap() - limit())
	_imb = clampf(over / maxf(1.0, float(cfg.get("span", 50))), 0.0, 1.0)
	_even = holds() and _leg > 0.0 and gap() <= limit()
	_fx = []
	if _imb > 0.0:
		var c: Dictionary = cfg.get("imbalance", {})
		_fx.append({"qi_mult": 1.0 - float(c.get("qi_mult", 0.3)) * _imb,
			"meditate_mult": 1.0 - float(c.get("meditate_mult", 0.3)) * _imb,
			"damage_taken": 1.0 + float(c.get("foe_damage", 0.15)) * _imb})
	if _even:
		_fx.append((cfg.get("even_road", {}) as Dictionary).duplicate())


func refresh() -> void:
	_recompute()


func tick(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 2.0
		var before := _imb
		_recompute()
		if _imb > 0.0 and before <= 0.0:
			G.message.emit("IMBALANCE: your two roads have drifted far apart. Walk the one you have neglected and it passes.")
		elif _imb <= 0.0 and before > 0.0:
			G.message.emit("The roads draw level again. The Imbalance lifts.")


func effects() -> Array:
	return _fx


func aspects() -> Dictionary:
	## aspect id -> 0..1
	var cap := float(cfg.get("skill_cap", 10))
	var body := 0.0
	var bs: Array = cfg.get("body_skills", [])
	for s in bs:
		body = maxf(body, float(G.skill_level(str(s))) / cap)
	var craft := 0.0
	var cs: Array = cfg.get("craft_skills", [])
	for s2 in cs:
		craft += float(G.skill_level(str(s2))) / cap
	craft = craft / float(maxi(1, cs.size())) * 2.0
	var lore := 0.0
	var Lo = G.sys("lore")
	if Lo and "history_found" in Lo and "data" in Lo:
		lore = float(Lo.history_found.size()) / float(maxi(1, (Lo.data.get("history", []) as Array).size()))
	var rank := 0.0
	for gid in G.guilds:
		rank += float(G.guild_rank(gid)) / 4.0
	var standing := rank / float(maxi(1, G.guilds.size())) if not G.guilds.is_empty() else 0.0
	return {"body": clampf(body, 0.0, 1.0), "qi": clampf(float(G.realm) / 12.0, 0.0, 1.0), "craft": clampf(craft, 0.0, 1.0),
		"lore": clampf(lore, 0.0, 1.0), "standing": clampf(standing, 0.0, 1.0),
		"wealth": clampf(float(G.count("gold")) / (float(cfg.get("gold_per_floor", 400)) * float(maxi(1, G.reach_depth()))), 0.0, 1.0),
		"exploration": clampf(float(G.reach_depth()) / 50.0, 0.0, 1.0)}


func weakest() -> String:
	var a := aspects()
	var best := ""
	var bv := 2.0
	for k in a:
		if float(a[k]) < bv:
			bv = float(a[k])
			best = str(k)
	return best


func hint_line() -> String:
	var w := weakest()
	if w == "":
		return ""
	var c: Dictionary = cfg.get("aspects", {}).get(w, {})
	return I18n.t("Weakest: %s. %s") % [str(c.get("name", w)), str(c.get("hint", ""))]
