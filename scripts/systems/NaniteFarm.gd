extends "res://scripts/systems/GameSystem.gd"
## Round 177: the nanite farm.
## Robert, 2026-10-25: "allow for user to build a nanite farm and learn skills to improve self replication so it doesnt become stagnant."
## Vats at home hold a culture. It replicates (logistic: fast while empty, slow when full). Left alone it STAGNATES: diversity drains,
## efficiency falls. Events ask for a choice (odds shown); skills slow the drain, speed replication and unlock strains. Harvest for
## shards, swarm growth or qi. Time runs while you are away (up to a day).

var data := {}
var vats := 0
var pop := 0.0
var diversity := 1.0
var lore := 0
var spent := {}            # skill id -> level
var strain := "builder"
var found := {"builder": true, "weaver": true}
var event := {}            # pending {id}
var next_event := 0.0      # minutes until the next one
var bonus := 0.0           # a pending harvest bonus multiplier
var harvests := 0
var last_t := 0.0
var rng := RandomNumberGenerator.new()
var _acc := 0.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/farm.json")
	rng.randomize()


func reset() -> void:
	vats = 0
	pop = 0.0
	diversity = 1.0
	lore = 0
	spent = {}
	strain = "builder"
	found = {"builder": true, "weaver": true}
	event = {}
	next_event = 0.0
	bonus = 0.0
	harvests = 0
	last_t = 0.0
	_acc = 0.0


func save_state() -> Dictionary:
	return {"vats": vats, "pop": pop, "diversity": diversity, "lore": lore, "spent": spent, "strain": strain, "found": found, "event": event,
		"next_event": next_event, "bonus": bonus, "harvests": harvests, "last_t": G._now()}


func load_state(d: Dictionary) -> void:
	reset()
	vats = int(d.get("vats", 0))
	pop = float(d.get("pop", 0.0))
	diversity = clampf(float(d.get("diversity", 1.0)), 0.0, 1.0)
	lore = int(d.get("lore", 0))
	var sp = d.get("spent", {})
	if sp is Dictionary:
		for k in sp:
			if data.get("skills", {}).has(str(k)):
				spent[str(k)] = int(sp[k])
	strain = str(d.get("strain", "builder"))
	var fd = d.get("found", {})
	if fd is Dictionary:
		for k in fd:
			if data.get("strains", {}).has(str(k)):
				found[str(k)] = true
	if not data.get("strains", {}).has(strain) or not found.has(strain):
		strain = "builder"
	var ev = d.get("event", {})
	event = ev if ev is Dictionary and data.get("events", {}).has(str(ev.get("id", ""))) else {}
	next_event = float(d.get("next_event", 0.0))
	bonus = float(d.get("bonus", 0.0))
	harvests = int(d.get("harvests", 0))
	last_t = float(d.get("last_t", 0.0))
	if vats > 0 and last_t > 0.0:
		var away := minf(maxf(G._now() - last_t, 0.0), float(data.get("offline_max_hours", 24)) * 3600.0)
		_advance(away / 60.0, false)


func _f(k: String, dflt: float) -> float:
	return float(data.get(k, dflt))


func lv(sid: String) -> int:
	return int(spent.get(sid, 0))


func open_block() -> String:
	if G.nanite_tier() < int(data.get("min_tier", 1)):
		return I18n.t("Your nanites are not grown enough to keep a culture (reach swarm tier %d).") % int(data.get("min_tier", 1))
	if not G.has_home():
		return I18n.t("A farm needs a home of your own to keep it.")
	return ""


func cap() -> float:
	return float(vats) * float(data.get("vats", {}).get("cap_each", 60.0)) * (1.0 + 0.25 * float(lv("lattice")))


func strain_def() -> Dictionary:
	return data.get("strains", {}).get(strain, {})


func rate() -> float:
	return _f("rate_per_min", 0.045) * (1.0 + 0.2 * float(lv("rep"))) * float(strain_def().get("rate", 1.0))


func efficiency() -> float:
	var fl := _f("eff_floor", 0.35)
	return fl + (1.0 - fl) * clampf(diversity, 0.0, 1.0)


func stagnate_rate() -> float:
	return _f("stagnate_per_min", 0.0018) * pow(0.85, float(lv("repair")))


func state_word() -> String:
	if vats <= 0:
		return I18n.t("no vats")
	if diversity >= 0.75:
		return I18n.t("thriving")
	if diversity >= 0.5:
		return I18n.t("steady")
	if diversity >= 0.3:
		return I18n.t("stagnating")
	return I18n.t("stagnant")


