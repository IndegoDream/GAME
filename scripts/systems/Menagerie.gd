extends "res://scripts/systems/GameSystem.gd"
## Round 141b: beasts with roles, wayfarers who can swear to you.
## Robert, 2026-10-17: "We need more variety of beast companions, they should have more function and use, and human
## companions that can maybe end up a party member."
##   BEASTS    every tameable animal has a ROLE (data/menagerie.json): a small passive gift that grows with the bond, and a
##             DEED you can ask of it on a cooldown (a buff, a heal, or a few of its finds). 26 new tameable species wander
##             the floors (place_wild), 0-2 a floor, in the band of floors where they belong.
##   HUMANS    ten WAYFARERS wait in the towns. Anyone can take them on (no long friendship needed). Each has a gift while
##             they travel with you, a deed, and TRUST: it grows as you fight, descend and use their deed together, and a
##             gift works at 60%..100% by trust. Reach their oath floor at trust 60 and they ask to SWEAR: a sworn companion
##             adds a second gift for good, can be called from any town, and their deed comes back 30% sooner.
## State saved: trust, sworn, deepest floor with each, deed cooldowns.

var data := {}
var trust := {}            # name -> 0..100
var sworn := {}            # name -> true
var deep := {}             # name -> deepest floor reached with them in the party
var cool := {}             # "b:Name" / "h:Name" -> unix time the deed is ready again
var _acc := 0.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/menagerie.json")
	forms = load_json("res://data/forms.json")
	for rid in data.get("roles", {}):
		var b: Dictionary = data["roles"][rid].get("deed", {}).get("buff", {})
		if not b.is_empty():
			G.buff_names[str(b.get("id", ""))] = str(b.get("name", ""))
	for w in data.get("wayfarers", []):
		var b2: Dictionary = w.get("deed", {}).get("buff", {})
		if not b2.is_empty():
			G.buff_names[str(b2.get("id", ""))] = str(b2.get("name", ""))


var forms := {}


func form_of(b: Dictionary) -> Dictionary:
	## round 153: what a beast has become -- {} until 'fierce'. {stage, title, color, awakened, awaken, desc}
	var st: int = G.familiar_stage(b)
	if st < 2:
		return {}
	var f: Dictionary = forms.get("roles", {}).get(rid(b), {})
	if f.is_empty():
		return {}
	var c: Array = f.get("color", [0.7, 1.0, 0.8])
	return {"stage": st, "title": str(f.get("title3" if st >= 3 else "title2", "")), "color": Color(float(c[0]), float(c[1]), float(c[2])),
		"awakened": st >= 3, "awaken": f.get("awaken", {}), "desc": str(f.get("desc", ""))}


func reset() -> void:
	trust = {}
	sworn = {}
	deep = {}
	cool = {}
	_acc = 0.0


func save_state() -> Dictionary:
	return {"trust": trust, "sworn": sworn, "deep": deep, "cool": cool}


func load_state(d: Dictionary) -> void:
	reset()
	for k in d.get("trust", {}):
		trust[str(k)] = clampf(float(d["trust"][k]), 0.0, 100.0)
	for k in d.get("sworn", {}):
		if bool(d["sworn"][k]):
			sworn[str(k)] = true
	for k in d.get("deep", {}):
		deep[str(k)] = int(d["deep"][k])
	for k in d.get("cool", {}):
		cool[str(k)] = float(d["cool"][k])


# ---- beasts -------------------------------------------------------------------------------------------------------------

func role_id(species: String) -> String:
	return str(data.get("species_roles", {}).get(species, ""))


func rid(b: Dictionary) -> String:
	## round 161: a bred beast may carry a parent's role instead of its species' own
	var r := str(b.get("role", ""))
	if r != "" and data.get("roles", {}).has(r):
		return r
	return role_id(str(b.get("species", "")))


func role_of(b: Dictionary) -> Dictionary:
	return data.get("roles", {}).get(rid(b), {})


