extends "res://scripts/systems/GameSystem.gd"
## The end of a life (round 121). When you fall, a card says what that life
## did (foes, floors, chests, depth, minutes), what you were nearly at, and
## one thing worth trying -- the next life is the "one more run" hook.
## It never blocks play (HUD queues big_moments until nothing else is open),
## and a quick death (under min_seconds_for_card and no kills) gets no card.

var cfg := {}
var life := {}                    # counters since you last woke
var last := {}                    # the last summary (title, body) -- the Road page can show it
var _tip_i := 0


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/lives.json", {})
	cfg = d if d is Dictionary else {}
	_new_life()


func reset() -> void:
	last = {}
	_tip_i = 0
	_new_life()


func _new_life() -> void:
	life = {"start": G.playtime if G != null else 0.0, "kills": 0, "bosses": 0, "elites": 0, "floors": 0, "chests": 0, "steps": 0, "shots": 0, "arts": 0, "deepest": 0}


func save_state() -> Dictionary:
	return {"life": life, "last": last, "tip_i": _tip_i}


func load_state(d: Dictionary) -> void:
	var l = d.get("life", {})
	life = l if l is Dictionary and not (l as Dictionary).is_empty() else {}
	if life.is_empty():
		_new_life()
	var la = d.get("last", {})
	last = la if la is Dictionary else {}
	_tip_i = int(d.get("tip_i", 0))


func _bump(k: String) -> void:
	life[k] = int(life.get(k, 0)) + 1


func on_event(kind: String, data: Dictionary) -> void:
	life["deepest"] = maxi(int(life.get("deepest", 0)), G.depth)
	match kind:
		"kill":
			_bump("kills")
		"boss_kill":
			_bump("bosses")
		"elite_kill":
			_bump("elites")
		"floor_cleared":
			_bump("floors")
		"chest":
			_bump("chests")
		"levelup":
			_bump("steps")
		"shot":
			_bump("shots")
		"path_art":
			_bump("arts")
		"death":
			_on_death(str(data.get("cause", "")))


func minutes() -> int:
	return int(round(maxf(G.playtime - float(life.get("start", 0.0)), 0.0) / 60.0))


func _tip_for(cause: String) -> String:
	var low := cause.to_lower()
	for t in cfg.get("tips", []):
		for w in t.get("words", []):
			if low.contains(str(w)):
				return str(t.get("text", ""))
	var gt: Array = cfg.get("general_tips", [])
	if gt.is_empty():
		return ""
	var s := str(gt[_tip_i % gt.size()])
	_tip_i += 1
	return s


func _nearly() -> String:
	## the closest thing you were to: a step, a quest, or your Path's next rank
	var a: String = G.almost()
	if a != "":
		return a
	var P = G.sys("paths")
	if P != null and P.primary != "":
		var nn: Dictionary = P.next_needs(P.primary)
		var best := ""
		var bf := -1.0
		for n in nn.get("needs", []):
			var f := float(n["have"]) / maxf(float(n["need"]), 1.0)
			if f < 1.0 and f > bf:
				bf = f
				best = I18n.t("%s: %d of %d for %s (%s)") % [str(n["label"]), int(n["have"]), int(n["need"]), str(nn["name"]), str(P.def(P.primary).get("name", ""))]
		if best != "" and bf >= 0.3:
			return I18n.t("Nearly: ") + best
	return ""


func summary(cause: String = "") -> Dictionary:
	var lines := []
	var mins := minutes()
	var l := I18n.t("You lasted %d minute%s") % [mins, "" if mins == 1 else "s"]
	if int(life.get("deepest", 0)) > 0:
		l += I18n.t(", down to floor %d") % int(life["deepest"])
	lines.append(l + ".")
	var bits := []
	if int(life.get("kills", 0)) > 0:
		var k := I18n.t("%d foe%s felled") % [int(life["kills"]), "" if int(life["kills"]) == 1 else "s"]
		var extra := []
		if int(life.get("bosses", 0)) > 0:
			extra.append(I18n.t("%d great") % int(life["bosses"]))
		if int(life.get("elites", 0)) > 0:
			extra.append(I18n.t("%d elite") % int(life["elites"]))
		if extra.size() > 0:
			k += " (" + ", ".join(extra) + ")"
		bits.append(k)
	if int(life.get("floors", 0)) > 0:
		bits.append(I18n.t("%d floor%s cleared") % [int(life["floors"]), "" if int(life["floors"]) == 1 else "s"])
	if int(life.get("chests", 0)) > 0:
		bits.append(I18n.t("%d chest%s opened") % [int(life["chests"]), "" if int(life["chests"]) == 1 else "s"])
	if int(life.get("steps", 0)) > 0:
		bits.append(I18n.t("%d step%s up") % [int(life["steps"]), "" if int(life["steps"]) == 1 else "s"])
	if int(life.get("arts", 0)) > 0:
		bits.append(I18n.t("your art used %d time%s") % [int(life["arts"]), "" if int(life["arts"]) == 1 else "s"])
	if bits.size() > 0:
		lines.append(", ".join(bits) + ".")
	if cause != "":
		lines.append(I18n.t("What brought you down: %s.") % cause)
	var n := _nearly()
	if n != "":
		lines.append(n)
	var tip := _tip_for(cause)
	if tip != "":
		lines.append("")
		lines.append(I18n.t("Try: ") + tip)
	return {"title": str(cfg.get("title", "This life, in short")), "body": "\n".join(lines)}


func _on_death(cause: String) -> void:
	var quick: bool = G.playtime - float(life.get("start", 0.0)) < float(cfg.get("min_seconds_for_card", 20)) and int(life.get("kills", 0)) == 0
	last = summary(cause)
	if not quick:
		G.big_moment.emit(str(last["title"]), str(last["body"]))
	_new_life()