# ---- vats ------------------------------------------------------------------------------------------------------

func vat_cost() -> Dictionary:
	var v: Dictionary = data.get("vats", {})
	return {"items": v.get("cost", {}), "gold": int(v.get("gold", 80)) + int(v.get("gold_step", 60)) * vats}


func vat_block() -> String:
	var w := open_block()
	if w != "":
		return w
	if vats >= int(data.get("vats", {}).get("max", 6)):
		return I18n.t("You have all %d vats.") % vats
	var c := vat_cost()
	var miss := []
	for it in c["items"]:
		if G.count(str(it)) < int(c["items"][it]):
			miss.append("%s %d/%d" % [G.item_name(str(it)), G.count(str(it)), int(c["items"][it])])
	if G.gold < int(c["gold"]):
		miss.append("%d gold" % int(c["gold"]))
	if not miss.is_empty():
		return I18n.t("Needs: ") + ", ".join(miss)
	return ""


func vat_text() -> String:
	var c := vat_cost()
	var parts := []
	for it in c["items"]:
		parts.append("%d %s" % [int(c["items"][it]), G.item_name(str(it))])
	parts.append("%d gold" % int(c["gold"]))
	return ", ".join(parts)


func build_vat() -> String:
	var w := vat_block()
	if w != "":
		return w
	var c := vat_cost()
	for it in c["items"]:
		G.remove_item(str(it), int(c["items"][it]))
	G.gold -= int(c["gold"])
	vats += 1
	if vats == 1:
		pop = _f("seed", 6.0)
		last_t = G._now()
		next_event = rng.randf_range(float(data["event_minutes"][0]), float(data["event_minutes"][1]))
		G.message.emit(I18n.t("FARM: the first vat is sealed and seeded. It begins to replicate."))
	else:
		G.message.emit(I18n.t("FARM: vat %d is sealed. There is room for %d.") % [vats, int(cap())])
	G.log_event("farm_vat", {"n": vats})
	G.stats_changed.emit()
	return ""


# ---- time ------------------------------------------------------------------------------------------------------

func _advance(minutes: float, allow_events: bool = true) -> void:
	if vats <= 0 or minutes <= 0.0:
		return
	var left := minutes
	while left > 0.0:
		var step := minf(left, 5.0)
		left -= step
		var c := cap()
		if c > 0.0:
			pop = clampf(pop + rate() * pop * (1.0 - pop / c) * efficiency() * step, 0.0, c)
		diversity = clampf(diversity - stagnate_rate() * step, 0.0, 1.0)
		if pop < 1.0:
			pop = 1.0                              # the culture never quite dies out
		if event.is_empty():
			var sooner: float = 1.0 + 0.15 * float(lv("diversify"))
			next_event -= step * sooner * (1.0 / _f("event_low_div_mult", 0.6) if diversity < 0.5 else 1.0)
			if next_event <= 0.0:
				if allow_events or true:
					_raise_event()
				next_event = rng.randf_range(float(data["event_minutes"][0]), float(data["event_minutes"][1]))


func tick(delta: float) -> void:
	if vats <= 0:
		return
	_acc += delta
	if _acc >= 5.0:
		var m := _acc / 60.0
		_acc = 0.0
		_advance(m)
		last_t = G._now()


func on_event(kind: String, _d: Dictionary) -> void:
	if kind == "enter_level" and vats > 0 and not event.is_empty():
		pass


func _raise_event() -> void:
	var ok := []
	for eid in data.get("events", {}):
		var e: Dictionary = data["events"][eid]
		if diversity <= float(e.get("min_div", 1.0)) and diversity >= 0.0 and diversity <= float(e.get("min_div", 1.0)) and diversity >= 1.0 - float(e.get("max_div", 1.0)) - 1.0:
			ok.append(str(eid))
	# rut only when diversity is low; surge only when it is healthy; stray and blight any time
	var pool := []
	for eid2 in data.get("events", {}):
		var e2: Dictionary = data["events"][eid2]
		if str(eid2) == "rut" and diversity > float(e2.get("max_div", 0.6)):
			continue
		if str(eid2) == "surge" and diversity < float(e2.get("min_div", 0.4)):
			continue
		pool.append(str(eid2))
	if str(pool.size()) == "0":
		return
	var pick := str(pool[rng.randi() % pool.size()])
	if diversity < 0.5 and pool.has("rut") and rng.randf() < 0.6:
		pick = "rut"
	event = {"id": pick}
	G.message.emit(I18n.t("FARM: %s -- the vats need a decision.") % I18n.t(str(data["events"][pick]["title"])))
	G.stats_changed.emit()


