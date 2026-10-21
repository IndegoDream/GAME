extends "res://scripts/systems/GameSystem.gd"
## The ki arts library (round 122). Robert: "movement arts, defence arts, attack arts and support
## arts like healing, buffing and debuffing, which can be done by anyone, but the classes will
## provide some sort of benefit for different arts, and some arts might be restricted by class or
## level... someone doesn't need nanites to succeed, or ki, but used together they meet their true
## potential... if we pick up companions, human or otherwise, they get appropriate targeting."
##
## The data is data/arts_ext.json (made by tools/gen/arts_gen.py). This system:
##   * merges those arts into the meridian lattice, so they are learned, practised, wired,
##     branched and mastered exactly like the arts that were there before;
##   * teaches a sect's or path's arts the moment you qualify (sync), and gates casting;
##   * gives each Path a small bonus on certain families (affinity);
##   * resonance: ki alone works, nanites alone work, both together run 12% stronger and cooler;
##   * where the support arts go (support_mode: one slot / two slots / share the attack key);
##   * who a heal or a boon reaches: you, human companions, spirits, constructs, beasts.
## The casting itself is scripts/actors/ArtCaster.gd.

var cfg := {}
var defs := {}                  # ext art id -> its row
var names := {}                 # lowercase display name -> id (a blow's "source")
var support_mode := "one"       # "one" | "two" | "share"
var ally_buff := {"dmg": {"mult": 1.0, "until": 0.0}, "take": {"mult": 1.0, "until": 0.0}}
var _sync_t := 0.0
var _res_told := false


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/arts_ext.json", {})
	cfg = d if d is Dictionary else {}
	defs = {}
	names = {}
	var L: Dictionary = G.lattice_data()
	var lat: Dictionary = L.get("arts", {})
	for a in cfg.get("arts", []):
		var aid := str(a.get("id", ""))
		if aid == "":
			continue
		defs[aid] = a
		names[str(a.get("name", aid)).to_lower()] = aid
		var el := str(a.get("element", ""))
		var row := {"family": str(a["family"]), "route": a.get("route", []), "heat": float(a.get("heat", 0.0)),
			"branches": a.get("branches", []), "template": str(a["template"]), "ext": true}
		if el != "":
			row["sect"] = "ext"                     # (it carries its element from the start, like a sect's art)
		if a.has("requires"):
			row["requires"] = a["requires"]
		if a.has("glimpse"):
			row["glimpse"] = a["glimpse"]
		lat[aid] = row
		var key := _key_label(a)
		G.technique_defs[aid] = {"name": str(a.get("name", aid)), "kind": "active" if str(a["family"]) != "guard" else "passive",
			"key": key, "cooldown": float(a.get("cooldown", 0.0)), "realm": int((a.get("req", {}) as Dictionary).get("realm", 0)),
			"desc": "%s (%s)" % [str(a.get("desc", "")), _source_text(a)],
			"params": (a.get("params", {}) as Dictionary).duplicate(true), "effect": {}, "hint": str(a.get("hint", ""))}
	L["arts"] = lat


func reset() -> void:
	support_mode = str(cfg.get("support", {}).get("default", "one"))
	ally_buff = {"dmg": {"mult": 1.0, "until": 0.0}, "take": {"mult": 1.0, "until": 0.0}}
	_sync_t = 0.0


func save_state() -> Dictionary:
	return {"mode": support_mode}


func load_state(d: Dictionary) -> void:
	var m := str(d.get("mode", cfg.get("support", {}).get("default", "one")))
	support_mode = m if m in ["one", "two", "share"] else "one"


func _key_label(a: Dictionary) -> String:
	match str(a["family"]):
		"strike":
			return "F"
		"step":
			return "V"
		"guard":
			return I18n.t("Right mouse")
	return slot_key(slot_of_def(a))


# ---- slots ------------------------------------------------------------------------------

func slot_of_def(a: Dictionary) -> String:
	var fam := str(a.get("family", ""))
	if fam != "support":
		return fam
	match support_mode:
		"share":
			return "strike"
		"two":
			return "support" if str(a.get("sub", "restore")) == "restore" else "support2"
	return "support"


func slot_of(aid: String) -> String:
	## which wired slot an art lives in. Every art but a support art is its own family's.
	if defs.has(aid):
		return slot_of_def(defs[aid])
	return G.art_family(aid)


