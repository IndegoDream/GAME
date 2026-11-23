extends "res://scripts/systems/GameSystem.gd"
## Round 177: the Foundry -- golems, the power frame and the skiff, built from parts.
## Robert, 2026-10-25: "same with constructs and ships: i want them to be modifiable and modular ... allow runes to be used on constructs."
## A golem has five slots (core, frame, limbs, senses, engine), the frame four (plating, servos, reactor, optics) and the skiff four
## (hull, sails, hold, charts). Craft a part from materials, fit it in a town, swap it whenever you like -- the old part goes back to the
## bin. Parts add gifts and an APTITUDE (what the construct is good at). Runes can be cut into golems and the frame.

var data := {}
var bin := {}              # part id -> count
var mech_parts := {}       # slot -> part id
var ship_parts := {}
var mech_runes := []
var made := 0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/foundry.json")


func reset() -> void:
	bin = {}
	mech_parts = {}
	ship_parts = {}
	mech_runes = []
	made = 0


func save_state() -> Dictionary:
	return {"bin": bin, "mech_parts": mech_parts, "ship_parts": ship_parts, "mech_runes": mech_runes, "made": made}


func load_state(d: Dictionary) -> void:
	reset()
	var b = d.get("bin", {})
	if b is Dictionary:
		for k in b:
			if data.get("parts", {}).has(str(k)) and int(b[k]) > 0:
				bin[str(k)] = int(b[k])
	for pair in [["mech_parts", mech_parts], ["ship_parts", ship_parts]]:
		var src = d.get(pair[0], {})
		if src is Dictionary:
			for k in src:
				if data.get("parts", {}).has(str(src[k])):
					pair[1][str(k)] = str(src[k])
	for r in d.get("mech_runes", []):
		mech_runes.append(str(r))
	made = int(d.get("made", 0))


func parts() -> Dictionary:
	return data.get("parts", {})


func slots_of(kind: String) -> Array:
	return data.get("slots", {}).get(kind, [])


func slot_name(s: String) -> String:
	return I18n.t(str(data.get("slot_names", {}).get(s, s)))


func part_name(id: String) -> String:
	return I18n.t(str(parts().get(id, {}).get("name", id)))


func for_slot(kind: String, slot: String) -> Array:
	var out := []
	for id in parts():
		var p: Dictionary = parts()[id]
		if str(p["kind"]) == kind and str(p["slot"]) == slot:
			out.append(str(id))
	out.sort_custom(func(a, b): return int(parts()[a]["tier"]) < int(parts()[b]["tier"]))
	return out


func in_town() -> bool:
	return G.havens.has(G.current_level) or G.tester_unlocked() or G._god_craft()


# ---- making and fitting parts ------------------------------------------------------------------------------------

