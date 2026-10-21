extends "res://scripts/systems/GameSystem.gd"
## Round 161: animal breeding.
## Robert, 2026-10-19: "Anything else we can introduce to the game before launch maybe animal breading".
## Two bonded beasts of yours can be paired in the stable (any town). They rest there while the egg-time runs (about four real
## hours; every place you enter shortens it) and then a young one hatches into your spirit space:
##   body    the species of one parent (a hybrid keeps a hint of the other's colour)
##   role    the gift and deed of one parent (rarely a surprise from any role)
##   trait   a small extra gift, inherited or new
##   gen     each generation is a little stronger (+3% a step, up to 8 generations)
##   mutation  a rare colour variant whose gifts are 25% stronger; it can run in the family
##   tree    who its parents and grandparents were
## Fair pay: nothing is sold or exclusive; the test kit hatches instantly.

var data := {}
var pairs := []            # [{"a": name, "b": name, "start": t, "ready": t}]
var born := 0
var best_gen := 0
var rng := RandomNumberGenerator.new()


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/breeding.json")
	rng.randomize()


func reset() -> void:
	pairs = []
	born = 0
	best_gen = 0


func save_state() -> Dictionary:
	return {"pairs": pairs, "born": born, "best_gen": best_gen}


func load_state(d: Dictionary) -> void:
	reset()
	for p in d.get("pairs", []):
		pairs.append({"a": str(p.get("a", "")), "b": str(p.get("b", "")), "start": float(p.get("start", 0.0)), "ready": float(p.get("ready", 0.0))})
	born = int(d.get("born", 0))
	best_gen = int(d.get("best_gen", 0))


func _f(k: String, dflt: float) -> float:
	return float(data.get(k, dflt))


func slots() -> int:
	return 2 if G.taming_level() >= int(data.get("second_stable_taming", 8)) else 1


func index_of(nm: String) -> int:
	for i in G.contracts.size():
		if str(G.contracts[i].get("name", "")) == nm:
			return i
	return -1


func in_stable(c: Dictionary) -> bool:
	return bool(c.get("breeding", false))


func _sp_name(sp: String) -> String:
	return str(G.enemies.get(sp, {}).get("name", sp))


# ---- pairing -------------------------------------------------------------------------------------------------------

func why_not(ia: int, ib: int) -> String:
	if ia == ib or ia < 0 or ib < 0 or ia >= G.contracts.size() or ib >= G.contracts.size():
		return I18n.t("Pick two different beasts.")
	var a: Dictionary = G.contracts[ia]
	var b: Dictionary = G.contracts[ib]
	if pairs.size() >= slots():
		return I18n.t("The stable is full (%d of %d).") % [pairs.size(), slots()]
	for c in [a, b]:
		var nm := str(c.get("name", ""))
		if bool(c.get("construct", false)):
			return I18n.t("%s is built, not born.") % nm
		if bool(c.get("away", false)):
			return I18n.t("%s is away.") % nm
		if in_stable(c):
			return I18n.t("%s is already in the stable.") % nm
		if float(c.get("bond", 0.0)) < _f("min_bond", 25.0):
			return I18n.t("%s must trust you more first (bond %d).") % [nm, int(_f("min_bond", 25.0))]
		var rest_left: float = float(c.get("bred_at", 0.0)) + _f("rest_hours", 6.0) * 3600.0 - G._now()
		if rest_left > 0.0 and not G.tester_unlocked():
			return I18n.t("%s needs to rest (%s).") % [nm, G._dur(rest_left)]
	if (a.get("parents", []) as Array).has(str(b.get("name", ""))) or (b.get("parents", []) as Array).has(str(a.get("name", ""))):
		return I18n.t("A parent and its young cannot be paired.")
	if not (G.havens.has(G.current_level) or G.tester_unlocked()):
		return I18n.t("Pair them in a town -- the stable needs a quiet roof.")
	return ""


func pair(ia: int, ib: int) -> String:
	var why := why_not(ia, ib)
	if why != "":
		return why
	var a: Dictionary = G.contracts[ia]
	var b: Dictionary = G.contracts[ib]
	var now: float = G._now()
	for i in [ia, ib]:
		var c: Dictionary = G.contracts[i]
		if bool(c.get("out", false)):
			G.rest_beast(i)
		c["breeding"] = true
	pairs.append({"a": str(a["name"]), "b": str(b["name"]), "start": now, "ready": now + _f("hours", 4.0) * 3600.0})
	G.log_event("beast_paired", {"a": str(a["name"]), "b": str(b["name"])})
	G.message.emit(I18n.t("STABLE: %s and %s settle in together. Something will hatch in about %s.") % [a["name"], b["name"], G._dur(_f("hours", 4.0) * 3600.0)])
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


