extends "res://scripts/systems/GameSystem.gd"
## Round 178: Bionics -- augments you build or find, and the swarm that brings them up to full power.
## Robert, 2026-10-25: "i want to be able to build or find my own augments and bionics ... and then you can have a nanite
## synchronization until full power and function."
## Nine body slots. A part is BUILT from materials and Bionic Scrap, or FOUND as salvage (chests, fallen foes). It is fitted in a town
## against a strain budget (grows with realm and nanite tier). A fitted part starts at a quarter of its power; the swarm SYNCHRONISES it
## over time -- faster while you sit, faster with nanite tier, and a Nanite Shard sets it on -- until it reaches full power and function.

var data := {}
var bin := {}              # part id -> count
var fitted := {}           # slot -> {"part": id, "sync": 0..1}
var made := 0
var found := 0
var fails := 0
var last_t := 0.0
var _acc := 0.0
var rng := RandomNumberGenerator.new()


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/bionics.json")
	rng.randomize()
	var it: Dictionary = data.get("item", {})
	if not it.is_empty():
		G.items[str(it["id"])] = {"name": it.get("name", ""), "type": str(it.get("type", "material")), "value": int(it.get("value", 40)), "desc": it.get("desc", "")}


func reset() -> void:
	bin = {}
	fitted = {}
	made = 0
	found = 0
	fails = 0
	last_t = G._now() if G != null else 0.0
	_acc = 0.0


func save_state() -> Dictionary:
	return {"bin": bin, "fitted": fitted, "made": made, "found": found, "fails": fails, "last_t": last_t}


func load_state(d: Dictionary) -> void:
	reset()
	var b = d.get("bin", {})
	if b is Dictionary:
		for k in b:
			if parts().has(str(k)) and int(b[k]) > 0:
				bin[str(k)] = int(b[k])
	var f = d.get("fitted", {})
	if f is Dictionary:
		for s in f:
			var row = f[s]
			if row is Dictionary and parts().has(str(row.get("part", ""))) and slots().has(str(s)):
				fitted[str(s)] = {"part": str(row["part"]), "sync": clampf(float(row.get("sync", 0.0)), 0.0, 1.0)}
	made = int(d.get("made", 0))
	found = int(d.get("found", 0))
	fails = int(d.get("fails", 0))
	last_t = float(d.get("last_t", G._now()))
	if last_t > G._now() or last_t <= 0.0:
		last_t = G._now()
	_catch_up()                 # the swarm kept working while you were away


# ---- the catalogue ------------------------------------------------------------------------------------------------

func parts() -> Dictionary:
	return data.get("parts", {})


func slots() -> Array:
	return data.get("slots", [])


func slot_name(s: String) -> String:
	return I18n.t(str(data.get("slot_names", {}).get(s, s)))


func part_name(id: String) -> String:
	return I18n.t(str(parts().get(id, {}).get("name", id)))


func for_slot(slot: String) -> Array:
	var out := []
	for id in parts():
		if str(parts()[id]["slot"]) == slot:
			out.append(str(id))
	out.sort_custom(func(a, b): return int(parts()[a]["tier"]) < int(parts()[b]["tier"]))
	return out


func in_town() -> bool:
	return G.havens.has(G.current_level) or G.tester_unlocked() or G._god_craft()


