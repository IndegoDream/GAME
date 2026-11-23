extends "res://scripts/systems/GameSystem.gd"
## Ruins and the old age (round 44). Robert, 2026-10-04: "bring more depth to
## the world ... ruins and the old age ... a sense of continuity."
##
## A dig site on every dungeon floor from the fourth down, ringed with the
## same jade-and-glyph stonework wherever it appears -- the look of the age
## before Eliet. Dig through three layers (Archaeology grows as you do; now
## and then you wake something). At the bottom: a RELIC of one of four ages,
## each a line in the Old Age timeline (the World page) --
##   the First Breath (deepest) -> the Lattice Age -> the Sundering -> the Long Quiet
## so going down is going back in time. A site whose relic is gone, or that
## never had one, gives potsherds and points you at the nearest relic you
## haven't found. Find every relic of an age and you learn its technique.
## Learn an age and its glyphs on every ruin become readable to you.
## A relic can be kept, or given to the Heirs of the Makers or to the Valley
## Sects -- each wants them, and each resents the other having them.
## data/ruins.json; Dev's words: brief ruins.

var data := {}
var dug := {}            # level id -> layers dug (0..3)
var found := []          # relic ids, in the order found
var given := {}          # relic id -> faction it went to
var _defs_done := false


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/ruins.json")
	var dr = G._load_json("res://data/drafts/ruins.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and data.get("relics", {}).has(str(it.get("id", ""))) and str(it.get("text", "")).strip_edges() != "":
				data["relics"][str(it["id"])]["text"] = str(it["text"]).strip_edges()
	_register()


func _register() -> void:
	## relics, the potsherd and the four ages' techniques join the game's own
	var fr: Dictionary = data.get("fragment", {})
	if not fr.is_empty() and not G.items.has(str(fr["id"])):
		G.items[str(fr["id"])] = {"name": fr.get("name", ""), "type": "material", "value": int(fr.get("value", 15)), "desc": fr.get("desc", "")}
	for rid in data.get("relics", {}):
		var r: Dictionary = data["relics"][rid]
		if not G.items.has(rid):
			G.items[rid] = {"name": r.get("name", rid), "type": "relic", "value": int(r.get("value", 50)), "desc": "%s (%s)" % [str(r.get("desc", "")), era_name(str(r.get("era", "")))]}
	for e in data.get("eras", []):
		var t: Dictionary = e.get("technique", {})
		if not t.is_empty() and not G.technique_defs.has(str(t["id"])):
			G.technique_defs[str(t["id"])] = {"name": t.get("name", ""), "kind": "passive", "desc": t.get("desc", ""), "effect": (t.get("effect", {}) as Dictionary).duplicate(), "realm": 0, "source": "ruins"}
	if not G.skill_defs.has("archaeology"):
		G.skill_defs["archaeology"] = {"name": "Archaeology", "kind": "gathering", "elements": {"earth": 0.6, "metal": 0.4},
			"desc": "Digging carefully through the layers of the old age. The better you are, the more the ground gives up."}


func reset() -> void:
	dug = {}
	found = []
	given = {}


func save_state() -> Dictionary:
	return {"dug": dug, "found": found, "given": given}


func load_state(d: Dictionary) -> void:
	dug = {}
	var dd = d.get("dug", {})
	if dd is Dictionary:
		for k in dd:
			dug[str(k)] = int(dd[k])
	found = d.get("found", []) if d.get("found", []) is Array else []
	given = d.get("given", {}) if d.get("given", {}) is Dictionary else {}


# ---- the ages ---------------------------------------------------------------------------------

func eras() -> Array:
	var out: Array = (data.get("eras", []) as Array).duplicate()
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


func era(eid: String) -> Dictionary:
	for e in data.get("eras", []):
		if str(e.get("id", "")) == eid:
			return e
	return {}


func era_name(eid: String) -> String:
	return str(era(eid).get("name", eid))


func relics_of(eid: String) -> Array:
	var out := []
	for rid in data.get("relics", {}):
		if str(data["relics"][rid].get("era", "")) == eid:
			out.append(rid)
	out.sort_custom(func(a, b): return int(data["relics"][a].get("floor", 0)) < int(data["relics"][b].get("floor", 0)))
	return out


func era_known(eid: String) -> bool:
	var rs := relics_of(eid)
	if rs.is_empty():
		return false
	for rid in rs:
		if not (rid in found):
			return false
	return true


func relic(rid: String) -> Dictionary:
	return data.get("relics", {}).get(rid, {})


func relic_at(floor_n: int) -> String:
	for rid in data.get("relics", {}):
		if int(data["relics"][rid].get("floor", -1)) == floor_n:
			return rid
	return ""


# ---- a site -------------------------------------------------------------------------------------

func has_site(level_id: String, level_def: Dictionary) -> bool:
	return int(level_def.get("depth", 0)) >= int(data.get("min_depth", 4)) and str(level_def.get("theme", "dungeon")) == "dungeon" \
		and level_id.begins_with("floor") and not bool(level_def.get("trial", false)) and not bool(level_def.get("arena", false))


func layers() -> int:
	return int(data.get("layers", 3))


func layers_dug(level_id: String) -> int:
	return int(dug.get(level_id, 0))


func site_done(level_id: String) -> bool:
	return layers_dug(level_id) >= layers()


func dig(level_id: String, floor_n: int) -> Dictionary:
	## one layer deeper: {text, done, relic, guardian}
	if site_done(level_id):
		return {"text": "There's nothing left here but a clean hole.", "done": true}
	var n := layers_dug(level_id) + 1
	dug[level_id] = n
	G.add_skill_xp("archaeology", 3.0 + floor_n * 0.4, "a dig")
	G.log_event("dig", {"level": level_id, "layer": n})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("dig|%s|%d" % [level_id, n])
	var out := {"done": n >= layers(), "guardian": n < layers() and rng.randf() < float(data.get("guardian_chance", 0.2))}
	var layer_names := ["topsoil and old ash", "packed clay full of potsherds", "dressed stone -- the old floor"]
	if n < layers():
		out["text"] = I18n.t("You dig through the %s.%s") % [layer_names[clampi(n - 1, 0, 2)], I18n.t(" Something stirs in the dark below!") if bool(out["guardian"]) else ""]
		G.stats_changed.emit()
		return out
	# the bottom
	var rid := relic_at(floor_n)
	var shards := 1 + int(G.skill_level("archaeology") / 3)
	var fr := str(data.get("fragment", {}).get("id", ""))
	if fr != "":
		G.add_item(fr, shards, false)
	if rid != "" and not (rid in found):
		found.append(rid)
		G.add_item(rid, 1, false)
		var r := relic(rid)
		var e := era(str(r.get("era", "")))
		G.jingle("discovery")
		G.big_moment.emit("%s -- %s" % [str(r.get("name", "")), str(e.get("name", ""))], str(r.get("text", "")))
		G.log_event("relic_found", {"relic": rid, "era": e.get("id", "")})
		G.note_place(I18n.t("Dug up the %s (%s)") % [str(r.get("name", "")), str(e.get("name", ""))])
		G.gain_insight(2.0, "the old age")
		out["relic"] = rid
		out["text"] = I18n.t("Under the old floor: the %s. (%d potsherd%s too.)") % [str(r.get("name", "")), shards, "" if shards == 1 else "s"]
		if era_known(str(e.get("id", ""))):
			_learn_era(e)
	else:
		out["text"] = I18n.t("Under the old floor: potsherds (%d), nothing more. %s") % [shards, pointer(floor_n)]
	G.stats_changed.emit()
	return out


func _learn_era(e: Dictionary) -> void:
	var t: Dictionary = e.get("technique", {})
	G.big_moment.emit(str(e.get("name", "")), "You know this age now, from the first relic to the last. %s" % str(e.get("summary", "")))
	G.log_event("era_known", {"era": e.get("id", "")})
	if not t.is_empty():
		G.learn(str(t["id"]), "the old age")


func pointer(from_floor: int) -> String:
	## the nearest relic you haven't found, as a carved hint
	var best := ""
	var bd := 999
	for rid in data.get("relics", {}):
		if rid in found:
			continue
		var f := int(data["relics"][rid].get("floor", 0))
		if absi(f - from_floor) < bd:
			bd = absi(f - from_floor)
			best = rid
	if best == "":
		return I18n.t("You've found every relic there is.")
	var r := relic(best)
	return I18n.t("A glyph-arrow scratched into the stone points %s: something of %s waits on floor %d.") % ["down" if int(r.get("floor", 0)) > from_floor else "up", era_name(str(r.get("era", ""))), int(r.get("floor", 0))]


func give(rid: String, fid: String) -> String:
	## a relic to the Heirs or the Sects
	if G.count(rid) <= 0:
		return I18n.t("You don't have that.")
	if not (fid in ["heirs", "sects"]):
		return I18n.t("They don't want it.")
	G.remove_item(rid, 1)
	given[rid] = fid
	var F = G.sys("factions")
	var gift: Dictionary = data.get("gift", {})
	if F:
		F.change(fid, float(gift.get("standing", 30)), I18n.t("a relic: ") + str(relic(rid).get("name", rid)), false)
		var rival := str(F.fdef(fid).get("rival", ""))
		if rival != "":
			F.change(rival, -float(gift.get("rival", 15)), I18n.t("you gave a relic to the ") + str(F.fdef(fid).get("short", fid)), false)
	G.log_event("relic_given", {"relic": rid, "to": fid})
	return I18n.t("The %s will look after the %s. (You still remember what it told you.)") % [str(F.fdef(fid).get("short", fid)) if F else fid, str(relic(rid).get("name", rid))]


func inscription_for(level_id: String, floor_n: int) -> String:
	## the glyphs on a ruin: readable once you know that floor's age
	var rid := relic_at(floor_n)
	var eid := str(relic(rid).get("era", "")) if rid != "" else _era_by_depth(floor_n)
	if eid == "":
		return ""
	return str(era(eid).get("inscription", "")) if era_known(eid) else ""


func _era_by_depth(floor_n: int) -> String:
	## the age a floor's stonework belongs to (the nearest relic's)
	var best := ""
	var bd := 999
	for rid in data.get("relics", {}):
		var f := int(data["relics"][rid].get("floor", 0))
		if absi(f - floor_n) < bd:
			bd = absi(f - floor_n)
			best = str(data["relics"][rid].get("era", ""))
	return best


func timeline() -> Array:
	## [{era, name, when, summary, known, entries: [{relic, name, text, floor, found}]}], oldest first
	var out := []
	for e in eras():
		var eid := str(e.get("id", ""))
		var ents := []
		for rid in relics_of(eid):
			var r := relic(rid)
			ents.append({"relic": rid, "name": str(r.get("name", "")), "text": str(r.get("text", "")), "floor": int(r.get("floor", 0)), "found": rid in found})
		out.append({"era": eid, "name": str(e.get("name", "")), "when": str(e.get("when", "")), "summary": str(e.get("summary", "")), "known": era_known(eid), "entries": ents})
	return out


func place(level) -> int:
	if not has_site(str(level.level_id), level.def):
		return 0
	var rad := 2
	var c: Vector2i = level.open_spot(3, "ruin|" + str(level.level_id))
	if c.x < 0:
		rad = 1
		c = level.open_spot(2, "ruin|" + str(level.level_id))
	if c.x < 0:
		level.warnings.append(I18n.t("no room for the dig site"))
		return 0
	level._spawn_script("res://scripts/world/DigSite.gd", level.cell_to_world(c), {"cell": c, "radius": rad})
	level._count("dig_sites")
	return 1
