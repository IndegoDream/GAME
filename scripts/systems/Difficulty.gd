extends "res://scripts/systems/GameSystem.gd"
## Round 139: your own difficulty. Robert, 2026-10-17: "being able to increase the difficulty as well so users can give
## themselves a penalty" -- a good idea if it stays honest, so:
##   - five tiers of FOE strength (Gentle ... Mythic); the harder ones pay more qi and more finds, the gentle one pays less
##   - three HANDICAPS you put on yourself (frail, dull, bare-handed), each paying a little
##   - changed only in the village, so it can't be swapped mid-fight to dodge a bad one
##   - the OFFLINE game only: online instances and the ladder run on the server's own numbers, so nobody climbs by choosing
##   - rewards are qi from kills and the chance of an extra find; never a stat. Standard changes nothing at all.
## data/difficulty.json.

var data := {}
var tier := "standard"
var handicaps := {}              # id -> true


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/difficulty.json")


func reset() -> void:
	tier = "standard"
	handicaps = {}


func save_state() -> Dictionary:
	return {"tier": tier, "handicaps": handicaps}


func load_state(d: Dictionary) -> void:
	reset()
	if _tier(str(d.get("tier", ""))).is_empty() == false:
		tier = str(d["tier"])
	var h = d.get("handicaps", {})
	if h is Dictionary:
		for k in h:
			if not _handicap(str(k)).is_empty() and bool(h[k]):
				handicaps[str(k)] = true


func _tier(tid: String) -> Dictionary:
	for t in data.get("tiers", []):
		if str(t.get("id", "")) == tid:
			return t
	return {}


func _handicap(hid: String) -> Dictionary:
	for t in data.get("handicaps", []):
		if str(t.get("id", "")) == hid:
			return t
	return {}


func tiers() -> Array:
	return data.get("tiers", [])


func handicap_list() -> Array:
	return data.get("handicaps", [])


func tier_def() -> Dictionary:
	return _tier(tier)


func foe_hp() -> float:
	return float(tier_def().get("foe_hp", 1.0))


func foe_damage() -> float:
	return float(tier_def().get("foe_damage", 1.0))


func reward() -> float:
	## the extra (or less) you earn: 0.0 on Standard
	var r := float(tier_def().get("reward", 0.0))
	for h in handicaps:
		r += float(_handicap(str(h)).get("reward", 0.0))
	return r


func is_standard() -> bool:
	return tier == "standard" and handicaps.is_empty()


func can_change() -> bool:
	return G.current_level == str(data.get("change_in", "village"))


func set_tier(tid: String) -> String:
	if _tier(tid).is_empty():
		return ""
	if not can_change():
		return I18n.t("Change this in the village, between trips.")
	tier = tid
	G.log_event("difficulty", {"tier": tid})
	G.stats_changed.emit()
	return I18n.t("Difficulty: %s.") % str(_tier(tid).get("name", tid))


func toggle_handicap(hid: String) -> String:
	if _handicap(hid).is_empty():
		return ""
	if not can_change():
		return I18n.t("Change this in the village, between trips.")
	if handicaps.has(hid):
		handicaps.erase(hid)
	else:
		handicaps[hid] = true
	G.log_event("handicap", {"id": hid, "on": handicaps.has(hid)})
	G.stats_changed.emit()
	return "%s: %s." % [str(_handicap(hid).get("name", hid)), "on" if handicaps.has(hid) else "off"]


func effects() -> Array:
	var out := []
	for h in handicaps:
		var fx = _handicap(str(h)).get("fx", {})
		if fx is Dictionary:
			out.append(fx)
	return out
