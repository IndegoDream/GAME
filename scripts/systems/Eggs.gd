extends "res://scripts/systems/GameSystem.gd"
## Round 177: beast eggs and bloodlines.
## Robert, 2026-10-25: "allow for user to find beast eggs maybe they will be great bloodline beast or can take some of the bloodline
## resources to grow stronger."
## Eggs turn up on new floors, in chests, in the beds and now and then from a kill; a good Scout among your beasts finds more.
## Carry a few, warm them in the nest (a few real hours, shortened by every place you enter) and a young one hatches. Some eggs
## hold a BLOODLINE: it shows once they have warmed a while. Bloodline Essence (from chests and beast kills) deepens any beast's
## blood; a bloodline-born one can take it twice as far.

var data := {}
var eggs := []             # [{id, sp, bl, pot, found, warm, ready, seen}]
var found := 0
var hatched := 0
var next_id := 1
var rng := RandomNumberGenerator.new()


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/eggs.json")
	rng.randomize()
	var it: Dictionary = data.get("item", {})
	if not it.is_empty():
		G.items[str(it["id"])] = {"name": it.get("name", ""), "type": str(it.get("type", "material")), "value": int(it.get("value", 100)), "desc": it.get("desc", "")}


func reset() -> void:
	eggs = []
	found = 0
	hatched = 0
	next_id = 1


func save_state() -> Dictionary:
	return {"eggs": eggs, "found": found, "hatched": hatched, "next_id": next_id}


func load_state(d: Dictionary) -> void:
	reset()
	for e in d.get("eggs", []):
		if e is Dictionary:
			eggs.append({"id": int(e.get("id", 0)), "sp": str(e.get("sp", "")), "bl": str(e.get("bl", "")), "pot": int(e.get("pot", 0)), "found": str(e.get("found", "")),
				"warm": bool(e.get("warm", false)), "start": float(e.get("start", 0.0)), "ready": float(e.get("ready", 0.0)), "seen": bool(e.get("seen", false))})
	found = int(d.get("found", 0))
	hatched = int(d.get("hatched", 0))
	next_id = maxi(int(d.get("next_id", 1)), 1)


func _f(k: String, dflt: float) -> float:
	return float(data.get(k, dflt))


func carry() -> int:
	return 9999 if G.unlimited_stores() else int(data.get("carry", 6))


func slots() -> int:
	return 3 if G.taming_level() >= int(data.get("third_slot_taming", 10)) else int(data.get("slots", 2))


func warming() -> int:
	var n := 0
	for e in eggs:
		if bool(e["warm"]):
			n += 1
	return n


# ---- finding -------------------------------------------------------------------------------------------------------

func scout_bonus() -> float:
	## the best Scout among the beasts at your side (0-1)
	var GN = G.sys("genome")
	if GN == null:
		return 0.0
	var best := 0.0
	for b in G.beasts_out():
		best = maxf(best, float(GN.aptitude(b).get("scout", 0.0)) / 100.0)
	return best


func find_chance(kind: String) -> float:
	var f: Dictionary = data.get("find", {})
	var base := float(f.get(kind, 0.0))
	if base <= 0.0:
		return 0.0
	var ch := (base + float(f.get("per_depth", 0.002)) * float(G.depth)) * (1.0 + float(f.get("scout", 0.12)) * 10.0 * scout_bonus() / 3.0)
	return clampf(ch, 0.0, float(f.get("cap", 0.5)))


func species_pool() -> Array:
	var M = G.sys("menagerie")
	var out := []
	for sp in ["cave_hare", "tunnel_boar", "moss_stag", "ember_salamander", "burrow_mole", "steel_crow"]:
		if G.enemies.has(sp):
			out.append(sp)
	for s in M.data.get("new_species", []):
		var sid := str(s.get("id", ""))
		if int(s.get("floor", 1)) <= maxi(G.depth, 1) and G.enemies.has(sid):
			out.append(sid)
	return out


func bloodline_chance() -> float:
	return clampf(_f("bloodline_chance", 0.12) + _f("bloodline_per_depth", 0.01) * float(G.depth) + 0.1 * scout_bonus(), 0.0, _f("bloodline_cap", 0.4))