func beast_grow(b: Dictionary) -> float:
	var share := 1.0 if is_same(b, G.familiar) else float(G.party_data().get("beasts", {}).get("second_share", 0.6))
	var BR = G.sys("breeding")
	var lm: float = BR.line_mult(b) if BR != null else 1.0
	return (1.0 + float(b.get("bond", 0.0)) / 100.0) * G.familiar_effect_mult(b) * share * lm


func _scale(eff: Dictionary, grow: float, out: Dictionary) -> void:
	for k in eff:
		var key := str(k)
		if key in G.ADDITIVE_KEYS or key.begins_with("craft_"):
			out[key] = float(eff[k]) * grow
		else:
			out[key] = 1.0 + (float(eff[k]) - 1.0) * grow


func trust_of(name: String) -> float:
	return float(trust.get(name, 0.0))


func is_sworn(name: String) -> bool:
	return bool(sworn.get(name, false))


func effects() -> Array:
	var out := []
	for b in G.beasts_out():
		var r := role_of(b)
		if r.is_empty():
			continue
		var one := {}
		_scale(r.get("effect", {}), beast_grow(b), one)
		out.append(one)
		var fm := form_of(b)
		if bool(fm.get("awakened", false)):
			var aw := {}
			var share := 1.0 if is_same(b, G.familiar) else float(G.party_data().get("beasts", {}).get("second_share", 0.6))
			_scale(fm.get("awaken", {}), share, aw)
			out.append(aw)                                  # round 153: the awakened gift
	for s in G.party_slots():
		var name := str(G.cslot(s).get("name", ""))
		var w := wayfarer(name)
		if w.is_empty() or bool(G.cslot(s).get("away", false)):
			continue
		var f := 0.6 + 0.4 * trust_of(name) / 100.0
		var one2 := {}
		_scale(w.get("gift", {}), f, one2)
		out.append(one2)
		if is_sworn(name):
			var two := {}
			_scale(w.get("sworn_gift", {}), 1.0, two)
			out.append(two)
	return out


func _cool_key(kind: String, name: String) -> String:
	return kind + ":" + name


func _left(key: String) -> float:
	return maxf(0.0, float(cool.get(key, 0.0)) - G._now())


func beast_deed_info(b: Dictionary) -> Dictionary:
	var r := role_of(b)
	if r.is_empty():
		return {}
	var dd: Dictionary = r.get("deed", {})
	return {"role": str(r.get("name", "")), "role_desc": str(r.get("desc", "")), "name": str(dd.get("name", "")),
		"desc": str(dd.get("desc", "")), "left": _left(_cool_key("b", str(b.get("name", ""))))}


func _item_range(v) -> int:
	if v is Array and v.size() >= 2:
		return randi_range(int(v[0]), int(v[1]))
	return int(v)


func _do_effect(dd: Dictionary, who: String, finds: Array) -> String:
	## the shared part of a deed: a buff, a heal, some finds. Returns what happened, in words.
	var told := []
	var b: Dictionary = dd.get("buff", {})
	if not b.is_empty():
		G.add_buff(str(b.get("id", "")), b.get("effect", {}), float(b.get("secs", 60)))
		told.append(I18n.t("%s for %d seconds.") % [str(b.get("name", "")), int(b.get("secs", 60))])
	if float(dd.get("heal", 0.0)) > 0.0:
		var amt := maxi(1, int(round(G.max_hp() * float(dd["heal"]))))
		G.heal(amt)
		told.append(I18n.t("+%d life.") % amt)
	var it: Dictionary = dd.get("items", {})
	if not it.is_empty():
		var got := []
		if it.has("fixed"):
			for id in it["fixed"]:
				var n := _item_range(it["fixed"][id])
				if n > 0 and G.items.has(str(id)):
					G.add_item(str(id), n, false)
					got.append("%d %s" % [n, G.item_name(str(id))])
		elif not finds.is_empty():
			for i in _item_range(it.get("n", [2, 3])):
				var id2 := str(finds[randi() % finds.size()])
				if G.items.has(id2):
					G.add_item(id2, 1, false)
					got.append(G.item_name(id2))
		if not got.is_empty():
			told.append(I18n.t("Brought back: %s.") % ", ".join(got))
	if int(dd.get("beast_bond", 0)) > 0:
		for bb in G.beasts_out():
			G.grow_bond(float(dd["beast_bond"]), bb)
		told.append(I18n.t("Your beasts feel closer."))
	return "%s: %s" % [who, " ".join(told)]