func event_def() -> Dictionary:
	return data.get("events", {}).get(str(event.get("id", "")), {})


func choice_block(ch: Dictionary) -> String:
	for it in ch.get("cost", {}):
		if G.count(str(it)) < int(ch["cost"][it]):
			return I18n.t("Needs %d %s.") % [int(ch["cost"][it]), G.item_name(str(it))]
	return ""


func outcome_odds(ch: Dictionary) -> Array:
	## [{p, text}] -- shown before you choose; mutate improves the odds of a new line
	var out := []
	for o in ch.get("outcomes", []):
		var p := float(o.get("p", 1.0))
		if bool(o.get("strain", false)) and unfound().size() > 0:
			p = clampf(p + 0.1 * float(lv("mutate")), 0.0, 0.95)
		out.append({"o": o, "p": p})
	var tot := 0.0
	for r in out:
		tot += float(r["p"])
	for r in out:
		r["p"] = float(r["p"]) / maxf(tot, 0.0001)
	return out


func odds_text(ch: Dictionary) -> String:
	var parts := []
	for r in outcome_odds(ch):
		var o: Dictionary = r["o"]
		var fx := []
		if o.has("div") and float(o["div"]) != 0.0:
			fx.append(I18n.t("diversity %+d") % int(round(float(o["div"]) * 100.0)))
		if o.has("pop_mult"):
			fx.append(I18n.t("colony %+d%%") % int(round((float(o["pop_mult"]) - 1.0) * 100.0)))
		if bool(o.get("strain", false)):
			fx.append(I18n.t("a new line"))
		if o.has("lore"):
			fx.append(I18n.t("%+d lore") % int(o["lore"]))
		if o.has("harvest_bonus"):
			fx.append(I18n.t("harvest x%.1f") % float(o["harvest_bonus"]))
		if o.has("integ_gift"):
			fx.append(I18n.t("swarm growth"))
		parts.append("%d%%: %s" % [int(round(float(r["p"]) * 100.0)), ", ".join(fx) if not fx.is_empty() else I18n.t("nothing changes")])
	return "  |  ".join(parts)


func unfound() -> Array:
	var out := []
	for sid in data.get("strains", {}):
		if bool(data["strains"][sid].get("found", false)) and not found.has(str(sid)):
			out.append(str(sid))
	return out


func resolve(cid: String, roll: float = -1.0) -> String:
	if event.is_empty():
		return ""
	var ev := event_def()
	var ch := {}
	for c in ev.get("choices", []):
		if str(c.get("id", "")) == cid:
			ch = c
	if ch.is_empty():
		return ""
	var why := choice_block(ch)
	if why != "":
		return why
	for it in ch.get("cost", {}):
		G.remove_item(str(it), int(ch["cost"][it]))
	var r := rng.randf() if roll < 0.0 else roll
	var chosen: Dictionary = {}
	var acc := 0.0
	for row in outcome_odds(ch):
		acc += float(row["p"])
		chosen = row["o"]
		if r <= acc:
			break
	var boost := 1.0 + 0.25 * float(lv("diversify"))
	var dv := float(chosen.get("div", 0.0))
	if dv > 0.0:
		dv *= boost
	diversity = clampf(diversity + dv, 0.0, 1.0)
	if chosen.has("pop_mult"):
		pop = clampf(pop * float(chosen["pop_mult"]), 1.0, maxf(cap(), 1.0))
	if chosen.has("lore"):
		lore += int(chosen["lore"])
	if chosen.has("harvest_bonus"):
		bonus = float(chosen["harvest_bonus"])
	if chosen.has("integ_gift"):
		G.integrate(float(chosen["integ_gift"]), "the nanite farm")
	var t := I18n.t(str(chosen.get("text", "")))
	if bool(chosen.get("strain", false)):
		var uf := unfound()
		if not uf.is_empty():
			var sid := str(uf[rng.randi() % uf.size()])
			found[sid] = true
			t += " " + I18n.t("New line: %s.") % I18n.t(str(data["strains"][sid]["name"]))
	event = {}
	G.message.emit("FARM: " + t)
	G.log_event("farm_choice", {"event": str(ev.get("title", "")), "choice": cid})
	G.stats_changed.emit()
	return t


