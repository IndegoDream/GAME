extends "res://scripts/systems/GameSystem.gd"
## Factions that remember (round 44). Robert, 2026-10-04: "bring more depth to
## the world ... factions that remember ... a sense of continuity."
##
## Five peoples with a standing toward you (-1000 .. 1000), shown as a tier
## (Hated .. Revered): the Village of Eliet, the Deepfolk, the Hollow Clans,
## the Heirs of the Makers, the Valley Sects. They have rivals -- help the
## Deepfolk and the Hollow Clans think less of you; give a relic to the Heirs
## and the Sects take note -- so every choice is a choice.
## What standing does:
##   * their traders' prices (Wary: dearer; Hostile: they won't trade; Trusted
##     and up: cheaper, and better stock)
##   * gifts at each tier (a free inn, research shared, bonds that grow faster)
##   * the Hollow Clans' hunters come after you on the floors if you've made
##     enemies of them
##   * their banners: a people who trust you fly their colours where you live
## Standing comes from what you already do (data/factions.json "events":
## quests, sect trials, research, settlements helped, relics given ...).

var data := {}
var standing := {}        # faction id -> number
var history := []         # [{"f", "by", "why", "day"}], newest last (kept to 60)


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/factions.json")
	var dr = G._load_json("res://data/drafts/factions.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and data.get("factions", {}).has(str(it.get("id", ""))) and str(it.get("text", "")).strip_edges() != "":
				data["factions"][str(it["id"])]["desc"] = str(it["text"]).strip_edges()
	reset()


func reset() -> void:
	standing = {}
	history = []
	for fid in data.get("factions", {}):
		standing[fid] = float(data["factions"][fid].get("start", 0))


func save_state() -> Dictionary:
	return {"standing": standing, "history": history}


func load_state(d: Dictionary) -> void:
	reset()
	var s = d.get("standing", {})
	if s is Dictionary:
		for k in s:
			if standing.has(str(k)):
				standing[str(k)] = float(s[k])
	history = []
	for h in (d.get("history", []) if d.get("history", []) is Array else []):
		if h is Dictionary:
			var hh: Dictionary = (h as Dictionary).duplicate()
			hh["day"] = int(hh.get("day", 0))        # (JSON brings numbers back as floats)
			history.append(hh)


func ids() -> Array:
	var out: Array = data.get("factions", {}).keys()
	return out


func fdef(fid: String) -> Dictionary:
	return data.get("factions", {}).get(fid, {})


func name_of(fid: String) -> String:
	return str(fdef(fid).get("name", fid))


func value(fid: String) -> float:
	return float(standing.get(fid, 0.0))


func tier(fid: String) -> Dictionary:
	var v := value(fid)
	var best: Dictionary = {}
	for t in data.get("tiers", []):
		if v >= float(t.get("from", -INF)):
			best = t
	return best


func tier_id(fid: String) -> String:
	return str(tier(fid).get("id", "neutral"))


func tier_index(tid: String) -> int:
	var ts: Array = data.get("tiers", [])
	for i in ts.size():
		if str(ts[i].get("id", "")) == tid:
			return i
	return -1


func at_least(fid: String, tid: String) -> bool:
	return tier_index(tier_id(fid)) >= tier_index(tid)


func next_tier(fid: String) -> Dictionary:
	var i := tier_index(tier_id(fid))
	var ts: Array = data.get("tiers", [])
	return ts[i + 1] if i + 1 < ts.size() else {}


func change(fid: String, by: float, why: String = "", spill: bool = true) -> void:
	## standing up (or down); the rival feels a share of it the other way
	if not standing.has(fid) or by == 0.0:
		return
	var before := tier_id(fid)
	standing[fid] = clampf(value(fid) + by, float(data.get("min", -1000)), float(data.get("max", 1000)))
	history.append({"f": fid, "by": snappedf(by, 0.1), "why": why, "day": G.sys("world").day() if G.sys("world") else 0})
	if history.size() > 60:
		history = history.slice(history.size() - 60)
	var after := tier_id(fid)
	if after != before:
		var t := tier(fid)
		var up := tier_index(after) > tier_index(before)
		G.message.emit(I18n.t("%s: %s now %s you%s.") % [(I18n.t("STANDING UP") if up else I18n.t("STANDING DOWN")), name_of(fid), ("count you as " + str(t.get("name", "")).to_lower()) if up else "are " + str(t.get("name", "")).to_lower() + " toward",
			("" if not up else ((" -- " + str(fdef(fid).get("gifts", {}).get(after, ""))) if str(fdef(fid).get("gifts", {}).get(after, "")) != "" else ""))])
		G.log_event("faction_tier", {"faction": fid, "tier": after, "up": up})
	var rival := str(fdef(fid).get("rival", ""))
	if spill and rival != "" and by > 0.0:
		change(rival, -by * float(data.get("rival_share", 0.5)), I18n.t("you helped ") + str(fdef(fid).get("short", fid)), false)
	G.stats_changed.emit()


func on_event(kind: String, d: Dictionary) -> void:
	var ev: Dictionary = data.get("events", {}).get(kind, {})
	for fid in ev:
		change(str(fid), float(ev[fid]), kind.replace("_", " "))


# ---- what standing does ----------------------------------------------------------------------

func place_faction(level_id: String) -> String:
	return str(data.get("places", {}).get(level_id, ""))


func price_mult(fid: String) -> float:
	## their traders: 0 = they won't trade with you
	if fid == "" or not standing.has(fid):
		return 1.0
	return float(tier(fid).get("price", 1.0))


func extra_stock(fid: String) -> Array:
	var out := []
	var st: Dictionary = fdef(fid).get("stock", {})
	for tid in st:
		if at_least(fid, str(tid)):
			for id in st[tid]:
				if G.has_item_def(str(id)) and not (str(id) in out):
					out.append(str(id))
	return out


func gift_lines(fid: String) -> Array:
	var out := []
	var gf: Dictionary = fdef(fid).get("gifts", {})
	for t in data.get("tiers", []):
		var tid := str(t.get("id", ""))
		if gf.has(tid):
			out.append([str(t.get("name", "")), str(gf[tid]), at_least(fid, tid)])
	return out


func effects() -> Array:
	var out := []
	for fid in standing:
		var ef: Dictionary = fdef(str(fid)).get("effect", {})
		var best := {}
		for tid in ef:
			if at_least(str(fid), str(tid)) and (best.is_empty() or tier_index(str(tid)) > tier_index(str(best.get("_t", "")))):
				best = (ef[tid] as Dictionary).duplicate()
				best["_t"] = str(tid)
		if not best.is_empty():
			best.erase("_t")
			out.append(best)
	return out


func inn_free() -> bool:
	return at_least("eliet", "trusted")


func camp_rest_free() -> bool:
	return at_least("deepfolk", "trusted")


func hunters_hunting() -> bool:
	var h: Dictionary = fdef("hollow").get("hunters", {})
	if h.is_empty():
		return false
	return tier_index(tier_id("hollow")) < tier_index(str(h.get("below", "wary")))


func hunters_for(level_id: String, level_def: Dictionary) -> int:
	## how many clan hunters are waiting on this floor today (0 = none)
	var h: Dictionary = fdef("hollow").get("hunters", {})
	if not hunters_hunting() or int(level_def.get("depth", 0)) < int(h.get("min_depth", 7)) or str(level_def.get("theme", "")) in ["village", "settlement"] \
			or bool(level_def.get("trial", false)) or bool(level_def.get("arena", false)):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunters|%s|%d" % [level_id, G.sys("world").day() if G.sys("world") else 0])
	return int(h.get("count", 3)) if rng.randf() < float(h.get("chance", 0.35)) else 0


func standing_text(fid: String) -> String:
	var t := tier(fid)
	var nt := next_tier(fid)
	return "%s (%d)%s" % [str(t.get("name", "")), int(value(fid)), ("  ·  %d to %s" % [int(float(nt.get("from", 0)) - value(fid)), str(nt.get("name", ""))]) if not nt.is_empty() else ""]


func define_faction_effects(fid: String = "", custom_effects: Dictionary = {}) -> Dictionary:
	var res: Dictionary = custom_effects.duplicate()
	var fids: Array = [fid] if (fid != "" and standing.has(fid)) else ids()
	for f in fids:
		var f_str := str(f)
		var f_info := {
			"faction": f_str,
			"tier": tier_id(f_str),
			"standing": value(f_str),
			"price_mult": price_mult(f_str),
			"extra_stock": extra_stock(f_str),
			"inn_free": (f_str == "eliet" and inn_free()),
			"camp_free": (f_str == "deepfolk" and camp_rest_free()),
			"hunters_hunting": (f_str == "hollow" and hunters_hunting()),
		}
		res[f_str] = f_info
	return res


func apply_faction_effects(target = null, fid: String = "") -> Dictionary:
	var base_dict: Dictionary = {}
	if target is Dictionary:
		base_dict = target.duplicate()
	var res: Dictionary = base_dict.duplicate()
	var active_effects: Array = []
	if fid != "" and standing.has(fid):
		var ef: Dictionary = fdef(fid).get("effect", {})
		var best: Dictionary = {}
		for tid in ef:
			if at_least(fid, str(tid)) and (best.is_empty() or tier_index(str(tid)) > tier_index(str(best.get("_t", "")))):
				best = (ef[tid] as Dictionary).duplicate()
				best["_t"] = str(tid)
		if not best.is_empty():
			best.erase("_t")
			active_effects.append(best)
	else:
		active_effects = effects()

	for ef in active_effects:
		if ef is Dictionary:
			for k in ef:
				var val = ef[k]
				if val is float or val is int:
					res[k] = float(res.get(k, 0.0)) + float(val)
				else:
					res[k] = val
	return res