func needs_text(id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	var out := []
	for it in p.get("needs", {}):
		out.append("%d %s" % [int(p["needs"][it]), G.item_name(str(it))])
	if int(p.get("gold", 0)) > 0:
		out.append("%d gold" % int(p.get("gold", 0)))
	return ", ".join(out)


func effect_text(id: String, power: float = 1.0) -> String:
	var p: Dictionary = parts().get(id, {})
	var M = G.sys("menagerie")
	return M._eff_text(_scaled(p.get("effect", {}), power)) if M != null else ""


# ---- building and finding -----------------------------------------------------------------------------------------

func make_block(id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	if p.is_empty():
		return I18n.t("No such part.")
	if G.realm < int(p.get("realm", 0)):
		return I18n.t("Needs %s.") % G.realm_name_of(int(p.get("realm", 0)))
	var miss := []
	for it in p.get("needs", {}):
		var have: int = G.count(str(it))
		if have < int(p["needs"][it]):
			miss.append("%s %d/%d" % [G.item_name(str(it)), have, int(p["needs"][it])])
	if G.gold < int(p.get("gold", 0)):
		miss.append("%d gold" % int(p.get("gold", 0)))
	if not miss.is_empty():
		return I18n.t("Needs: ") + ", ".join(miss)
	return ""


func make(id: String) -> String:
	var why := make_block(id)
	if why != "":
		return why
	var p: Dictionary = parts()[id]
	for it in p.get("needs", {}):
		G.remove_item(str(it), int(p["needs"][it]))
	G.gold -= int(p.get("gold", 0))
	bin[id] = int(bin.get(id, 0)) + 1
	made += 1
	G.message.emit(I18n.t("BIONICS: you build a %s. It goes in the bin.") % part_name(id))
	G.log_event("bionic_made", {"id": id})
	G.stats_changed.emit()
	return ""


func find_tier_cap() -> int:
	return clampi(1 + G.realm / 3, 1, 3)


func find_part(source: String) -> String:
	## a whole part turns up in the salvage -- never above what your realm could carry. Returns its id ("" if none).
	var pool := []
	for id in parts():
		if int(parts()[id]["tier"]) <= find_tier_cap():
			pool.append(str(id))
	if pool.is_empty():
		return ""
	var id: String = pool[rng.randi() % pool.size()]
	bin[id] = int(bin.get(id, 0)) + 1
	found += 1
	G.message.emit(I18n.t("BIONICS: you salvage a %s (%s).") % [part_name(id), source])
	G.log_event("bionic_found", {"id": id})
	return id


func on_event(kind: String, d: Dictionary) -> void:
	var f: Dictionary = data.get("find", {})
	if kind == "chest":
		if rng.randf() < float(f.get("chest", 0.06)):
			find_part(I18n.t("a chest"))
		elif rng.randf() < float(f.get("scrap_chest", 0.25)):
			G.add_item("bionic_scrap", rng.randi_range(1, 3))
	elif kind == "kill":
		var big: bool = str(d.get("type", "")).findn("boss") >= 0 or str(d.get("type", "")).findn("elite") >= 0
		if rng.randf() < (float(f.get("elite", 0.05)) if big else float(f.get("kill", 0.012))):
			find_part(I18n.t("a fallen foe"))
		elif rng.randf() < float(f.get("scrap_kill", 0.05)) * (3.0 if big else 1.0):
			G.add_item("bionic_scrap", 1)


# ---- strain --------------------------------------------------------------------------------------------------------

func capacity() -> int:
	var s: Dictionary = data.get("strain", {})
	return int(s.get("base", 6)) + int(s.get("per_realm", 2)) * G.realm + int(s.get("per_tier", 2)) * G.nanite_tier()


func strain_used() -> int:
	var n := 0
	for s in fitted:
		n += int(parts()[fitted[s]["part"]].get("strain", 0))
	return n


func install_chance(use_shard: bool = false) -> float:
	if G._god_craft():
		return 1.0
	var i: Dictionary = data.get("install", {})
	var c: float = float(i.get("base", 0.78)) + float(i.get("per_realm", 0.02)) * G.realm + (float(i.get("shard", 0.12)) if use_shard else 0.0)
	return clampf(c, 0.05, float(i.get("cap", 0.96)) + (float(i.get("shard", 0.12)) if use_shard else 0.0))


func install_block(slot: String, pid: String, use_shard: bool = false) -> String:
	if not parts().has(pid) or str(parts()[pid]["slot"]) != slot:
		return I18n.t("That part does not fit that slot.")
	if int(bin.get(pid, 0)) <= 0:
		return I18n.t("You have no %s.") % part_name(pid)
	if not in_town():
		return I18n.t("Fit and remove parts in a town.")
	var cur: String = str(fitted.get(slot, {}).get("part", ""))
	var after: int = strain_used() - (int(parts()[cur].get("strain", 0)) if cur != "" else 0) + int(parts()[pid].get("strain", 0))
	if after > capacity():
		return I18n.t("Too much strain: %d of %d. Grow your realm or the swarm, or take another part out.") % [after, capacity()]
	var cost := int(data.get("swap_gold", 15)) if cur != "" else 0
	if G.gold < cost:
		return I18n.t("Swapping costs %d gold.") % cost
	if use_shard and G.count("nanite_shard") <= 0:
		return I18n.t("You have no %s.") % G.item_name("nanite_shard")
	return ""


func install(slot: String, pid: String, use_shard: bool = false) -> Dictionary:
	## {"ok": bool, "text": String}
	var why := install_block(slot, pid, use_shard)
	if why != "":
		return {"ok": false, "text": why}
	var cur: String = str(fitted.get(slot, {}).get("part", ""))
	if cur != "":
		G.gold -= int(data.get("swap_gold", 15))
		bin[cur] = int(bin.get(cur, 0)) + 1
		fitted.erase(slot)
	if use_shard:
		G.remove_item("nanite_shard", 1)
	bin[pid] = int(bin.get(pid, 0)) - 1
	if int(bin[pid]) <= 0:
		bin.erase(pid)
	if rng.randf() > install_chance(use_shard):
		fails += 1
		G.add_item("bionic_scrap", maxi(1, int(parts()[pid]["tier"])))
		var t := I18n.t("BIONICS: the graft failed -- the %s is ruined. You keep a little scrap.") % part_name(pid)
		G.message.emit(t)
		G.stats_changed.emit()
		return {"ok": false, "text": t}
	fitted[slot] = {"part": pid, "sync": 0.0}
	var t2 := I18n.t("BIONICS: the %s is fitted. The swarm begins to synchronise it (%d%% power).") % [part_name(pid), int(round(power_of(0.0) * 100.0))]
	G.message.emit(t2)
	G.log_event("bionic_fit", {"id": pid})
	G.stats_changed.emit()
	return {"ok": true, "text": t2}


func remove(slot: String) -> String:
	if not fitted.has(slot):
		return ""
	if not in_town():
		return I18n.t("Fit and remove parts in a town.")
	var pid: String = str(fitted[slot]["part"])
	bin[pid] = int(bin.get(pid, 0)) + 1
	fitted.erase(slot)
	G.stats_changed.emit()
	return I18n.t("BIONICS: the %s comes out and goes in the bin. (Its synchronisation starts over.)") % part_name(pid)


func dismantle(pid: String) -> String:
	if int(bin.get(pid, 0)) <= 0:
		return I18n.t("You have no %s.") % part_name(pid)
	bin[pid] = int(bin[pid]) - 1
	if int(bin[pid]) <= 0:
		bin.erase(pid)
	var n: int = int(parts()[pid]["tier"]) * 2
	G.add_item("bionic_scrap", n)
	return I18n.t("BIONICS: you strip the %s for %d scrap.") % [part_name(pid), n]


# ---- synchronisation -----------------------------------------------------------------------------------------------

func sync_cfg() -> Dictionary:
	return data.get("sync", {})


func power_of(sync: float) -> float:
	var fl: float = float(sync_cfg().get("floor", 0.25))
	return fl + (1.0 - fl) * clampf(sync, 0.0, 1.0)


func sync_of(slot: String) -> float:
	return float(fitted.get(slot, {}).get("sync", 0.0))


func is_full(slot: String) -> bool:
	return fitted.has(slot) and sync_of(slot) >= 0.9999


func rate_mult() -> float:
	var c: Dictionary = sync_cfg()
	var m: float = 1.0 + float(c.get("per_nanite_tier", 0.15)) * G.nanite_tier()
	if G.sitting or G.meditating:
		m *= float(c.get("sitting_mult", 2.0))
	return m


func hours_left(slot: String) -> float:
	if not fitted.has(slot):
		return 0.0
	var h: float = float(parts()[fitted[slot]["part"]].get("sync_hours", 1.0))
	return maxf(0.0, (1.0 - sync_of(slot)) * h / rate_mult())


func _advance(seconds: float, mult: float) -> void:
	for s in fitted:
		var row: Dictionary = fitted[s]
		if float(row["sync"]) >= 1.0:
			continue
		var h: float = float(parts()[row["part"]].get("sync_hours", 1.0))
		row["sync"] = minf(1.0, float(row["sync"]) + seconds / (h * 3600.0) * mult)
		if float(row["sync"]) >= 1.0:
			G.message.emit(I18n.t("BIONICS: your %s is fully synchronised -- full power and function.") % part_name(str(row["part"])))
			G.log_event("bionic_full", {"id": str(row["part"])})


func tick(delta: float) -> void:
	if fitted.is_empty():
		return
	_acc += delta
	if _acc >= 5.0:
		var dt := _acc
		_acc = 0.0
		last_t = G._now()
		_advance(dt, rate_mult())


func _catch_up() -> void:
	## the time you were away: the swarm works at the plain rate (no sitting bonus), up to a day
	if fitted.is_empty():
		last_t = G._now()
		return
	var away: float = clampf(G._now() - last_t, 0.0, float(sync_cfg().get("offline_cap_hours", 24)) * 3600.0)
	last_t = G._now()
	if away > 60.0:
		_advance(away, 1.0 + float(sync_cfg().get("per_nanite_tier", 0.15)) * G.nanite_tier())


func resync_block(slot: String) -> String:
	if not fitted.has(slot):
		return I18n.t("Nothing is fitted there.")
	if is_full(slot):
		return I18n.t("Already at full power.")
	if G.count("nanite_shard") <= 0:
		return I18n.t("You have no %s.") % G.item_name("nanite_shard")
	return ""


func resync(slot: String) -> String:
	var why := resync_block(slot)
	if why != "":
		return why
	G.remove_item("nanite_shard", 1)
	fitted[slot]["sync"] = minf(1.0, sync_of(slot) + float(sync_cfg().get("shard_gain", 0.25)))
	if float(fitted[slot]["sync"]) >= 1.0:
		G.message.emit(I18n.t("BIONICS: your %s is fully synchronised -- full power and function.") % part_name(str(fitted[slot]["part"])))
	G.stats_changed.emit()
	return I18n.t("BIONICS: the swarm pours into the %s (now %d%% synchronised).") % [part_name(str(fitted[slot]["part"])), int(round(sync_of(slot) * 100.0))]


func sync_all_block() -> String:
	var need := 0
	for s in fitted:
		if not is_full(str(s)):
			need += 1
	if need == 0:
		return I18n.t("Everything fitted is at full power.")
	if G.count("nanite_shard") <= 0:
		return I18n.t("You have no %s.") % G.item_name("nanite_shard")
	return ""


func sync_all() -> String:
	## shards poured in until every fitted part is at full power, or the shards run out
	var why := sync_all_block()
	if why != "":
		return why
	var used := 0
	var guard := 0
	while guard < 200 and G.count("nanite_shard") > 0:
		guard += 1
		var target := ""
		for s in fitted:
			if not is_full(str(s)):
				target = str(s)
				break
		if target == "":
			break
		resync(target)
		used += 1
	return I18n.t("BIONICS: %d shards poured into the swarm.") % used


# ---- the gifts -----------------------------------------------------------------------------------------------------

func _scaled(eff: Dictionary, f: float) -> Dictionary:
	var out := {}
	for k in eff:
		var key := str(k)
		if key in G.ADDITIVE_KEYS or key.begins_with("craft_"):
			out[key] = float(eff[k]) * f
		else:
			out[key] = 1.0 + (float(eff[k]) - 1.0) * f
	return out


func _combine(into: Dictionary, eff: Dictionary) -> void:
	for k in eff:
		var key := str(k)
		if key in G.ADDITIVE_KEYS or key.begins_with("craft_"):
			into[key] = float(into.get(key, 0.0)) + float(eff[k])
		else:
			into[key] = float(into.get(key, 1.0)) * float(eff[k])


func gifts() -> Dictionary:
	var out := {}
	for s in fitted:
		var p: Dictionary = parts()[fitted[s]["part"]]
		_combine(out, _scaled(p.get("effect", {}), power_of(float(fitted[s]["sync"]))))
	return out


func effects() -> Array:
	var g := gifts()
	return [g] if not g.is_empty() else []


func status_lines() -> Array:
	var out := []
	out.append(I18n.t("Strain %d of %d  ·  parts built %d  ·  found %d  ·  grafts failed %d") % [strain_used(), capacity(), made, found, fails])
	out.append(I18n.t("The swarm synchronises at x%.2f (sit to double it).") % rate_mult())
	return out