func lay(kind: String = "", force_bl: bool = false) -> Dictionary:
	## make one egg and put it in the carry-box (if there is room)
	var pool := species_pool()
	if pool.is_empty():
		return {}
	var sp := str(pool[rng.randi() % pool.size()])
	var bl := ""
	var pot := 0
	if force_bl or rng.randf() < bloodline_chance():
		var bk: Array = data.get("bloodlines", {}).keys()
		bl = str(bk[rng.randi() % bk.size()])
		var roll := rng.randf()
		var acc := 0.0
		pot = 1
		for row in data.get("potential", [[1, 1.0]]):
			acc += float(row[1])
			if roll <= acc:
				pot = int(row[0])
				break
	var e := {"id": next_id, "sp": sp, "bl": bl, "pot": pot, "found": G.current_level, "warm": false, "start": 0.0, "ready": 0.0, "seen": false}
	if bl != "" and rng.randf() < scout_bonus() * 0.5:
		e["seen"] = true                     # a good nose smells the blood at once
	next_id += 1
	found += 1
	eggs.append(e)
	var nm := str(data.get("egg_names", ["Speckled"])[rng.randi() % data.get("egg_names", ["Speckled"]).size()])
	G.message.emit(I18n.t("EGG: you find a %s egg (%s).") % [nm.to_lower(), I18n.t(str(G.enemies.get(sp, {}).get("name", sp)))] + (" " + I18n.t("It hums faintly -- a bloodline?") if bool(e["seen"]) and bl != "" else ""))
	G.log_event("egg_found", {"sp": sp, "bloodline": bl})
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return e


func on_event(kind: String, d: Dictionary) -> void:
	var ess: Dictionary = data.get("essence", {})
	if kind == "enter_level":
		for e in eggs:
			if bool(e["warm"]):
				e["ready"] = maxf(float(e["start"]), float(e["ready"]) - _f("visit_cut_secs", 900.0))
		if str(d.get("id", "")).begins_with("floor") and eggs.size() < carry() and rng.randf() < find_chance("enter_floor"):
			lay("floor")
	elif kind == "chest":
		if eggs.size() < carry() and rng.randf() < find_chance("chest"):
			lay("chest")
		if rng.randf() < float(ess.get("chest", 0.1)):
			G.add_item(str(ess.get("item", "blood_essence")), 1)
	elif kind == "harvest":
		if eggs.size() < carry() and rng.randf() < find_chance("harvest"):
			lay("bed")
	elif kind == "kill":
		if eggs.size() < carry() and rng.randf() < find_chance("kill"):
			lay("kill")
		if rng.randf() < float(ess.get("kill", 0.025)):
			G.add_item(str(ess.get("item", "blood_essence")), 1)


# ---- warming and hatching --------------------------------------------------------------------------------------

func left(e: Dictionary) -> float:
	return maxf(0.0, float(e.get("ready", 0.0)) - G._now())


func progress(e: Dictionary) -> float:
	if not bool(e["warm"]):
		return 0.0
	var total := maxf(1.0, float(e["ready"]) - float(e["start"]))
	return clampf(1.0 - left(e) / total, 0.0, 1.0)


func is_revealed(e: Dictionary) -> bool:
	return bool(e.get("seen", false)) or progress(e) >= _f("reveal_at", 0.5)


func by_id(id: int) -> int:
	for i in eggs.size():
		if int(eggs[i]["id"]) == id:
			return i
	return -1


func warm_block(e: Dictionary) -> String:
	if bool(e["warm"]):
		return I18n.t("Already warming.")
	if warming() >= slots():
		return I18n.t("The nest is full (%d of %d).") % [warming(), slots()]
	if not (G.havens.has(G.current_level) or G.tester_unlocked()):
		return I18n.t("Warm eggs in a town -- they need a quiet roof.")
	return ""


func warm(id: int) -> String:
	var i := by_id(id)
	if i < 0:
		return ""
	var why := warm_block(eggs[i])
	if why != "":
		return why
	var now: float = G._now()
	eggs[i]["warm"] = true
	eggs[i]["start"] = now
	eggs[i]["ready"] = now + _f("hours", 3.0) * 3600.0
	G.message.emit(I18n.t("EGG: it settles in the nest. About %s.") % G._dur(_f("hours", 3.0) * 3600.0))
	G.familiar_changed.emit()
	return ""


func cool_egg(id: int) -> String:
	var i := by_id(id)
	if i < 0:
		return ""
	eggs[i]["warm"] = false
	eggs[i]["start"] = 0.0
	eggs[i]["ready"] = 0.0
	return I18n.t("You take it out of the nest; it starts over.")


func hatch_block(e: Dictionary) -> String:
	if not bool(e["warm"]):
		return I18n.t("Warm it first.")
	if left(e) > 0.0 and not G.tester_unlocked():
		return I18n.t("Not yet -- about %s more.") % G._dur(left(e))
	if not G.can_tame_more():
		return I18n.t("There is no room for another beast (Contracts %d of %d). Release one or train Taming.") % [G.beast_count(), G.contract_cap()]
	return ""