func needs_text(id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	var out := []
	for it in p.get("needs", {}):
		out.append("%d %s" % [int(p["needs"][it]), G.item_name(str(it))])
	if int(p.get("gold", 0)) > 0:
		out.append("%d gold" % int(p["gold"]))
	return ", ".join(out)


func make_block(id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	if p.is_empty():
		return I18n.t("No such part.")
	var CN = G.sys("constructs")
	if CN != null and not CN._research("animate"):
		return I18n.t("Research Animation first (the swarm, Constructs).")
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
	G.message.emit(I18n.t("FOUNDRY: you shape a %s. It goes in the bin.") % part_name(id))
	G.log_event("part_made", {"id": id})
	G.stats_changed.emit()
	return ""


func target_parts(target: String) -> Dictionary:
	## target: "mech", "ship" or "golem:<name>"
	if target == "mech":
		return mech_parts
	if target == "ship":
		return ship_parts
	var c := golem_by_name(target.trim_prefix("golem:"))
	if c.is_empty():
		return {}
	if not (c.get("parts") is Dictionary):
		c["parts"] = {}
	return c["parts"]


func target_kind(target: String) -> String:
	return "golem" if target.begins_with("golem:") else target


func golem_by_name(nm: String) -> Dictionary:
	for c in G.contracts:
		if bool(c.get("construct", false)) and str(c.get("name", "")) == nm:
			return c
	return {}


func golems() -> Array:
	var out := []
	for c in G.contracts:
		if bool(c.get("construct", false)):
			out.append(c)
	return out


func fit_block(target: String, slot: String, id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	if p.is_empty() or str(p["kind"]) != target_kind(target) or str(p["slot"]) != slot:
		return I18n.t("That part does not go there.")
	if int(bin.get(id, 0)) <= 0:
		return I18n.t("You have no %s in the bin.") % part_name(id)
	if not in_town():
		return I18n.t("Fit parts in a town -- the work needs a bench.")
	if target.begins_with("golem:") and golem_by_name(target.trim_prefix("golem:")).is_empty():
		return I18n.t("No such golem.")
	if target == "ship" and not G.sys("constructs").voyage.is_empty():
		return I18n.t("The skiff is at sea.")
	if target.begins_with("golem:") and bool(golem_by_name(target.trim_prefix("golem:")).get("away", false)):
		return I18n.t("It is away.")
	var cur: String = str(target_parts(target).get(slot, ""))
	if cur != "" and G.gold < int(data.get("swap_gold", 20)):
		return I18n.t("Swapping costs %d gold.") % int(data.get("swap_gold", 20))
	return ""


func fit(target: String, slot: String, id: String) -> String:
	var why := fit_block(target, slot, id)
	if why != "":
		return why
	var tp := target_parts(target)
	var cur: String = str(tp.get(slot, ""))
	if cur != "":
		G.gold -= int(data.get("swap_gold", 20))
		bin[cur] = int(bin.get(cur, 0)) + 1
	bin[id] = int(bin.get(id, 0)) - 1
	if int(bin[id]) <= 0:
		bin.erase(id)
	tp[slot] = id
	G.message.emit(I18n.t("FOUNDRY: %s fitted.") % part_name(id))
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


func unfit(target: String, slot: String) -> String:
	if not in_town():
		return I18n.t("Fit parts in a town -- the work needs a bench.")
	var tp := target_parts(target)
	var cur: String = str(tp.get(slot, ""))
	if cur == "":
		return ""
	tp.erase(slot)
	bin[cur] = int(bin.get(cur, 0)) + 1
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return I18n.t("%s goes back in the bin.") % part_name(cur)


# ---- gifts and aptitude ------------------------------------------------------------------------------------------

func _combine(into: Dictionary, eff: Dictionary) -> void:
	for k in eff:
		var key := str(k)
		if key in G.ADDITIVE_KEYS or key.begins_with("craft_"):
			into[key] = float(into.get(key, 0.0)) + float(eff[k])
		else:
			into[key] = float(into.get(key, 1.0)) * float(eff[k])


func gifts(target: String) -> Dictionary:
	var out := {}
	for slot in target_parts(target):
		var p: Dictionary = parts().get(str(target_parts(target)[slot]), {})
		_combine(out, p.get("effect", {}))
	return out


func mods(target: String) -> Dictionary:
	var out := {}
	for slot in target_parts(target):
		var p: Dictionary = parts().get(str(target_parts(target)[slot]), {})
		for k in p.get("mods", {}):
			out[k] = float(out.get(k, 1.0)) * float(p["mods"][k])
	return out


func aptitude(target: String) -> Dictionary:
	## {skill: 0-100}: what the parts (and a golem's own kind) make it good at
	var GN = G.sys("genome")
	var out := {}
	for sk in GN.skills():
		out[sk] = 0.0
	for slot in target_parts(target):
		var p: Dictionary = parts().get(str(target_parts(target)[slot]), {})
		for sk in p.get("apt", {}):
			out[sk] = float(out.get(sk, 0.0)) + float(p["apt"][sk])
	if target.begins_with("golem:"):
		var c := golem_by_name(target.trim_prefix("golem:"))
		var M = G.sys("menagerie")
		var rw: Dictionary = GN.data.get("role_weights", {}).get(M.rid(c), {})
		for sk in rw:
			out[sk] = float(out.get(sk, 0.0)) + float(rw[sk]) * float(data.get("role_share", 0.45))
		var CR = G.sys("crew")
		if CR != null:
			for sk in out:
				out[sk] = float(out[sk]) + CR.focus_bonus(c, str(sk))
	for sk in out:
		out[sk] = clampf(float(out[sk]), 0.0, 100.0)
	return out


func breakdown(target: String) -> Array:
	## same rows as Genome.breakdown; level -1 means "from parts"
	var GN = G.sys("genome")
	var ap := aptitude(target)
	var rows := []
	for sk in ap:
		rows.append([str(sk), float(ap[sk])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var out := []
	for r in rows:
		var sk := str(r[0])
		out.append({"skill": sk, "name": GN.skill_name(sk), "score": float(r[1]), "grade": GN.grade(float(r[1])), "gene": "", "level": -1,
			"good_for": I18n.t(str(GN.skills()[sk].get("good_for", "")))})
	return out


func suited_text(target: String) -> String:
	var GN = G.sys("genome")
	var best := []
	for r in breakdown(target):
		if float(r["score"]) >= 35.0 and best.size() < 2:
			best.append(r)
	if best.is_empty():
		return I18n.t("No strong gift yet -- fit better parts.")
	return I18n.t("Best at %s -- good for %s.") % [", ".join(best.map(func(r): return "%s (%s)" % [r["name"], r["grade"]])), str(best[0]["good_for"])]


# ---- runes on constructs -----------------------------------------------------------------------------------------

func rune_sockets() -> int:
	if not G.skill_known("runecraft"):
		return 0
	var lvl: int = G.skill_level("runecraft")
	var n := 0
	for row in data.get("rune_sockets", [[0, 1]]):
		if lvl >= int(row[0]):
			n = int(row[1])
	return n


func runes_on(target: String) -> Array:
	if target == "mech":
		return mech_runes
	if target.begins_with("golem:"):
		var c := golem_by_name(target.trim_prefix("golem:"))
		if c.get("runes") is Array:
			return c["runes"]
	return []


func _set_runes(target: String, list: Array) -> void:
	if target == "mech":
		mech_runes = list
	elif target.begins_with("golem:"):
		var c := golem_by_name(target.trim_prefix("golem:"))
		if not c.is_empty():
			if list.is_empty():
				c.erase("runes")
			else:
				c["runes"] = list


func inscribe_chance(target: String, rune: String) -> float:
	var I: Dictionary = G.runes_data().get("inscribe", {})
	var c := float(I.get("base", 0.62)) + float(G.skill_level("runecraft") - int(G.rune_info(rune).get("difficulty", 0))) * float(I.get("per_level", 0.06))
	c -= 0.05 * float(runes_on(target).size())
	c += G.tech_effect("craft_success", 0.0) + G.tech_effect("craft_success_runecraft", 0.0)
	if G._god_craft():
		return 1.0
	return clampf(c, float(I.get("min", 0.15)), float(I.get("max", 0.97)))


func inscribe_block(target: String, rune: String) -> String:
	if not G.skill_known("runecraft"):
		return I18n.t("You don't know how to set a rune. ") + G.craft_teacher_hint("runecraft")
	if G.count(rune) <= 0 or not G.is_rune(rune):
		return I18n.t("You have no %s.") % G.item_name(rune)
	if runes_on(target).size() >= rune_sockets():
		return I18n.t("It holds no more runes (%d). Scour it, or grow your craft.") % rune_sockets()
	if target.begins_with("golem:") and golem_by_name(target.trim_prefix("golem:")).is_empty():
		return I18n.t("No such golem.")
	return ""


func inscribe(target: String, rune: String, roll: float = -1.0) -> Dictionary:
	var why := inscribe_block(target, rune)
	if why != "":
		return {"ok": false, "text": why}
	var chance := inscribe_chance(target, rune)
	var r := randf() if roll < 0.0 else roll
	var diff := int(G.rune_info(rune).get("difficulty", 0))
	G.remove_item(rune, 1)
	if r >= chance:
		G.add_skill_xp("runecraft", (8.0 + diff * 3.0) * 0.4, "a cracked rune")
		var t := I18n.t("The %s cracks under the chisel.") % G.item_name(rune)
		G.message.emit(t)
		return {"ok": true, "success": false, "text": t}
	var list := runes_on(target).duplicate()
	list.append(rune)
	_set_runes(target, list)
	G.add_skill_xp("runecraft", 8.0 + diff * 3.0, "inscribing")
	var t2 := I18n.t("The %s sinks into the metal.") % G.rune_mark(rune)
	G.message.emit(t2)
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return {"ok": true, "success": true, "text": t2}


func scour_cost(target: String) -> int:
	return int(G.runes_data().get("inscribe", {}).get("scour_gold", 25)) * runes_on(target).size()


func scour(target: String) -> String:
	var n := runes_on(target).size()
	if n == 0:
		return I18n.t("There's nothing carved on it.")
	if G.gold < scour_cost(target):
		return I18n.t("Scouring costs %d gold.") % scour_cost(target)
	G.gold -= scour_cost(target)
	_set_runes(target, [])
	G.stats_changed.emit()
	G.familiar_changed.emit()
	return I18n.t("The runes are ground away (%d).") % n


func rune_pool(list: Array, part: String = "wear") -> Dictionary:
	## the runes' gifts pooled the way worn runes are: a second rune of one kind counts for less
	var P: Dictionary = G.runes_data().get("wear_pool", {})
	var pool := {}
	for r in list:
		var e: Dictionary = G.rune_info(str(r)).get(part, {})
		for k in e:
			var add := float(e[k]) if (k in G.ADDITIVE_KEYS or str(k).begins_with("craft_")) else float(e[k]) - 1.0
			pool[k] = float(pool.get(k, 0.0)) + add * G._rune_q(str(r))
	var pd := {}
	for k in pool:
		var v := float(pool[k])
		if k in G.ADDITIVE_KEYS or str(k).begins_with("craft_"):
			pd[k] = v
			continue
		var a := absf(v)
		var soft := float(P.get("soft", 0.08))
		if a > soft:
			a = soft + (a - soft) * float(P.get("after", 0.4))
		a = minf(a, float(P.get("cap", 0.25)))
		pd[k] = 1.0 + signf(v) * a
	return pd


func rune_line(target: String) -> String:
	var have := runes_on(target)
	if have.is_empty():
		return I18n.t("Runes: none (%d socket%s).") % [rune_sockets(), "" if rune_sockets() == 1 else "s"]
	return I18n.t("Runes: %s  (%d of %d)") % [" · ".join(have.map(func(r): return G.rune_mark(str(r)))), have.size(), rune_sockets()]


# ---- what it all gives -----------------------------------------------------------------------------------------

func effects() -> Array:
	var out := []
	var M = G.sys("menagerie")
	for b in G.beasts_out():
		if not bool(b.get("construct", false)):
			continue
		var t := "golem:" + str(b.get("name", ""))
		var eff := gifts(t)
		var rp := rune_pool(runes_on(t), "wear")
		if not rp.is_empty():
			_combine(eff, rp)
		if eff.is_empty():
			continue
		var one := {}
		M._scale(eff, M.beast_grow(b), one)
		out.append(one)
	return out


func mech_effects() -> Dictionary:
	var eff := gifts("mech")
	var rp := rune_pool(mech_runes, "weapon")
	if not rp.is_empty():
		_combine(eff, rp)
	return eff


func mech_drain_mult() -> float:
	return float(mods("mech").get("drain", 1.0))


func ship_mods() -> Dictionary:
	var m := mods("ship")
	return {"hours": float(m.get("hours", 1.0)), "loot": float(m.get("loot", 1.0)), "gold": float(m.get("gold", 1.0)), "insight": float(m.get("insight", 1.0))}


func part_effect_text(id: String) -> String:
	var p: Dictionary = parts().get(id, {})
	var M = G.sys("menagerie")
	var t := ""
	if not p.get("effect", {}).is_empty():
		t = M._eff_text(p["effect"])
	var mm: Dictionary = p.get("mods", {})
	var bits := []
	if mm.has("drain"):
		bits.append(I18n.t("qi drain -%d%%") % int(round((1.0 - float(mm["drain"])) * 100.0)))
	if mm.has("hours"):
		bits.append(I18n.t("voyages %d%% faster") % int(round((1.0 - float(mm["hours"])) * 100.0)))
	if mm.has("loot"):
		bits.append(I18n.t("cargo +%d%%") % int(round((float(mm["loot"]) - 1.0) * 100.0)))
	if mm.has("gold"):
		bits.append(I18n.t("gold +%d%%") % int(round((float(mm["gold"]) - 1.0) * 100.0)))
	if mm.has("insight"):
		bits.append(I18n.t("insight +%d%%") % int(round((float(mm["insight"]) - 1.0) * 100.0)))
	if not bits.is_empty():
		t = (t + ", " if t != "" else "") + ", ".join(bits)
	var ap := []
	for sk in p.get("apt", {}):
		ap.append("%s +%d" % [G.sys("genome").skill_name(str(sk)), int(p["apt"][sk])])
	return t + ("  ·  " + ", ".join(ap) if not ap.is_empty() else "")