func ask_beast(b: Dictionary) -> String:
	## "" nothing to ask; else the words to show
	var r := role_of(b)
	if r.is_empty():
		return ""
	var name := str(b.get("name", ""))
	var key := _cool_key("b", name)
	var left := _left(key)
	if left > 0.0:
		return I18n.t("%s needs a while yet (%s).") % [name, G._dur(left)]
	var dd: Dictionary = r.get("deed", {})
	var finds: Array = G.enemies.get(str(b.get("species", "")), {}).get("familiar", {}).get("finds", [])
	var told := _do_effect(dd, name, finds)
	cool[key] = G._now() + float(dd.get("cool", 300))
	G.grow_bond(2.0, b)
	G.taming_xp("find")
	G.log_event("beast_deed", {"name": name, "role": rid(b)})
	G.stats_changed.emit()
	return told


# ---- humans ---------------------------------------------------------------------------------------------------------------

func wayfarer(name: String) -> Dictionary:
	for w in data.get("wayfarers", []):
		if str(w.get("name", "")) == name:
			return w
	return {}


func is_wayfarer(name: String) -> bool:
	return not wayfarer(name).is_empty()


func human_deed_info(name: String) -> Dictionary:
	var w := wayfarer(name)
	if w.is_empty():
		return {}
	var dd: Dictionary = w.get("deed", {})
	return {"name": str(dd.get("name", "")), "desc": str(dd.get("desc", "")), "left": _left(_cool_key("h", name)),
		"trade": str(w.get("trade", "")), "sworn": is_sworn(name), "trust": trust_of(name)}


func ask_human(name: String) -> String:
	var w := wayfarer(name)
	if w.is_empty():
		return ""
	var key := _cool_key("h", name)
	var left := _left(key)
	if left > 0.0:
		return I18n.t("%s needs a while yet (%s).") % [name, G._dur(left)]
	var dd: Dictionary = w.get("deed", {})
	var told := _do_effect(dd, name, [])
	var mult := float(w.get("sworn_deed_cool", 0.7)) if is_sworn(name) else 1.0
	cool[key] = G._now() + float(dd.get("cool", 300)) * mult
	_gain(name, float(data.get("trust", {}).get("per_deed", 2.0)))
	G.warm_bond(name, 0.5)
	G.log_event("wayfarer_deed", {"name": name})
	G.stats_changed.emit()
	return told


func _gain(name: String, amount: float) -> void:
	var cap := float(data.get("trust", {}).get("max", 100))
	var before := trust_of(name)
	trust[name] = clampf(before + amount, 0.0, cap)
	if before < 60.0 and trust_of(name) >= 60.0 and not is_sworn(name):
		G.message.emit(I18n.t("TRUST: %s trusts you now. Reach floor %d together and they may ask something of you.") % [name, int(wayfarer(name).get("oath", {}).get("depth", 10))])


func party_wayfarers() -> Array:
	var out := []
	for s in G.party_slots():
		var nm := str(G.cslot(s).get("name", ""))
		if is_wayfarer(nm) and not bool(G.cslot(s).get("away", false)):
			out.append(nm)
	return out


func recruit(name: String, persona_text: String, home: String, tint: Color) -> String:
	## a wayfarer says yes to anyone who asks: no friendship needed. Starts at some trust.
	if not is_wayfarer(name) or G.in_party(name) >= 0:
		return "no"
	if not trust.has(name):
		trust[name] = 10.0
	deep[name] = maxi(int(deep.get(name, 0)), G.depth)
	return G.seat_companion(name, persona_text, home, tint)