func hatch(id: int) -> String:
	var i := by_id(id)
	if i < 0:
		return ""
	var e: Dictionary = eggs[i]
	var why := hatch_block(e)
	if why != "":
		return why
	var BR = G.sys("breeding")
	var M = G.sys("menagerie")
	var sp := str(e["sp"])
	var rid: String = M.role_id(sp)
	if rid == "":
		var rk: Array = M.data.get("roles", {}).keys()
		rid = str(rk[rng.randi() % rk.size()])
	var nm: String = BR._pick_name()
	var c := {"species": sp, "name": nm, "bond": _f("start_bond", 10.0), "tier": 0, "out": false, "role": rid, "gen": 0, "born": G._now(), "egg": true}
	if str(e["bl"]) != "":
		c["bl"] = str(e["bl"])
		c["blood"] = int(e["pot"])
	eggs.remove_at(i)
	G.contracts.append(c)
	hatched += 1
	G.taming_xp("breed")
	var gains: Array = data.get("essence", {}).get("hatch", [1, 2])
	G.add_item(str(data.get("essence", {}).get("item", "blood_essence")), rng.randi_range(int(gains[0]), int(gains[1])) if str(e["bl"]) != "" else 0)
	G.log_event("beast_born", {"name": nm, "species": sp, "gen": 0, "variant": "", "egg": true})
	G.message.emit(I18n.t("EGG: %s hatches!") % nm + (" " + I18n.t("A %s bloodline, blood %d.") % [I18n.t(str(data["bloodlines"][str(e["bl"])]["name"])), int(e["pot"])] if str(e["bl"]) != "" else ""))
	G.note_place(I18n.t("Hatched ") + nm)
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


# ---- blood -----------------------------------------------------------------------------------------------------

func blood_max(c: Dictionary) -> int:
	return int(data.get("blood_max_line", 6)) if str(c.get("bl", "")) != "" else int(data.get("blood_max", 3))


func feed_cost(c: Dictionary) -> int:
	return int(data.get("feed_base", 1)) + int(c.get("blood", 0))


func feed_block(c: Dictionary) -> String:
	if bool(c.get("construct", false)):
		return I18n.t("%s is built, not born.") % str(c.get("name", ""))
	if int(c.get("blood", 0)) >= blood_max(c):
		return I18n.t("%s's blood can go no deeper (%d).") % [str(c.get("name", "")), blood_max(c)]
	var it := str(data.get("essence", {}).get("item", "blood_essence"))
	if G.count(it) < feed_cost(c):
		return I18n.t("It needs %d Bloodline Essence (you have %d).") % [feed_cost(c), G.count(it)]
	return ""


func feed(c: Dictionary) -> String:
	var why := feed_block(c)
	if why != "":
		return why
	G.remove_item(str(data.get("essence", {}).get("item", "blood_essence")), feed_cost(c))
	c["blood"] = int(c.get("blood", 0)) + 1
	G.message.emit(I18n.t("BLOOD: %s grows stronger (blood %d).") % [c.get("name", ""), int(c["blood"])])
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


func blood_mult(c: Dictionary) -> float:
	return 1.0 + _f("blood_line_mult", 0.04) * float(int(c.get("blood", 0)))


func lines(c: Dictionary) -> Array:
	var out := []
	var bl := str(c.get("bl", ""))
	var bd: Dictionary = data.get("bloodlines", {}).get(bl, {})
	if not bd.is_empty():
		out.append(I18n.t("Bloodline: %s -- %s") % [I18n.t(str(bd.get("name", bl))), I18n.t(str(bd.get("desc", "")))])
	if int(c.get("blood", 0)) > 0 or bl != "":
		out.append(I18n.t("Blood %d of %d  ·  +%d%% strength") % [int(c.get("blood", 0)), blood_max(c), int(round((blood_mult(c) - 1.0) * 100.0))])
	return out


func effects() -> Array:
	var out := []
	var M = G.sys("menagerie")
	for b in G.beasts_out():
		var bd: Dictionary = data.get("bloodlines", {}).get(str(b.get("bl", "")), {})
		if bd.is_empty():
			continue
		var eff := {}
		var n := 1.0 + float(int(b.get("blood", 0)))
		for k in bd.get("effect", {}):
			var key := str(k)
			var v := float(bd["effect"][k])
			eff[key] = v * n if (key in G.ADDITIVE_KEYS or key.begins_with("craft_")) else 1.0 + (v - 1.0) * n
		var one := {}
		M._scale(eff, M.beast_grow(b), one)
		out.append(one)
	return out


func status_text(e: Dictionary) -> String:
	var spn := I18n.t(str(G.enemies.get(str(e["sp"]), {}).get("name", e["sp"])))
	var st := ""
	if bool(e["warm"]):
		st = I18n.t("warming, %d%% (%s left)") % [int(round(progress(e) * 100.0)), G._dur(left(e))] if left(e) > 0.0 else I18n.t("ready to hatch")
	else:
		st = I18n.t("in your carry-box")
	var bl := ""
	if str(e["bl"]) != "":
		bl = ("  ·  " + I18n.t("bloodline: ") + I18n.t(str(data["bloodlines"][str(e["bl"])]["name"])) + " " + I18n.t("(blood %d)") % int(e["pot"])) if is_revealed(e) else "  ·  " + I18n.t("something stirs inside…")
	return "%s  --  %s%s" % [spn, st, bl]
