extends "res://scripts/systems/GameSystem.gd"
## Round 177: the genome. Robert, 2026-10-25: "the pet actions and abilities section needs work, maybe a skill breakdown toward
## what they would be good at ... allow for pairs to be from different species and randomized results for synergistic effects ...
## a gene splicer with the ability to modify the genes of pets."
## Every beast has ten genes (level 0-5). Eight make an APTITUDE breakdown (what it is good at, graded E to S) and each level
## gives a small real gift. Pairing two species may wake a SYNERGY (a named, randomly strong bonus) -- or a quirk. The Gene
## Splicer takes a sample from a beast and grafts it onto another, with the odds shown first.

var data := {}
var samples := []          # [{gene, level, from, species}]
var cool := {}             # beast name -> unix time it can give another sample
var splices := 0
var rng := RandomNumberGenerator.new()


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/genome.json")
	rng.randomize()


func reset() -> void:
	samples = []
	cool = {}
	splices = 0


func save_state() -> Dictionary:
	return {"samples": samples, "cool": cool, "splices": splices}


func load_state(d: Dictionary) -> void:
	reset()
	for s in d.get("samples", []):
		if s is Dictionary:
			samples.append({"gene": str(s.get("gene", "")), "level": int(s.get("level", 1)), "from": str(s.get("from", "")), "species": str(s.get("species", ""))})
	var cd = d.get("cool", {})
	if cd is Dictionary:
		for k in cd:
			cool[str(k)] = float(cd[k])
	splices = int(d.get("splices", 0))


func _f(grp: String, k: String, dflt: float) -> float:
	return float(data.get(grp, {}).get(k, dflt))


func skills() -> Dictionary:
	return data.get("skills", {})


func genes() -> Dictionary:
	return data.get("genes", {})


func gene_name(g: String) -> String:
	return I18n.t(str(genes().get(g, {}).get("name", g)))


func skill_name(s: String) -> String:
	return I18n.t(str(skills().get(s, {}).get("name", s)))


func max_level() -> int:
	return int(data.get("max_level", 5))


func cap_of(c: Dictionary) -> int:
	return max_level() + int(floor(float(c.get("blood", 0)) / 3.0))


# ---- genes ---------------------------------------------------------------------------------------------------------

func _weights(c: Dictionary) -> Dictionary:
	## how much each gene is wanted by this beast's role (a tracker leans to Nose, a guardian to Hide)
	var M = G.sys("menagerie")
	var rw: Dictionary = data.get("role_weights", {}).get(M.rid(c) if M != null else "", {})
	var out := {}
	for gk in genes():
		var sk := str(genes()[gk].get("skill", ""))
		out[gk] = 1.0 + (float(rw.get(sk, 0.0)) / 18.0 if sk != "" else -0.4)
	return out


func genes_of(c: Dictionary) -> Dictionary:
	if c.get("genes") is Dictionary and not (c["genes"] as Dictionary).is_empty():
		return c["genes"]
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(c.get("name", "")) + "|" + str(c.get("species", "")))
	var g := {}
	for gk in genes():
		g[gk] = 0
	var pts := int(data.get("base_points", 8)) + int(data.get("points_per_tier", 2)) * int(c.get("tier", 0)) + int(data.get("points_per_blood", 1)) * int(c.get("blood", 0))
	var w := _weights(c)
	var cap := cap_of(c)
	var guard := 0
	while pts > 0 and guard < 400:
		guard += 1
		var tot := 0.0
		for gk in g:
			if int(g[gk]) < cap:
				tot += maxf(0.15, float(w[gk]))
		if tot <= 0.0:
			break
		var roll := r.randf() * tot
		for gk in g:
			if int(g[gk]) >= cap:
				continue
			roll -= maxf(0.15, float(w[gk]))
			if roll <= 0.0:
				g[gk] = int(g[gk]) + 1
				pts -= 1
				break
	c["genes"] = g
	return g