# ---- yield and growth ------------------------------------------------------------------------------------------

func harvest_preview() -> Dictionary:
	if vats <= 0:
		return {"take": 0.0, "shards": 0, "integ": 0.0, "qi": 0.0}
	var keep := maxf(_f("seed", 6.0), pop * _f("harvest_keep", 0.35))
	var take := maxf(pop - keep, 0.0) * efficiency() * (bonus if bonus > 0.0 else 1.0) * float(strain_def().get("yield", 1.0))
	var sd := strain_def()
	return {"take": take, "shards": int(floor(take * float(sd.get("shards", 1.0)) / _f("shard_per", 40.0) * 3.0)),
		"integ": take * float(sd.get("integ", 0.2)) * 0.12 * pow(1.3, float(lv("link"))), "qi": take * float(sd.get("qi", 0.0)) * 0.02 * G.qi_to_next() * 0.05}


func harvest_block() -> String:
	if vats <= 0:
		return I18n.t("Build a vat first.")
	var p := harvest_preview()
	if int(p["shards"]) <= 0 and float(p["integ"]) < 0.5 and float(p["qi"]) < 0.5:
		return I18n.t("Not enough grown yet.")
	return ""


func harvest() -> String:
	var why := harvest_block()
	if why != "":
		return why
	var p := harvest_preview()
	var keep := maxf(_f("seed", 6.0), pop * _f("harvest_keep", 0.35))
	pop = keep
	bonus = 0.0
	harvests += 1
	var bits := []
	if int(p["shards"]) > 0:
		G.add_item("nanite_shard", int(p["shards"]), false)
		bits.append("%d %s" % [int(p["shards"]), G.item_name("nanite_shard")])
	if float(p["integ"]) > 0.0:
		G.integrate(float(p["integ"]), "the nanite farm")
		bits.append(I18n.t("swarm growth"))
	if float(p["qi"]) >= 0.5:
		G.qi = minf(G.qi + float(p["qi"]), G.qi_to_next())
		bits.append(I18n.t("%d qi") % int(p["qi"]))
	if harvests % 2 == 0:
		lore += 1
	var t := I18n.t("FARM: you draw the vats down -- %s.") % ", ".join(bits)
	G.message.emit(t)
	G.log_event("farm_harvest", {"n": harvests})
	G.stats_changed.emit()
	return t


func set_strain(sid: String) -> String:
	if not found.has(sid):
		return I18n.t("You have not found that line yet.")
	strain = sid
	G.stats_changed.emit()
	return I18n.t("The vats are given over to the %s.") % I18n.t(str(data["strains"][sid]["name"]))


# ---- skills ----------------------------------------------------------------------------------------------------

func skill_cost(sid: String) -> int:
	var sd: Dictionary = data.get("skills", {}).get(sid, {})
	var l := lv(sid)
	if l >= int(sd.get("max", 1)):
		return -1
	return int(sd["cost"][l])


func skill_block(sid: String) -> String:
	var c := skill_cost(sid)
	if c < 0:
		return I18n.t("At its limit.")
	if lore < c:
		return I18n.t("Needs %d lore (you have %d).") % [c, lore]
	return ""


func learn(sid: String) -> String:
	var w := skill_block(sid)
	if w != "":
		return w
	lore -= skill_cost(sid)
	spent[sid] = lv(sid) + 1
	G.message.emit(I18n.t("FARM: %s grows to %d.") % [I18n.t(str(data["skills"][sid]["name"])), lv(sid)])
	G.stats_changed.emit()
	return ""


# ---- what it gives you -----------------------------------------------------------------------------------------

func effects() -> Array:
	if vats <= 0:
		return []
	var P: Dictionary = data.get("passive", {})
	var v := minf(float(P.get("swarm_per_pop", 0.0004)) * pop * efficiency(), float(P.get("cap", 0.08)))
	return [{"swarm_mult": 1.0 + v}]


func status_lines() -> Array:
	var out := []
	if vats <= 0:
		return out
	out.append(I18n.t("Colony %d of %d  ·  diversity %d%% (%s)  ·  efficiency %d%%  ·  line: %s") % [int(pop), int(cap()), int(round(diversity * 100.0)), state_word(), int(round(efficiency() * 100.0)), I18n.t(str(strain_def().get("name", strain)))])
	return out
