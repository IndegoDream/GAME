extends "res://scripts/systems/GameSystem.gd"
## Round 177: runes as tattoos.
## Robert, 2026-10-25: "allow runes to be used on constructs and to be utilised as tattoos."
## A rune is cut into a beast (in a town): its "wear" gift, pooled with the beast's other tattoos, leaning toward the placement
## you choose (brow, paw, flank, back). Slots follow Runecraft. A slip cracks the rune and the beast flinches (a little bond).

var data := {}
var cut := 0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/tattoos.json")


func reset() -> void:
	cut = 0


func save_state() -> Dictionary:
	return {"cut": cut}


func load_state(d: Dictionary) -> void:
	reset()
	cut = int(d.get("cut", 0))


func placements() -> Dictionary:
	return data.get("placements", {})


func place_name(p: String) -> String:
	return I18n.t(str(placements().get(p, {}).get("name", p)))


func slots() -> int:
	var FD = G.sys("foundry")
	return FD.rune_sockets() if FD != null else 0


func marks(c: Dictionary) -> Array:
	## [{rune, place}]
	var t = c.get("tattoos", [])
	return t if t is Array else []


func block(c: Dictionary, rune: String, place: String) -> String:
	if bool(c.get("construct", false)):
		return I18n.t("Built things take runes in the Foundry, not tattoos.")
	if not G.skill_known("runecraft"):
		return I18n.t("You don't know how to set a rune. ") + G.craft_teacher_hint("runecraft")
	if slots() <= 0:
		return I18n.t("No room to cut yet.")
	if marks(c).size() >= slots():
		return I18n.t("%s has no skin left to mark (%d). Scour one, or grow your craft.") % [str(c.get("name", "")), slots()]
	if not placements().has(place):
		return I18n.t("Pick where to cut it.")
	if G.count(rune) <= 0 or not G.is_rune(rune):
		return I18n.t("You have no %s.") % G.item_name(rune)
	if bool(c.get("away", false)):
		return I18n.t("%s is away.") % str(c.get("name", ""))
	if not (G.havens.has(G.current_level) or G.tester_unlocked() or G._god_craft()):
		return I18n.t("Tattoos are cut in a town, with the beast calm and still.")
	return ""


func odds(c: Dictionary, rune: String) -> Dictionary:
	var I: Dictionary = G.runes_data().get("inscribe", {})
	var p := float(I.get("base", 0.62)) + float(G.skill_level("runecraft") - int(G.rune_info(rune).get("difficulty", 0))) * float(I.get("per_level", 0.06))
	p -= 0.05 * float(marks(c).size())
	p += float(data.get("bond_help", 0.0015)) * float(c.get("bond", 0.0))
	p += G.tech_effect("craft_success", 0.0) + G.tech_effect("craft_success_runecraft", 0.0)
	p = clampf(p, float(I.get("min", 0.15)), float(I.get("max", 0.97)))
	if G._god_craft():
		p = 1.0
	var f := 1.0 - p
	return {"ok": p, "crack": f, "flinch": f * float(data.get("flinch", 0.5))}


func odds_text(o: Dictionary) -> String:
	return I18n.t("Takes %d%%  ·  cracks %d%% (the rune is lost; %d%% it flinches and loses a little bond)") % [int(round(float(o["ok"]) * 100.0)), int(round(float(o["crack"]) * 100.0)), int(round(float(o["flinch"]) * 100.0))]


func apply(c: Dictionary, rune: String, place: String, roll: float = -1.0) -> Dictionary:
	var why := block(c, rune, place)
	if why != "":
		return {"ok": false, "text": why}
	var o := odds(c, rune)
	var r := randf() if roll < 0.0 else roll
	var diff := int(G.rune_info(rune).get("difficulty", 0))
	G.remove_item(rune, 1)
	var nm := str(c.get("name", ""))
	if r >= float(o["ok"]):
		G.add_skill_xp("runecraft", (8.0 + diff * 3.0) * 0.4, "a cracked rune")
		var t := I18n.t("The %s cracks under the needle.") % G.item_name(rune)
		if r >= float(o["ok"]) + float(o["crack"]) - float(o["flinch"]):
			c["bond"] = maxf(0.0, float(c.get("bond", 0.0)) - float(data.get("flinch_loss", 1.0)))
			t += " " + I18n.t("%s flinches and trusts you a little less.") % nm
		G.message.emit(t)
		return {"ok": true, "success": false, "text": t}
	var list := marks(c).duplicate()
	list.append({"rune": rune, "place": place})
	c["tattoos"] = list
	cut += 1
	G.add_skill_xp("runecraft", 8.0 + diff * 3.0, "a tattoo")
	var t2 := I18n.t("%s wears the %s on its %s.") % [nm, G.rune_mark(rune), place_name(place).to_lower()]
	G.message.emit(t2)
	G.log_event("tattoo", {"name": nm, "rune": rune, "place": place})
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return {"ok": true, "success": true, "text": t2}