func left(p: Dictionary) -> float:
	return maxf(0.0, float(p.get("ready", 0.0)) - G._now())


func separate(pi: int) -> String:
	if pi < 0 or pi >= pairs.size():
		return ""
	var p: Dictionary = pairs[pi]
	for nm in [p["a"], p["b"]]:
		var i := index_of(str(nm))
		if i >= 0:
			G.contracts[i].erase("breeding")
	pairs.remove_at(pi)
	G.familiar_changed.emit()
	return I18n.t("They go their ways again.")


func on_event(kind: String, _d: Dictionary) -> void:
	if kind == "enter_level":
		for p in pairs:
			var floor_t: float = float(p.get("start", 0.0)) + _f("min_hours", 0.5) * 3600.0
			p["ready"] = maxf(floor_t, float(p["ready"]) - _f("visit_cut_secs", 1200.0))


func hatch(pi: int) -> String:
	if pi < 0 or pi >= pairs.size():
		return ""
	var p: Dictionary = pairs[pi]
	if left(p) > 0.0 and not G.tester_unlocked():
		return I18n.t("Not yet -- about %s more.") % G._dur(left(p))
	if not G.can_tame_more():
		return I18n.t("There is no room for another beast (Contracts %d of %d). Release one or train Taming.") % [G.beast_count(), G.contract_cap()]
	var ia := index_of(str(p["a"]))
	var ib := index_of(str(p["b"]))
	if ia < 0 or ib < 0:
		pairs.remove_at(pi)
		return I18n.t("The pair is gone.")
	var a: Dictionary = G.contracts[ia]
	var b: Dictionary = G.contracts[ib]
	var young := make_young(a, b)
	for c in [a, b]:
		c.erase("breeding")
		c["bred_at"] = G._now()
		G.grow_bond(3.0, c)
	pairs.remove_at(pi)
	G.contracts.append(young)
	born += 1
	best_gen = maxi(best_gen, int(young.get("gen", 1)))
	G.taming_xp("breed")
	G.log_event("beast_born", {"name": young["name"], "species": young["species"], "gen": young["gen"], "variant": str(young.get("variant", ""))})
	G.message.emit(I18n.t("STABLE: %s hatches -- %s") % [young["name"], "; ".join(lineage_lines(young))])
	G.note_place(I18n.t("Raised ") + str(young["name"]))
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


# ---- the young one ------------------------------------------------------------------------------------------------