func level(c: Dictionary, gk: String) -> int:
	return int(genes_of(c).get(gk, 0))


func set_level(c: Dictionary, gk: String, v: int) -> void:
	genes_of(c)[gk] = clampi(v, 0, cap_of(c))


# ---- aptitude ------------------------------------------------------------------------------------------------------

func aptitude(c: Dictionary) -> Dictionary:
	var M = G.sys("menagerie")
	var rw: Dictionary = data.get("role_weights", {}).get(M.rid(c) if M != null else "", {})
	var out := {}
	for sk in skills():
		var gk := str(skills()[sk].get("gene", ""))
		var sc: float = float(level(c, gk)) * float(data.get("per_gene_level", 9.0)) + float(rw.get(sk, 0.0)) * 0.45
		var CR = G.sys("crew")
		if CR != null:
			sc += CR.focus_bonus(c, str(sk))               # round 179: a focus the creature has worked at
		out[sk] = clampf(sc, 0.0, 100.0)
	return out


func grade(score: float) -> String:
	for row in data.get("grades", []):
		if score >= float(row[0]):
			return str(row[1])
	return "E"


func ranked(c: Dictionary) -> Array:
	var ap := aptitude(c)
	var out := []
	for sk in ap:
		out.append([str(sk), float(ap[sk])])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


func best(c: Dictionary, n: int = 2) -> Array:
	var out := []
	for row in ranked(c):
		if float(row[1]) >= 35.0 and out.size() < n:
			out.append(str(row[0]))
	return out


func suited_text(c: Dictionary) -> String:
	var b := best(c, 2)
	if b.is_empty():
		return I18n.t("No strong gift yet -- splice a gene or let it grow.")
	var parts := []
	for sk in b:
		parts.append("%s (%s)" % [skill_name(sk), grade(float(aptitude(c)[sk]))])
	var why := I18n.t(str(skills()[b[0]].get("good_for", "")))
	return I18n.t("Best at %s -- good for %s.") % [", ".join(parts), why]


func breakdown(c: Dictionary) -> Array:
	## every skill: {skill, name, score, grade, gene, level, good_for}
	var ap := aptitude(c)
	var out := []
	for row in ranked(c):
		var sk := str(row[0])
		var gk := str(skills()[sk].get("gene", ""))
		out.append({"skill": sk, "name": skill_name(sk), "score": float(ap[sk]), "grade": grade(float(ap[sk])), "gene": gk, "level": level(c, gk),
			"good_for": I18n.t(str(skills()[sk].get("good_for", "")))})
	return out


func extra_lines(c: Dictionary) -> Array:
	## synergy, quirk, temper, brood: the small print
	var out := []
	var CR = G.sys("crew")
	if CR != null:
		out.append_array(CR.lines(c))
	if bool(c.get("construct", false)):
		return out
	var sy = c.get("syn")
	if sy is Dictionary:
		out.append(I18n.t("Synergy: %s (%s) -- %s") % [syn_name(sy), I18n.t(strength_name(str(sy.get("str", "solid")))), _eff_text(syn_effect(c))])
	var q := str(c.get("quirk", ""))
	if q != "" and data.get("synergy", {}).get("quirks", {}).has(q):
		var qd: Dictionary = data["synergy"]["quirks"][q]
		out.append(I18n.t("Quirk: %s -- %s") % [I18n.t(str(qd.get("name", q))), I18n.t(str(qd.get("desc", "")))])
	for gk in ["temper", "brood"]:
		var lv := level(c, gk)
		if lv > 0:
			out.append("%s %d: %s" % [gene_name(gk), lv, I18n.t(str(genes()[gk].get("desc", "")))])
	return out


func _eff_text(eff: Dictionary) -> String:
	var M = G.sys("menagerie")
	return M._eff_text(eff) if M != null else ""


# ---- what genes give ---------------------------------------------------------------------------------------------