func oath_ready(name: String) -> bool:
	var w := wayfarer(name)
	if w.is_empty() or is_sworn(name) or G.in_party(name) < 0:
		return false
	var o: Dictionary = w.get("oath", {})
	return trust_of(name) >= float(data.get("trust", {}).get("oath_trust", 60)) and int(deep.get(name, 0)) >= int(o.get("depth", 10))


func oath_text(name: String) -> String:
	return str(wayfarer(name).get("oath", {}).get("text", ""))


func swear(name: String) -> String:
	if not oath_ready(name):
		return ""
	sworn[name] = true
	trust[name] = 100.0
	G.warm_bond(name, 30.0)
	G.log_event("wayfarer_sworn", {"name": name})
	G.note_place("%s swore to you" % name)
	G.stats_changed.emit()
	G.companion_changed.emit()
	return str(wayfarer(name).get("sworn_text", ""))


func human_lines(name: String) -> Array:
	## what the Party page and the companion's dialog say about them
	var w := wayfarer(name)
	if w.is_empty():
		return []
	var out := []
	var di := human_deed_info(name)
	out.append(I18n.t("%s -- %s") % [str(w.get("trade", "")), I18n.t("sworn to you") if is_sworn(name) else I18n.t("trust %d / 100") % int(trust_of(name))])
	out.append(I18n.t("Gift: %s") % _eff_text(w.get("gift", {})))
	if is_sworn(name):
		out.append(I18n.t("Sworn gift: %s") % _eff_text(w.get("sworn_gift", {})))
	elif not oath_ready(name):
		var o: Dictionary = w.get("oath", {})
		out.append(I18n.t("They will ask to swear when trust is %d and you have reached floor %d together.") % [int(data.get("trust", {}).get("oath_trust", 60)), int(o.get("depth", 10))])
	out.append(I18n.t("Deed: %s -- %s%s") % [di.get("name", ""), di.get("desc", ""), (" (" + G._dur(float(di["left"])) + ")") if float(di.get("left", 0.0)) > 0.0 else ""])
	return out


func beast_lines(b: Dictionary) -> Array:
	var i := beast_deed_info(b)
	if i.is_empty():
		return []
	var out := [I18n.t("%s: %s") % [i["role"], i["role_desc"]]]
	var fm := form_of(b)
	if not fm.is_empty():
		out.append(I18n.t("Form: %s") % I18n.t(str(fm["title"])))
		if bool(fm["awakened"]):
			out.append(I18n.t("Awakened: %s (%s).") % [I18n.t(str(fm["desc"])), _eff_text(fm["awaken"])])
	out.append(I18n.t("Deed: %s -- %s%s") % [i["name"], i["desc"], (" (" + G._dur(float(i["left"])) + ")") if float(i["left"]) > 0.0 else ""])
	return out


const EFF_NAMES := {"sense_radius": "senses", "sight": "sight", "gather_chance": "gathering", "gather_bonus": "yields", "loot_luck": "drop luck",
	"heal_on_kill": "life per kill", "ward": "ward", "damage_taken": "damage taken", "damage_mult": "damage", "insight_mult": "insight",
	"move_mult": "speed", "bond_mult": "bonds", "crit_chance": "crits", "dodge_chance": "dodging", "meditate_mult": "sitting",
	"swarm_mult": "swarm", "qi_mult": "qi", "ranged_mult": "ranged damage", "craft_quality_smithing": "smithing quality",
	"keep_gold": "keeps your gold", "cleanse_speed": "cleansing"}


