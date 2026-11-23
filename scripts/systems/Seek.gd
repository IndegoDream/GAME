extends "res://scripts/systems/GameSystem.gd"
## Round 155 (Robert: "one human companion to follow at most, both slots can be used to search for items and
## reagents, plants, jewels and shards"). Only the first human companion walks with you; the second waits at camp.
## EITHER one can be sent to search for plants, reagents, jewels or shards for 1-8 real hours (the clock runs while the
## game is closed). Deeper floors you have reached open richer finds. The state lives on the companion's own record
## (`search`), so it is saved with them and travels if you swap places.

var cfg := {}
var _t := 0.0


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/seek.json", {})
	cfg = d if d is Dictionary else {}


func kinds() -> Dictionary:
	return cfg.get("kinds", {})


func hours() -> Array:
	return cfg.get("hours", [1, 2, 4, 8])


func state(slot: int) -> Dictionary:
	var s = G.cslot(slot).get("search", {})
	return s if s is Dictionary else {}


func searching(slot: int) -> bool:
	return not state(slot).is_empty()


func left(slot: int) -> float:
	var s := state(slot)
	return maxf(0.0, float(s.get("end", 0.0)) - G._now()) if not s.is_empty() else 0.0


func block(slot: int, kind: String) -> String:
	var c: Dictionary = G.cslot(slot)
	if c.is_empty():
		return I18n.t("Nobody is in that place.")
	if not kinds().has(kind):
		return I18n.t("No such search.")
	if searching(slot):
		return I18n.t("%s is already out searching.") % str(c.get("name", ""))
	if bool(c.get("away", false)):
		return I18n.t("%s is away on an expedition.") % str(c.get("name", ""))
	return ""


func start(slot: int, kind: String, hrs: float) -> String:
	var why := block(slot, kind)
	if why != "":
		return why
	var c: Dictionary = G.cslot(slot)
	var now: float = G._now()
	c["search"] = {"kind": kind, "start": now, "end": now + hrs * 3600.0, "hours": hrs}
	c["away"] = true
	G.log_event("search_start", {"who": str(c.get("name", "")), "kind": kind})
	G.message.emit(I18n.t("%s sets out to search for %s. Back in %s.") % [str(c.get("name", "")), I18n.t(str(kinds()[kind].get("name", kind))).to_lower(), G._dur(hrs * 3600.0)])
	G.companion_changed.emit()
	G.stats_changed.emit()
	return ""


func pool(kind: String) -> Array:
	## [[item, weight]] for what the deepest floor you have reached opens
	var out := []
	var tw: Array = cfg.get("tier_weights", [1.0])
	var depth: int = G.reach_depth()
	var ti := 0
	for tier in kinds().get(kind, {}).get("tiers", []):
		if depth >= int(tier.get("depth", 1)):
			for id in tier.get("items", []):
				if G.items.has(str(id)):
					out.append([str(id), float(tw[mini(ti, tw.size() - 1)])])
		ti += 1
	return out


func finish(slot: int) -> Array:
	var c: Dictionary = G.cslot(slot)
	var s := state(slot)
	if c.is_empty() or s.is_empty():
		return []
	var nm := str(c.get("name", ""))
	var kind := str(s.get("kind", "plants"))
	var hrs: float = float(s.get("hours", 1.0))
	var warm: float = float(G.bond(nm).get("warmth", 0.0))
	var rolls: int = maxi(1, int(round(hrs * float(cfg.get("rolls_per_hour", 2.5)) * (1.0 + warm / float(cfg.get("warmth_bonus", 300.0))))))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(float(s.get("start", 0.0))) + slot * 31
	var pl: Array = pool(kind)
	var got := {}
	var total := 0.0
	for p in pl:
		total += float(p[1])
	for i in rolls:
		if pl.is_empty():
			break
		var r: float = rng.randf() * total
		var pick := str(pl[0][0])
		for p in pl:
			r -= float(p[1])
			if r <= 0.0:
				pick = str(p[0])
				break
		got[pick] = int(got.get(pick, 0)) + rng.randi_range(1, 2)
	var parts := []
	for id in got:
		G.add_item(str(id), int(got[id]), false)
		parts.append("%d %s" % [int(got[id]), G.item_name(str(id))])
	c.erase("search")
	c.erase("away")
	G.warm_bond(nm, 1.0 * hrs)
	G.counters["searches"] = float(G.counters.get("searches", 0.0)) + 1.0
	var line: String = I18n.t("%s is back from searching for %s with %s.") % [nm, I18n.t(str(kinds().get(kind, {}).get("name", kind))).to_lower(), ", ".join(parts) if not parts.is_empty() else I18n.t("nothing this time")]
	G.message.emit(line)
	G.log_event("search_done", {"who": nm, "kind": kind})
	G.sfx("pickup")
	G.companion_changed.emit()
	G.stats_changed.emit()
	return [line]


func tick(delta: float) -> void:
	_t += delta
	if _t < 3.0:
		return
	_t = 0.0
	for slot in [0, 1]:
		if searching(slot) and left(slot) <= 0.0:
			finish(slot)