func _lvl_eff(eff: Dictionary, n: float) -> Dictionary:
	var o := {}
	for k in eff:
		var key := str(k)
		if key in G.ADDITIVE_KEYS or key.begins_with("craft_"):
			o[key] = float(eff[k]) * n
		else:
			o[key] = 1.0 + (float(eff[k]) - 1.0) * n
	return o


func skill_effect(sk: String, n: float) -> Dictionary:
	return _lvl_eff(skills().get(sk, {}).get("effect", {}), n)


func syn_name(sy: Dictionary) -> String:
	var k := "%s+%s" % [str(sy.get("a", "")), str(sy.get("b", ""))]
	var names: Dictionary = data.get("synergy", {}).get("names", {})
	return I18n.t(str(names.get(k, names.get("%s+%s" % [str(sy.get("b", "")), str(sy.get("a", ""))], k))))


func strength_row(sid: String) -> Array:
	for row in data.get("synergy", {}).get("strengths", []):
		if str(row[0]) == sid:
			return row
	return ["solid", "Solid", 1.0, 0.5]


func strength_name(sid: String) -> String:
	return str(strength_row(sid)[1])


func syn_effect(c: Dictionary) -> Dictionary:
	var sy = c.get("syn")
	if not (sy is Dictionary):
		return {}
	var m := float(strength_row(str(sy.get("str", "solid")))[2])
	var e := skill_effect(str(sy.get("a", "")), 2.0 * m)
	var e2 := skill_effect(str(sy.get("b", "")), 2.0 * m)
	for k in e2:
		if e.has(k):
			if str(k) in G.ADDITIVE_KEYS or str(k).begins_with("craft_"):
				e[k] = float(e[k]) + float(e2[k])
			else:
				e[k] = float(e[k]) * float(e2[k])
		else:
			e[k] = e2[k]
	return e


func gene_effects(c: Dictionary) -> Array:
	var out := []
	for sk in skills():
		var n := level(c, str(skills()[sk].get("gene", "")))
		if n > 0:
			out.append(skill_effect(str(sk), float(n)))
	var tl := level(c, "temper")
	if tl > 0:
		out.append(_lvl_eff(genes()["temper"].get("effect", {}), float(tl)))
	var se := syn_effect(c)
	if not se.is_empty():
		out.append(se)
	var q := str(c.get("quirk", ""))
	if q != "" and data.get("synergy", {}).get("quirks", {}).has(q):
		out.append(data["synergy"]["quirks"][q].get("effect", {}))
	return out


func effects() -> Array:
	var out := []
	var M = G.sys("menagerie")
	for b in G.beasts_out():
		if bool(b.get("construct", false)):
			continue                                      # built things get their gifts from their parts (Foundry)
		var grow: float = M.beast_grow(b)
		for e in gene_effects(b):
			var one := {}
			M._scale(e, grow, one)
			out.append(one)
	return out


# ---- inheritance and pairing -----------------------------------------------------------------------------------