func _pick_name() -> String:
	var names: Array = data.get("names", ["Pip"])
	var taken: Array = G.contracts.map(func(c): return str(c.get("name", "")))
	var base := str(names[rng.randi() % names.size()])
	var nm := base
	var k := 2
	while nm in taken:
		nm = "%s %s" % [base, ["", "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][mini(k, 10)]]
		k += 1
		if k > 10:
			nm = "%s %d" % [base, k]
			if not (nm in taken):
				break
	return nm


func _tree_of(c: Dictionary, d: int) -> Dictionary:
	var o := {"n": str(c.get("name", ""))}
	var t: Dictionary = c.get("tree", {})
	if d > 0 and t.has("p"):
		var ps := []
		for q in t["p"]:
			ps.append(_prune(q, d - 1))
		o["p"] = ps
	return o


func _prune(t: Dictionary, d: int) -> Dictionary:
	var o := {"n": str(t.get("n", ""))}
	if d > 0 and t.has("p"):
		var ps := []
		for q in t["p"]:
			ps.append(_prune(q, d - 1))
		o["p"] = ps
	return o


func make_young(a: Dictionary, b: Dictionary) -> Dictionary:
	var M = G.sys("menagerie")
	var pick_a: bool = rng.randf() < 0.5
	var body: Dictionary = a if pick_a else b
	var other: Dictionary = b if pick_a else a
	var sp := str(body.get("species", ""))
	var mix := str(other.get("species", ""))
	if mix == sp:
		mix = ""
	var roles: Dictionary = M.data.get("roles", {})
	var rid := ""
	if rng.randf() < _f("surprise_role", 0.08):
		var rk: Array = roles.keys()
		rid = str(rk[rng.randi() % rk.size()])
	else:
		rid = M.rid(a if rng.randf() < 0.5 else b)
	var traits: Dictionary = data.get("traits", {})
	var tp := []
	for p in [a, b]:
		if str(p.get("trait", "")) != "":
			tp.append(str(p["trait"]))
	var tr := ""
	if not tp.is_empty() and rng.randf() < _f("trait_inherit", 0.55):
		tr = str(tp[rng.randi() % tp.size()])
	elif rng.randf() < _f("trait_new", 0.35):
		var tk: Array = traits.keys()
		tr = str(tk[rng.randi() % tk.size()])
	var gen := maxi(int(a.get("gen", 0)), int(b.get("gen", 0))) + 1
	var variants: Dictionary = data.get("variants", {})
	var vp := []
	for p2 in [a, b]:
		if str(p2.get("variant", "")) != "":
			vp.append(str(p2["variant"]))
	var vr := ""
	var mch := minf(_f("mutation_cap", 0.2), _f("mutation", 0.08) + _f("mutation_per_gen", 0.02) * float(gen))
	if not vp.is_empty() and rng.randf() < _f("variant_inherit", 0.25):
		vr = str(vp[rng.randi() % vp.size()])
	elif rng.randf() < mch:
		var vk: Array = variants.keys()
		vr = str(vk[rng.randi() % vk.size()])
	var nm := _pick_name()
	var strong: bool = float(a.get("bond", 0.0)) >= _f("strong_bond", 100.0) and float(b.get("bond", 0.0)) >= _f("strong_bond", 100.0)
	var c := {"species": sp, "name": nm, "bond": _f("start_bond_strong", 15.0) if strong else _f("start_bond", 10.0), "tier": 0, "out": false,
		"role": rid, "gen": gen, "parents": [str(a.get("name", "")), str(b.get("name", ""))], "born": G._now(),
		"tree": {"n": nm, "p": [_tree_of(a, 2), _tree_of(b, 2)]}}
	if mix != "":
		c["mix"] = mix
	if tr != "":
		c["trait"] = tr
	if vr != "":
		c["variant"] = vr
	return c


# ---- what it is worth ---------------------------------------------------------------------------------------------

func line_mult(c: Dictionary) -> float:
	var g := mini(int(c.get("gen", 0)), int(_f("gen_cap", 8.0)))
	var m := 1.0 + _f("gen_bonus", 0.03) * float(g)
	if str(c.get("variant", "")) != "":
		m *= _f("variant_mult", 1.25)
	return m


func effects() -> Array:
	var out := []
	var M = G.sys("menagerie")
	var traits: Dictionary = data.get("traits", {})
	for b in G.beasts_out():
		var tr := str(b.get("trait", ""))
		if tr == "" or not traits.has(tr):
			continue
		var one := {}
		M._scale(traits[tr].get("effect", {}), M.beast_grow(b), one)
		out.append(one)
	return out


func tint_for(c: Dictionary, base: Color) -> Color:
	var col := base
	var mix := str(c.get("mix", ""))
	if mix != "":
		var t: Array = G.enemies.get(mix, {}).get("tint", [])
		if t.size() >= 3:
			col = col.lerp(Color(float(t[0]), float(t[1]), float(t[2])), 0.45)
	var v := str(c.get("variant", ""))
	if v != "" and data.get("variants", {}).has(v):
		var vc: Array = data["variants"][v]["color"]
		col = col.lerp(Color(float(vc[0]), float(vc[1]), float(vc[2])), 0.55)
	return col


func variant_name(c: Dictionary) -> String:
	var v := str(c.get("variant", ""))
	return I18n.t(str(data.get("variants", {}).get(v, {}).get("name", ""))) if v != "" else ""


func lineage_lines(c: Dictionary) -> Array:
	var out := []
	var g := int(c.get("gen", 0))
	if g <= 0:
		return out
	out.append(I18n.t("Generation %d (gifts +%d%%)") % [g, int(round(_f("gen_bonus", 0.03) * float(mini(g, int(_f("gen_cap", 8.0)))) * 100.0))])
	var tr := str(c.get("trait", ""))
	if tr != "" and data.get("traits", {}).has(tr):
		var td: Dictionary = data["traits"][tr]
		out.append(I18n.t("Trait: %s -- %s") % [I18n.t(str(td.get("name", ""))), I18n.t(str(td.get("desc", "")))])
	if str(c.get("variant", "")) != "":
		out.append(I18n.t("Mutation: %s (gifts x%.2f)") % [variant_name(c), _f("variant_mult", 1.25)])
	if str(c.get("mix", "")) != "":
		out.append(I18n.t("Mixed blood: %s and %s") % [_sp_name(str(c.get("species", ""))).to_lower(), _sp_name(str(c["mix"])).to_lower()])
	return out


func tree_lines(c: Dictionary) -> Array:
	var out := []
	if c.has("tree"):
		_walk(c["tree"], 0, out)
	return out


func _walk(t: Dictionary, depth: int, out: Array) -> void:
	out.append(("   ".repeat(depth) + "- " if depth > 0 else "") + str(t.get("n", "")))
	for q in t.get("p", []):
		_walk(q, depth + 1, out)


func status_lines() -> Array:
	var out := []
	for p in pairs:
		var l := left(p)
		out.append("%s + %s  --  %s" % [p["a"], p["b"], I18n.t("ready to hatch") if l <= 0.0 else I18n.t("about %s left") % G._dur(l)])
	return out