func slot_key(slot: String) -> String:
	return {"strike": "F", "step": "V", "guard": "guard", "support": "8", "support2": "9"}.get(slot, "?")


func slot_label(slot: String) -> String:
	return {"strike": "F", "step": "V", "guard": "Guard", "support": "8 Mend" if support_mode == "two" else "8 Support", "support2": "9 Boon"}.get(slot, slot)


func slots_shown() -> Array:
	## [label, slot] for the HUD line: the support slots depend on the mode
	var out := [["F", "strike"], ["V", "step"], ["Guard", "guard"]]
	if support_mode != "share":
		out.append(["8", "support"])
	if support_mode == "two":
		out.append(["9", "support2"])
	return out


func mode_text() -> String:
	match support_mode:
		"two":
			return I18n.t("two slots: 8 mends (healing), 9 boons and hexes")
		"share":
			return I18n.t("shared with the attack key (F)")
	return I18n.t("one slot, on 8")


func cycle_mode() -> String:
	var modes: Array = cfg.get("support", {}).get("modes", ["one", "two", "share"])
	support_mode = str(modes[(modes.find(support_mode) + 1) % modes.size()])
	# arts keep their place only if the new mode still has a slot for them
	var keep := {}
	for s in G.art_slots:
		var aid := str(G.art_slots[s])
		if defs.has(aid) and str(defs[aid]["family"]) == "support":
			continue
		keep[s] = G.art_slots[s]
	G.art_slots = keep
	G.stats_changed.emit()
	return I18n.t("Support arts: %s.") % mode_text()


# ---- who may learn and cast what -----------------------------------------------------------

func def_of(aid: String) -> Dictionary:
	return defs.get(aid, {})


func is_ext(aid: String) -> bool:
	return defs.has(aid)


func is_source(src: String) -> bool:
	return names.has(src)


func _sect_ok(e: Dictionary) -> bool:
	return G.in_sect(str(e["sect"])) and int(G.sect.get("rank", 0)) + 1 >= int(e.get("rank", 1))


func _path_ok(e: Dictionary) -> bool:
	var P = G.sys("paths")
	if P == null:
		return false
	var pid := str(e["path"])
	if P.primary != pid and P.secondary != pid:
		return false
	return P.rank_of(pid) >= int(e.get("rank", 1))


func qualifies(aid: String) -> String:
	## "" when you don't, else how: "open" (no restriction), "sect" or "path"
	var a := def_of(aid)
	var req: Dictionary = a.get("req", {})
	if G.realm < int(req.get("realm", 0)):
		return ""
	var any: Array = req.get("any", [])
	if any.is_empty():
		return "open"
	var via := ""
	for e in any:
		if e.has("sect") and _sect_ok(e):
			return "sect"
		if e.has("path") and _path_ok(e):
			via = "path"
	return via


func needs_text(aid: String) -> String:
	## what a locked art asks of you, in words
	var a := def_of(aid)
	var req: Dictionary = a.get("req", {})
	var bits := []
	if int(req.get("realm", 0)) > 0:
		bits.append(I18n.t("the realm of %s") % G.realm_name_of(int(req["realm"])))
	var opts := []
	for e in req.get("any", []):
		if e.has("sect"):
			opts.append(I18n.t("%s of the %s") % [G.sect_rank_name(int(e.get("rank", 1)) - 1), str(G.sect_def(str(e["sect"])).get("name", e["sect"]))])
		elif e.has("path"):
			var P = G.sys("paths")
			opts.append(I18n.t("rank %d of the %s road") % [int(e.get("rank", 1)), str(P.def(str(e["path"])).get("name", e["path"])) if P != null else str(e["path"])])
	if not opts.is_empty():
		bits.append(" or ".join(opts))
	return " and ".join(bits)


func _source_text(a: Dictionary) -> String:
	var req: Dictionary = a.get("req", {})
	if (req.get("any", []) as Array).is_empty():
		return I18n.t("open to anyone")
	return "restricted"


func nano_carries(aid: String) -> bool:
	## "someone doesn't need ki to succeed": a new art whose route is still sealed runs on the swarm
	## alone once it is past its first tier (hotter, as a nanite bridge is -- never stronger)
	if not defs.has(aid) or G.nanite_tier() < 1:
		return false
	for pid in G.art_route(aid):
		if not G.lattice.has(str(pid)):
			return true
	return false