func diverse(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	var ga := genes_of(a)
	var gb := genes_of(b)
	for gk in ga:
		if absi(int(ga[gk]) - int(gb.get(gk, 0))) >= 2:
			n += 1
	return n


func mixed(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("species", "")) != str(b.get("species", ""))


func synergy_chance(a: Dictionary, b: Dictionary) -> float:
	if not mixed(a, b):
		return 0.0
	var sg: Dictionary = data.get("synergy", {})
	var ch := float(sg.get("mixed_base", 0.35)) + float(sg.get("per_diverse", 0.08)) * float(diverse(a, b)) + float(sg.get("per_brood", 0.04)) * float(level(a, "brood") + level(b, "brood"))
	return clampf(ch, 0.0, float(sg.get("cap", 0.8)))


func strength_odds() -> Array:
	var out := []
	for row in data.get("synergy", {}).get("strengths", []):
		out.append([str(row[0]), str(row[1]), float(row[2]), float(row[3])])
	return out


func quirk_chance(a: Dictionary, b: Dictionary) -> float:
	## only a mixed pairing risks a quirk; two Brood-rich parents steady it
	if not mixed(a, b):
		return 0.0
	return clampf(float(data.get("synergy", {}).get("quirk", 0.25)) - 0.03 * float(level(a, "brood") + level(b, "brood")), 0.04, 0.5)


func pair_preview(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	if mixed(a, b):
		out.append(I18n.t("Two kinds: a synergy wakes %d%% of the time, a quirk %d%%.") % [int(round(synergy_chance(a, b) * 100.0)), int(round(quirk_chance(a, b) * 100.0))])
		var parts := []
		for r in strength_odds():
			parts.append("%s %d%%" % [I18n.t(str(r[1])), int(round(float(r[3]) * 100.0))])
		out.append(I18n.t("If it wakes: ") + ", ".join(parts))
		out.append(I18n.t("Hybrid vigor: %d%% for one gene to start a step higher.") % int(round(float(data.get("synergy", {}).get("hybrid_vigor", 0.2)) * 100.0)))
	else:
		out.append(I18n.t("Same kind: steadier, no synergy; genes pass from both parents."))
	out.append(I18n.t("Genes differ in %d places (more difference, more chance of a synergy).") % diverse(a, b))
	var ta := best(a, 1)
	var tb := best(b, 1)
	if not ta.is_empty() and not tb.is_empty():
		out.append(I18n.t("Likely to be good at %s or %s.") % [skill_name(ta[0]), skill_name(tb[0])])
	return out


func inherit_into(child: Dictionary, a: Dictionary, b: Dictionary) -> void:
	## called by Breeding.make_young: genes from both parents, a mutation or two, maybe a synergy or a quirk
	var ga := genes_of(a)
	var gb := genes_of(b)
	var g := {}
	var cap := max_level()
	for gk in genes():
		var la := int(ga.get(gk, 0))
		var lb := int(gb.get(gk, 0))
		var v := 0
		var r := rng.randf()
		if r < 0.4:
			v = la
		elif r < 0.8:
			v = lb
		else:
			v = int(round((la + lb) / 2.0))
		if rng.randf() < 0.18:
			v += 1 if rng.randf() < 0.6 else -1
		g[gk] = clampi(v, 0, cap)
	child["genes"] = g
	if mixed(a, b):
		var gl: Array = g.keys()
		if rng.randf() < float(data.get("synergy", {}).get("hybrid_vigor", 0.2)):
			var pk := str(gl[rng.randi() % gl.size()])
			g[pk] = mini(int(g[pk]) + 1, cap)
		if rng.randf() < synergy_chance(a, b):
			var r2 := ranked(child)
			var s1 := str(r2[0][0])
			var s2 := str(r2[1][0])
			var roll := rng.randf()
			var acc := 0.0
			var sid := "solid"
			for row in strength_odds():
				acc += float(row[3])
				if roll <= acc:
					sid = str(row[0])
					break
			child["syn"] = {"a": s1, "b": s2, "str": sid}
		if rng.randf() < quirk_chance(a, b):
			var qk: Array = data.get("synergy", {}).get("quirks", {}).keys()
			child["quirk"] = str(qk[rng.randi() % qk.size()])


# ---- the Gene Splicer ------------------------------------------------------------------------------------------

func max_samples() -> int:
	return 9999 if G.unlimited_stores() else int(_f("splicer", "max_samples", 12.0))


func splicer_open() -> String:
	## "" when it is usable, else why not
	if G.taming_level() < int(_f("splicer", "min_taming", 4.0)):
		return I18n.t("The splicer needs Taming %d.") % int(_f("splicer", "min_taming", 4.0))
	return ""


func sample_block(c: Dictionary, gk: String) -> String:
	var w := splicer_open()
	if w != "":
		return w
	if level(c, gk) <= 0:
		return I18n.t("%s has no %s to give.") % [str(c.get("name", "")), gene_name(gk)]
	if float(c.get("bond", 0.0)) < _f("splicer", "min_bond", 25.0):
		return I18n.t("%s must trust you more first (bond %d).") % [str(c.get("name", "")), int(_f("splicer", "min_bond", 25.0))]
	if samples.size() >= max_samples():
		return I18n.t("The sample case is full (%d).") % samples.size()
	var left: float = float(cool.get(str(c.get("name", "")), 0.0)) - G._now()
	if left > 0.0 and not G.tester_unlocked():
		return I18n.t("%s needs a rest (%s).") % [str(c.get("name", "")), G._dur(left)]
	return ""


func take_sample(c: Dictionary, gk: String) -> String:
	var why := sample_block(c, gk)
	if why != "":
		return why
	samples.append({"gene": gk, "level": level(c, gk), "from": str(c.get("name", "")), "species": str(c.get("species", ""))})
	cool[str(c.get("name", ""))] = G._now() + _f("splicer", "sample_cool_hours", 2.0) * 3600.0
	G.message.emit(I18n.t("SPLICER: a sample of %s (%s %d) is in the case.") % [c.get("name", ""), gene_name(gk), level(c, gk)])
	G.stats_changed.emit()
	return ""


func splice_cost(c: Dictionary, gk: String) -> int:
	return int(_f("splicer", "gold_per_level", 25.0)) * (level(c, gk) + 1)


func splice_block(c: Dictionary, si: int) -> String:
	var w := splicer_open()
	if w != "":
		return w
	if si < 0 or si >= samples.size():
		return I18n.t("Pick a sample.")
	var gk := str(samples[si]["gene"])
	if bool(c.get("construct", false)):
		return I18n.t("%s is built, not born.") % str(c.get("name", ""))
	if level(c, gk) >= cap_of(c):
		return I18n.t("%s already has %s at its limit (%d).") % [str(c.get("name", "")), gene_name(gk), cap_of(c)]
	if int(samples[si]["level"]) < level(c, gk):
		return I18n.t("That sample is weaker than %s's own %s.") % [str(c.get("name", "")), gene_name(gk)]
	if G.gold < splice_cost(c, gk):
		return I18n.t("It costs %d gold.") % splice_cost(c, gk)
	return ""


func splice_odds(c: Dictionary, si: int, cat: String = "") -> Dictionary:
	## {ok, reject, unstable, nothing} -- all shown before you press the button
	if si < 0 or si >= samples.size():
		return {"ok": 0.0, "reject": 0.0, "unstable": 0.0, "nothing": 1.0}
	var sp: Dictionary = data.get("splicer", {})
	var gk := str(samples[si]["gene"])
	var lv := level(c, gk)
	var p := float(sp.get("base", 0.5)) + float(sp.get("per_taming", 0.02)) * float(G.taming_level()) + float(sp.get("per_bond", 0.0025)) * float(c.get("bond", 0.0))
	p -= float(sp.get("per_target_level", 0.07)) * float(lv)
	if str(samples[si].get("species", "")) != str(c.get("species", "")):
		p -= float(sp.get("mixed_penalty", 0.06))
	p += float(sp.get("per_brood", 0.03)) * float(level(c, "brood"))
	var cd: Dictionary = sp.get("catalysts", {}).get(cat, {})
	p += float(cd.get("success", 0.0))
	p = clampf(p, 0.05, 0.95)
	var f := 1.0 - p
	var rj := f * float(sp.get("reject_share", 0.25))
	if bool(cd.get("reject_half", false)):
		rj *= 0.5
	var un := f * float(sp.get("unstable_share", 0.5))
	if bool(cd.get("no_unstable", false)):
		un = 0.0
	return {"ok": p, "reject": rj, "unstable": un, "nothing": maxf(0.0, f - rj - un)}


func odds_text(o: Dictionary) -> String:
	return I18n.t("Takes %d%%  ·  rejected %d%% (a step lost)  ·  unstable %d%% (wrong strand, maybe a quirk)  ·  nothing %d%%") % [
		int(round(float(o["ok"]) * 100.0)), int(round(float(o["reject"]) * 100.0)), int(round(float(o["unstable"]) * 100.0)), int(round(float(o["nothing"]) * 100.0))]


func splice(c: Dictionary, si: int, cat: String = "") -> String:
	var why := splice_block(c, si)
	if why != "":
		return why
	if cat != "" and G.count(cat) <= 0:
		return I18n.t("You have no %s.") % G.item_name(cat)
	var o := splice_odds(c, si, cat)
	var gk := str(samples[si]["gene"])
	var cost := splice_cost(c, gk)
	G.gold -= cost
	if cat != "":
		G.remove_item(cat, 1)
	samples.remove_at(si)
	splices += 1
	var nm := str(c.get("name", ""))
	var r := rng.randf()
	var msg := ""
	if r < float(o["ok"]):
		set_level(c, gk, level(c, gk) + 1)
		msg = I18n.t("SPLICER: it takes! %s's %s rises to %d.") % [nm, gene_name(gk), level(c, gk)]
	elif r < float(o["ok"]) + float(o["reject"]):
		set_level(c, gk, level(c, gk) - 1)
		msg = I18n.t("SPLICER: rejected. %s's %s falls to %d.") % [nm, gene_name(gk), level(c, gk)]
	elif r < float(o["ok"]) + float(o["reject"]) + float(o["unstable"]):
		var others := []
		for k2 in genes():
			if str(k2) != gk and level(c, str(k2)) < cap_of(c):
				others.append(str(k2))
		if others.is_empty():
			msg = I18n.t("SPLICER: nothing took. The sample is spent.")
		else:
			var wk := str(others[rng.randi() % others.size()])
			set_level(c, wk, level(c, wk) + 1)
			msg = I18n.t("SPLICER: unstable -- it landed on the wrong strand. %s's %s rises to %d instead.") % [nm, gene_name(wk), level(c, wk)]
		if not others.is_empty() and str(c.get("quirk", "")) == "" and rng.randf() < 0.5:
			var qk: Array = data.get("synergy", {}).get("quirks", {}).keys()
			c["quirk"] = str(qk[rng.randi() % qk.size()])
			msg += " " + I18n.t("It has a quirk now.")
	else:
		msg = I18n.t("SPLICER: nothing took. The sample is spent.")
	G.message.emit(msg)
	G.log_event("gene_splice", {"name": nm, "gene": gk})
	G.stats_changed.emit()
	G.familiar_changed.emit()
	return msg


func suppress_block(c: Dictionary, gk: String) -> String:
	var w := splicer_open()
	if w != "":
		return w
	if level(c, gk) <= 0:
		return I18n.t("%s has nothing of %s to quiet.") % [str(c.get("name", "")), gene_name(gk)]
	if G.gold < splice_cost(c, gk):
		return I18n.t("It costs %d gold.") % splice_cost(c, gk)
	return ""


func suppress(c: Dictionary, gk: String) -> String:
	## quiet a gene by a step (always works); the freed strength is yours to re-graft from a fresh sample
	var why := suppress_block(c, gk)
	if why != "":
		return why
	G.gold -= splice_cost(c, gk)
	set_level(c, gk, level(c, gk) - 1)
	if samples.size() < max_samples():
		samples.append({"gene": gk, "level": level(c, gk) + 1, "from": str(c.get("name", "")), "species": str(c.get("species", ""))})
	var msg := I18n.t("SPLICER: %s's %s is quieted to %d. The strand is kept as a sample.") % [str(c.get("name", "")), gene_name(gk), level(c, gk)]
	G.message.emit(msg)
	G.stats_changed.emit()
	return msg


func clear_quirk(c: Dictionary) -> String:
	if str(c.get("quirk", "")) == "":
		return I18n.t("No quirk to clear.")
	if G.gold < 100:
		return I18n.t("It costs %d gold.") % 100
	G.gold -= 100
	c.erase("quirk")
	G.stats_changed.emit()
	return I18n.t("SPLICER: the quirk is smoothed away.")