func scour_cost(c: Dictionary) -> int:
	return int(data.get("scour_gold", 25)) * marks(c).size()


func scour(c: Dictionary) -> String:
	if marks(c).is_empty():
		return I18n.t("There's nothing marked on it.")
	if G.gold < scour_cost(c):
		return I18n.t("Scouring costs %d gold.") % scour_cost(c)
	G.gold -= scour_cost(c)
	var n := marks(c).size()
	c.erase("tattoos")
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return I18n.t("%s's marks fade (%d).") % [str(c.get("name", "")), n]


func gifts(c: Dictionary) -> Dictionary:
	## the wear gift of every mark, leaning toward its placement, pooled
	var FD = G.sys("foundry")
	var lean := float(data.get("lean", 0.35))
	var shaped := []
	var out := {}
	for m in marks(c):
		var e: Dictionary = G.rune_info(str(m.get("rune", ""))).get("wear", {})
		var keys: Array = placements().get(str(m.get("place", "")), {}).get("keys", [])
		var adj := {}
		for k in e:
			var v := float(e[k])
			if str(k) in keys:
				if str(k) in G.ADDITIVE_KEYS or str(k).begins_with("craft_"):
					v *= 1.0 + lean
				else:
					v = 1.0 + (v - 1.0) * (1.0 + lean)
			adj[k] = v
		shaped.append(adj)
	# pool by hand so each mark keeps its quality and lean
	var pool := {}
	var P: Dictionary = G.runes_data().get("wear_pool", {})
	for i in shaped.size():
		var q: float = G._rune_q(str(marks(c)[i].get("rune", "")))
		for k in shaped[i]:
			var add := float(shaped[i][k]) if (k in G.ADDITIVE_KEYS or str(k).begins_with("craft_")) else float(shaped[i][k]) - 1.0
			pool[k] = float(pool.get(k, 0.0)) + add * q
	for k in pool:
		var v2 := float(pool[k])
		if k in G.ADDITIVE_KEYS or str(k).begins_with("craft_"):
			out[k] = v2
			continue
		var a := absf(v2)
		var soft := float(P.get("soft", 0.08))
		if a > soft:
			a = soft + (a - soft) * float(P.get("after", 0.4))
		a = minf(a, float(P.get("cap", 0.25)))
		out[k] = 1.0 + signf(v2) * a
	if FD == null:
		return {}
	return out


func effects() -> Array:
	var out := []
	for b in G.beasts_out():
		if marks(b).is_empty():
			continue
		var share := 1.0 if is_same(b, G.familiar) else float(G.party_data().get("beasts", {}).get("second_share", 0.6))
		var g := gifts(b)
		var one := {}
		for k in g:
			var key := str(k)
			one[key] = float(g[k]) * share if (key in G.ADDITIVE_KEYS or key.begins_with("craft_")) else 1.0 + (float(g[k]) - 1.0) * share
		out.append(one)
	return out


func lines(c: Dictionary) -> Array:
	var out := []
	if marks(c).is_empty():
		return out
	var parts := []
	for m in marks(c):
		parts.append("%s (%s)" % [G.rune_mark(str(m.get("rune", ""))), place_name(str(m.get("place", "")))])
	out.append(I18n.t("Tattoos: %s  ·  %d of %d") % [", ".join(parts), marks(c).size(), slots()])
	var M = G.sys("menagerie")
	out.append(I18n.t("They give: ") + M._eff_text(gifts(c)))
	return out