func gate(aid: String) -> String:
	## "" when you may cast it now. Called from Game.art_blocked.
	if not defs.has(aid):
		return ""
	var a: Dictionary = defs[aid]
	var req: Dictionary = a.get("req", {})
	if G.realm < int(req.get("realm", 0)):
		return I18n.t("%s needs the realm of %s.") % [str(a["name"]), G.realm_name_of(int(req["realm"]))]
	var any: Array = req.get("any", [])
	if any.is_empty():
		return ""
	if G.has_flag("ax:%s:sect" % aid):
		return ""                                  # a sect's gift stays with you (as the sect told you)
	for e in any:
		if e.has("sect") and _sect_ok(e):
			return ""
		if e.has("path") and _path_ok(e):
			return ""
	return I18n.t("%s needs you to walk the road it came from: %s.") % [str(a["name"]), needs_text(aid)]


func sync() -> void:
	## teach whatever you now qualify for (a sect rank, a path rank, a realm)
	for aid in defs:
		if G.techniques.has(aid):
			continue
		var a: Dictionary = defs[aid]
		if a.has("glimpse"):
			continue                                # found by doing, not by rank
		var how := qualifies(str(aid))
		if how == "" or how == "open":
			continue
		G.set_flag("ax:%s:%s" % [aid, how])
		var src := "sect" if how == "sect" else "path"
		G.learn(str(aid), src)
		G.message.emit(I18n.t("ART TAUGHT: %s -- %s") % [str(a["name"]), I18n.t("your sect's gift") if how == "sect" else "your road opens it"])