func _eff_text(eff: Dictionary) -> String:
	var parts := []
	for k in eff:
		var nm := I18n.t(str(EFF_NAMES.get(str(k), str(k))))
		var v := float(eff[k])
		if str(k) in G.ADDITIVE_KEYS or str(k).begins_with("craft_") or str(k) == "cleanse_speed":
			parts.append("%s +%s" % [nm, ("%d%%" % int(round(v * 100.0))) if v < 1.0 else str(snappedf(v, 0.1))])
		else:
			parts.append("%s %s%d%%" % [nm, "+" if v >= 1.0 else "", int(round((v - 1.0) * 100.0))])
	return ", ".join(parts)


# ---- the road --------------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_acc += delta
	if _acc < 15.0:
		return
	var per := float(data.get("trust", {}).get("per_minute", 0.4)) * _acc / 60.0
	_acc = 0.0
	for nm in party_wayfarers():
		_gain(nm, per)


func on_event(kind: String, d: Dictionary) -> void:
	if kind == "kill":
		for nm in party_wayfarers():
			_gain(nm, float(data.get("trust", {}).get("per_kill", 0.25)))
	elif kind == "enter_level" and str(d.get("id", "")).begins_with("floor"):
		for nm in party_wayfarers():
			if G.depth > int(deep.get(nm, 0)):
				deep[nm] = G.depth
				_gain(nm, float(data.get("trust", {}).get("per_new_floor", 1.5)))


# ---- the floor: wild beasts and waiting wayfarers ----------------------------------------------------------------------------

func _cells(lvl) -> Array:
	var cells: Array = lvl._floor_cells.keys().filter(func(c): return lvl.char_at(c) == "." and not lvl.on_road(lvl.cell_to_world(c)))
	if cells.is_empty():
		cells = lvl.spawns.get(".", []).duplicate()
	cells.sort()
	return cells


func wild_candidates(depth: int) -> Array:
	var band := int(data.get("wild", {}).get("band", 4))
	var out := []
	for s in data.get("new_species", []):
		var f := int(s.get("floor", 1))
		if f <= depth and f >= depth - band and G.enemies.has(str(s.get("id", ""))):
			out.append(str(s["id"]))
	return out


func place(lvl) -> void:
	## called by Level after its critters
	if lvl.is_town():
		_place_wayfarers(lvl)
		return
	var lid := str(lvl.level_id)
	if not lid.begins_with("floor"):
		return
	var depth := int(lvl.def.get("depth", G.depth))
	var cand := wild_candidates(depth)
	if cand.is_empty():
		return
	var cells := _cells(lvl)
	if cells.is_empty():
		return
	var W: Dictionary = data.get("wild", {})
	var n := 0
	for i in int(W.get("max", 2)):
		if lvl._rng.randf() < float(W.get("chance", 0.7)):
			n += 1
	for i in n:
		var cell: Vector2i = cells[lvl._rng.randi() % cells.size()]
		lvl._spawn_script("res://scripts/actors/Enemy.gd", lvl.cell_to_world(cell), {"type": cand[lvl._rng.randi() % cand.size()], "cell": cell})
		lvl._count("wild_beasts")


func _place_wayfarers(lvl) -> void:
	var cells := _cells(lvl)
	if cells.is_empty():
		return
	for w in data.get("wayfarers", []):
		var nm := str(w.get("name", ""))
		if not (lvl.level_id in w.get("towns", [])) or G.in_party(nm) >= 0 or G.realm < int(w.get("min_realm", 0)):
			continue
		var cell: Vector2i = cells[lvl._rng.randi() % cells.size()]
		var tint: Array = w.get("tint", [0.8, 0.8, 0.8])
		lvl._spawn_script("res://scripts/actors/NPC.gd", lvl.cell_to_world(cell), {"cell": cell, "role": "villager", "name": nm,
			"line": str(w.get("line", "")), "def": {"role": "villager", "name": nm, "line": str(w.get("line", "")),
			"persona": str(w.get("persona", "")), "can_travel": true, "wayfarer": true, "tint": tint}})
		lvl._count("wayfarers")


func wayfarer_home(name: String) -> String:
	var t: Array = wayfarer(name).get("towns", ["village"])
	return str(t[0]) if not t.is_empty() else "village"