func tick(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 2.0
		if G.hp > 0:
			sync()


# ---- Path affinity ----------------------------------------------------------------------

func affinity(fam: String) -> Dictionary:
	## {"power","cd","heat"} multipliers from your road (the second road counts half)
	var out := {"power": 1.0, "cd": 1.0, "heat": 1.0}
	var P = G.sys("paths")
	if P == null:
		return out
	var table: Dictionary = cfg.get("affinity", {})
	var caps: Dictionary = cfg.get("affinity_caps", {})
	for pair in [[P.primary, 1.0], [P.secondary, 0.5]]:
		var pid := str(pair[0])
		if pid == "" or not table.has(pid):
			continue
		var row: Dictionary = (table[pid] as Dictionary).get(fam, {})
		for k in row:
			out[k] = float(out[k]) * (1.0 + (float(row[k]) - 1.0) * float(pair[1]))
	out["power"] = minf(float(out["power"]), float(caps.get("power", 1.2)))
	out["cd"] = maxf(float(out["cd"]), float(caps.get("cd", 0.8)))
	out["heat"] = maxf(float(out["heat"]), float(caps.get("heat", 0.8)))
	return out


# ---- resonance: ki, nanites, and both ------------------------------------------------------

func resonance(aid: String) -> Dictionary:
	## {"mode": "ki" | "nano" | "both" | "none", "power", "heat", "dur"}
	var R: Dictionary = cfg.get("resonance", {})
	var ki: bool = G.realm >= 1 and G.art_blocked(aid) == "" and not G._route_bridged(aid)
	var nano: bool = G.nanite_tier() >= 1
	var out := {"mode": "none", "power": 1.0, "heat": 1.0, "dur": 1.0}
	if ki and nano:
		out = {"mode": "both", "power": float(R.get("power", 1.12)), "heat": float(R.get("heat", 0.85)), "dur": float(R.get("duration", 1.15))}
	elif ki:
		out["mode"] = "ki"
	elif nano:
		out["mode"] = "nano"
	return out


func resonance_text(aid: String) -> String:
	match str(resonance(aid)["mode"]):
		"both":
			return I18n.t("ki and nanites in step: +12% strength, 15% less heat")
		"ki":
			return I18n.t("running on ki alone (nanites would add to it)")
		"nano":
			return I18n.t("running on nanites alone (an open meridian would add to it)")
	return I18n.t("neither road begun")


func note_resonance(aid: String) -> void:
	if not _res_told and str(resonance(aid)["mode"]) == "both":
		_res_told = true
		if not G.has_flag("ax:resonance_told"):
			G.set_flag("ax:resonance_told")
			G.message.emit("RESONANCE: ki and nanites run together -- the art is stronger and cooler. Either alone still works; both is its true strength.")


# ---- who an art reaches --------------------------------------------------------------------

func ally_kind(c: Dictionary) -> String:
	var k := str(c.get("kind", ""))
	if k == "":
		k = str(cfg.get("named_kinds", {}).get(str(c.get("name", "")), ""))
	if k == "":
		k = str(G.companions_data().get("kinds", {}).get(str(c.get("name", "")), "human"))
	return k if cfg.get("kinds", {}).has(k) else "human"


func kind_mult(kind: String, nature: String) -> float:
	return float(cfg.get("kinds", {}).get(kind, cfg.get("kinds", {}).get("human", {})).get(nature, 1.0))


func party() -> Array:
	## [{"who": "you"|"companion"|"beast", "slot", "name", "kind", "frac", "hp", "max", "down", "node"}]
	var out := []
	out.append({"who": "you", "slot": -1, "name": "you", "kind": "human", "frac": float(G.hp) / maxf(float(G.max_hp()), 1.0), "hp": G.hp, "max": G.max_hp(), "down": false, "node": null})
	for s in [0, 1]:
		var cc: Dictionary = G.cslot(s)
		if cc.is_empty():
			continue
		var node = null
		for n in G.get_tree().get_nodes_in_group("companion"):
			if is_instance_valid(n) and int(n.slot) == s:
				node = n
		out.append({"who": "companion", "slot": s, "name": str(cc.get("name", "")), "kind": ally_kind(cc),
			"frac": float(G.companion_hp(s)) / maxf(float(G.companion_max_hp(s)), 1.0), "hp": G.companion_hp(s), "max": G.companion_max_hp(s),
			"down": G.companion_down(s), "node": node})
	for n2 in G.get_tree().get_nodes_in_group("familiar_node"):
		if is_instance_valid(n2):
			out.append({"who": "beast", "slot": 0, "name": str(G.familiar.get("name", I18n.t("your familiar"))), "kind": "beast", "frac": 1.0, "hp": 0, "max": 0, "down": false, "node": n2})
	return out


func in_reach(entry: Dictionary, from: Vector3, r: float) -> bool:
	var n = entry.get("node", null)
	if n == null:
		return str(entry["who"]) == "you"           # you are always within reach of yourself
	return is_instance_valid(n) and (n.global_position - from).length() <= r


func heal_entry(entry: Dictionary, pct: float, nature: String) -> int:
	## heal one party member by pct of THEIR life, scaled by what they are made of. Returns what it did.
	var k := str(entry["kind"])
	var m := kind_mult(k, nature)
	match str(entry["who"]):
		"you":
			var amt: int = maxi(1, int(round(G.max_hp() * pct)))
			var before: int = G.hp
			G.heal(amt)
			return G.hp - before
		"companion":
			if bool(entry["down"]):
				return 0
			var cc: Dictionary = G.cslot(int(entry["slot"]))
			var mx: int = G.companion_max_hp(int(entry["slot"]))
			var before2: int = G.companion_hp(int(entry["slot"]))
			cc["hp"] = mini(mx, before2 + maxi(1, int(round(mx * pct * m))))
			G.stats_changed.emit()
			return int(cc["hp"]) - before2
	return 0


func set_ally_buff(which: String, mult: float, secs: float) -> void:
	var row: Dictionary = ally_buff[which]
	var now: float = G._now()
	row["mult"] = mult
	row["until"] = now + secs


func ally_dmg_mult() -> float:
	var r: Dictionary = ally_buff["dmg"]
	return float(r["mult"]) if float(r["until"]) > G._now() else 1.0


func ally_take_mult() -> float:
	var r: Dictionary = ally_buff["take"]
	return float(r["mult"]) if float(r["until"]) > G._now() else 1.0


# ---- the menu's view -------------------------------------------------------------------------

func rows(fam: String = "") -> Array:
	## every ext art: {id, name, family, known, status, how} for the K page / Arts list
	var out := []
	for aid in defs:
		var a: Dictionary = defs[aid]
		if fam != "" and str(a["family"]) != fam:
			continue
		var known: bool = G.techniques.has(aid)
		var st := ""
		if known:
			st = "known" if gate(str(aid)) == "" else "known, but " + gate(str(aid)).to_lower()
		elif a.has("glimpse"):
			st = "found by doing"
		else:
			st = needs_text(str(aid))
		out.append({"id": str(aid), "name": str(a["name"]), "family": str(a["family"]), "sub": str(a.get("sub", "")), "known": known, "status": st})
	return out
