extends "res://scripts/systems/GameSystem.gd"
## Round 179: the Crew -- every beast, construct and companion is unique, can be steered toward its strengths, and has a job
## while it is not out with you.
## Robert, 2026-10-25: "i want each pet and construct to be unique and modifiable toward their strengths" and "allow for them to
## tend the internal garden or to go out and train or gather, they can each have a job when not active with me, same for the companions."
## SPECIALTY: from its name -- a knack (job multipliers, a small gift while at your side). FOCUS: a skill you choose; work deepens it
## (levels add aptitude). JOB: rest, tend the gardens (plots ripen sooner, the inner world's flora grows), go out and train (bond or
## warmth, focus, a little qi for you) or go out and gather (finds come back to the haul bin). Work is real time, up to 8 hours away.

var data := {}
var haul := {}              # item -> n waiting
var last_t := 0.0
var _acc := 0.0
var prog := {}              # key -> minutes toward the next find
var day := ""
var day_finds := 0
var worked := 0.0           # hours of crew work done, ever
var rng := RandomNumberGenerator.new()


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/crew.json")
	rng.randomize()


func reset() -> void:
	haul = {}
	prog = {}
	day = ""
	day_finds = 0
	worked = 0.0
	last_t = G._now() if G != null else 0.0
	_acc = 0.0


func save_state() -> Dictionary:
	return {"haul": haul, "prog": prog, "day": day, "day_finds": day_finds, "worked": worked, "last_t": last_t}


func load_state(d: Dictionary) -> void:
	reset()
	var h = d.get("haul", {})
	if h is Dictionary:
		for k in h:
			if G.items.has(str(k)) and int(h[k]) > 0:
				haul[str(k)] = int(h[k])
	var p = d.get("prog", {})
	if p is Dictionary:
		for k in p:
			prog[str(k)] = float(p[k])
	day = str(d.get("day", ""))
	day_finds = int(d.get("day_finds", 0))
	worked = float(d.get("worked", 0.0))
	last_t = float(d.get("last_t", G._now()))
	if last_t <= 0.0 or last_t > G._now():
		last_t = G._now()
	_catch_up()


# ---- the catalogue ---------------------------------------------------------------------------------------------------

func jobs() -> Dictionary:
	return data.get("jobs", {})


func job_ids() -> Array:
	return ["rest", "tend", "train", "gather"]


func job_name(j: String) -> String:
	return I18n.t(str(jobs().get(j, {}).get("name", j)))


func specs() -> Dictionary:
	return data.get("specialties", {})


func _r(k: String, d: float) -> float:
	return float(data.get("rates", {}).get(k, d))


# ---- hands: who can work ----------------------------------------------------------------------------------------------

func hands() -> Array:
	## [{key, kind, name, rec}] -- everyone resting at home (not out at your side, not away)
	var out := []
	for c in G.contracts:
		if bool(c.get("out", false)) or bool(c.get("away", false)):
			continue
		var nm := str(c.get("name", c.get("species", "")))
		out.append({"key": "b:" + nm, "kind": "construct" if bool(c.get("construct", false)) else "beast", "name": nm, "rec": c})
	for nm in G.roster():
		if G.in_party(str(nm)) >= 0:
			continue
		out.append({"key": "c:" + str(nm), "kind": "companion", "name": str(nm), "rec": G.bond(str(nm))})
	for h in out:
		ensure(h)
	return out


func ensure(h: Dictionary) -> void:
	var rec: Dictionary = h["rec"]
	if not specs().has(str(rec.get("spec", ""))):
		var ids: Array = specs().keys()
		ids.sort()
		var sp := str(h["rec"].get("species", ""))
		rec["spec"] = str(ids[absi((str(h["name"]) + "|" + sp).hash()) % ids.size()])
	if not rec.has("job") or not jobs().has(str(rec["job"])):
		rec["job"] = "rest"
	if not rec.has("fxp"):
		rec["fxp"] = 0.0
	if not rec.has("focus"):
		rec["focus"] = str(specs()[rec["spec"]].get("likes", "gather"))


func spec_of(rec: Dictionary) -> Dictionary:
	return specs().get(str(rec.get("spec", "")), {})


func spec_name(rec: Dictionary) -> String:
	return I18n.t(str(spec_of(rec).get("name", "")))


func job_of(h: Dictionary) -> String:
	return str(h["rec"].get("job", "rest"))


# ---- focus ---------------------------------------------------------------------------------------------------------------

func focus_level(rec: Dictionary) -> int:
	var lv := 0
	for t in data.get("focus", {}).get("levels", []):
		if float(rec.get("fxp", 0.0)) >= float(t):
			lv += 1
	return lv


func focus_bonus(rec: Dictionary, sk: String) -> float:
	## aptitude points the focus has earned in this skill (read by Genome and Foundry)
	if str(rec.get("focus", "")) != sk or not rec.has("fxp"):
		return 0.0
	return float(focus_level(rec)) * float(data.get("focus", {}).get("per_level", 4.0))


func focus_next(rec: Dictionary) -> float:
	var lv := focus_level(rec)
	var lst: Array = data.get("focus", {}).get("levels", [])
	return float(lst[lv]) if lv < lst.size() else -1.0


func set_focus_block(h: Dictionary, sk: String) -> String:
	if str(h["rec"].get("focus", "")) == sk:
		return I18n.t("Already its focus.")
	var cost := int(data.get("focus", {}).get("change_gold", 60))
	if float(h["rec"].get("fxp", 0.0)) > 0.0 and G.gold < cost:
		return I18n.t("Re-training its focus costs %d gold.") % cost
	return ""


func set_focus(h: Dictionary, sk: String) -> String:
	var why := set_focus_block(h, sk)
	if why != "":
		return why
	var rec: Dictionary = h["rec"]
	var fd: Dictionary = data.get("focus", {})
	if float(rec.get("fxp", 0.0)) > 0.0:
		G.gold -= int(fd.get("change_gold", 60))
		rec["fxp"] = float(rec["fxp"]) * float(fd.get("keep_share", 0.25))
	rec["focus"] = sk
	G.stats_changed.emit()
	return I18n.t("CREW: %s now trains toward %s.") % [h["name"], _skill_name(sk)]


func _skill_name(sk: String) -> String:
	var GN = G.sys("genome")
	return GN.skill_name(sk) if GN != null else sk


# ---- aptitude and rates ------------------------------------------------------------------------------------------------

func aptitude(h: Dictionary) -> Dictionary:
	var GN = G.sys("genome")
	var out := {}
	if h["kind"] == "beast":
		out = GN.aptitude(h["rec"])
	elif h["kind"] == "construct":
		var FD = G.sys("foundry")
		out = FD.aptitude("golem:" + str(h["name"])) if FD != null else {}
	else:
		var w := float(h["rec"].get("warmth", 0.0))
		for sk in GN.skills():
			out[sk] = clampf(18.0 + w * 0.5 + G.realm * 3.0, 0.0, 100.0)
		var lk := str(spec_of(h["rec"]).get("likes", ""))
		if out.has(lk):
			out[lk] = minf(100.0, float(out[lk]) + 15.0)
	for sk in out:
		out[sk] = clampf(float(out[sk]) + (focus_bonus(h["rec"], str(sk)) if h["kind"] == "companion" else 0.0), 0.0, 100.0)
	return out


func rate(h: Dictionary, job: String) -> float:
	## work speed: 0.5 .. ~3 -- its aptitude for the job times its specialty's knack
	if job == "rest" or not jobs().has(job):
		return 0.0
	var ap := aptitude(h)
	var sks: Array = jobs()[job].get("skills", [])
	var tot := 0.0
	for sk in sks:
		tot += float(ap.get(str(sk), 0.0))
	var avg: float = tot / maxf(1.0, float(sks.size()))
	return (_r("floor", 0.5) + _r("per_apt", 0.02) * avg) * float(spec_of(h["rec"]).get("mods", {}).get(job, 1.0))


func rate_text(h: Dictionary, job: String) -> String:
	return "x%.2f" % rate(h, job)


# ---- jobs -----------------------------------------------------------------------------------------------------------------

func job_block(h: Dictionary, job: String) -> String:
	if not jobs().has(job):
		return I18n.t("No such job.")
	if job == "tend":
		var IW = G.sys("inner_world")
		var GA = G.sys("garden")
		if not ((IW != null and IW.open()) or (GA != null and GA.plots.size() > 0)):
			return I18n.t("You have no garden to tend yet.")
	return ""


func set_job(h: Dictionary, job: String) -> String:
	var why := job_block(h, job)
	if why != "":
		return why
	h["rec"]["job"] = job
	G.stats_changed.emit()
	return I18n.t("CREW: %s will %s.") % [h["name"], job_name(job).to_lower()]


func working() -> int:
	var n := 0
	for h in hands():
		if job_of(h) != "rest":
			n += 1
	return n


func stock_total() -> int:
	var n := 0
	for k in haul:
		n += int(haul[k])
	return n


func stock_cap() -> int:
	return int(_r("haul_cap", 24)) + 4 * working()


func _roll_day() -> void:
	var t := Time.get_date_string_from_system()
	if t != day:
		day = t
		day_finds = 0


# ---- the work ------------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_acc += delta
	if _acc < 30.0:
		return
	_acc = 0.0
	var now: float = G._now()
	if last_t <= 0.0:
		last_t = now
		return
	var mins := minf((now - last_t) / 60.0, _r("offline_cap_minutes", 480.0))
	last_t = now
	process(mins)


func _catch_up() -> void:
	var now: float = G._now()
	var mins := clampf((now - last_t) / 60.0, 0.0, _r("offline_cap_minutes", 480.0))
	last_t = now
	if mins >= 1.0:
		process(mins)


func process(minutes: float) -> void:
	if minutes <= 0.0:
		return
	_roll_day()
	var hours := minutes / 60.0
	var tend_pool := 0.0
	var tend_flora := 0.0
	for h in hands():
		var job := job_of(h)
		if job == "rest":
			continue
		var eff := rate(h, job)
		worked += hours
		_focus_gain(h, job, hours, eff)
		if job == "tend":
			tend_pool += hours * _r("tend_minutes_per_hour", 20.0) * eff
			tend_flora += hours * _r("tend_flora", 0.6) * eff
		elif job == "train":
			if h["kind"] == "beast":
				G.grow_bond(_r("train_bond_per_hour", 1.5) * hours * eff, h["rec"])
			elif h["kind"] == "companion":
				_quiet_warmth(str(h["name"]), _r("train_warmth_per_hour", 0.12) * hours * eff)
			_quiet_qi(_r("train_qi_per_hour", 3.0) * hours * eff)
		elif job == "gather":
			_gather(h, minutes, eff)
	if tend_pool > 0.0:
		_tend(tend_pool, tend_flora)
	# (no stats_changed here: background work must not make the HUD rebuild itself every half minute -- round 180, the pack
	#  screen's 3D figure was being torn down and rebuilt under the renderer. The pages read fresh numbers when opened.)


func _quiet_warmth(name: String, delta: float) -> void:
	## warmth without Game.warm_bond: that one pokes the HUD (stats_changed) and background work must not
	var bd: Dictionary = G.bond(name)
	bd["warmth"] = clampf(float(bd.get("warmth", 0.0)) + delta * G.tech_effect("bond_mult", 1.0), -50.0, 100.0)


func _quiet_qi(amount: float) -> void:
	## qi without Game.add_qi (it emits stats_changed and messages): kept just under the next step so real play does the level-up
	if amount <= 0.0:
		return
	var top: float = G.qi_to_next()
	G.qi = minf(G.qi + amount * G.tech_effect("qi_mult", 1.0) * G.growth_mult(), top - 0.01)


func _focus_gain(h: Dictionary, job: String, hours: float, eff: float) -> void:
	var rec: Dictionary = h["rec"]
	var before := focus_level(rec)
	var g: float = hours * _r("focus_per_hour", 6.0) * eff
	if str(rec.get("focus", "")) in jobs()[job].get("skills", []):
		g *= float(data.get("focus", {}).get("like_bonus", 1.25))
	rec["fxp"] = float(rec.get("fxp", 0.0)) + g
	if focus_level(rec) > before:
		G.message.emit(I18n.t("CREW: %s's %s focus deepens (level %d).") % [h["name"], _skill_name(str(rec.get("focus", ""))), focus_level(rec)])


func _tend(pool_minutes: float, flora: float) -> void:
	var secs := pool_minutes * 60.0
	var IW = G.sys("inner_world")
	if IW != null and IW.open():
		for i in IW.plots.size():
			var p: Dictionary = IW.plots[i]
			if p.is_empty() or secs <= 0.0:
				continue
			var left := maxf(0.0, float(p["ready"]) - IW._now())
			var cut := minf(left, secs)
			p["ready"] = float(p["ready"]) - cut
			secs -= cut
		IW._feed("flora", flora)
		IW._add_xp(0.4 * pool_minutes / 60.0)
	var GA = G.sys("garden")
	if GA != null and secs > 0.0:
		for i in GA.plots.size():
			var p2: Dictionary = GA.plots[i]
			if p2.is_empty() or secs <= 0.0:
				continue
			var left2 := maxf(0.0, float(p2["ready"]) - GA._now())
			var cut2 := minf(left2, secs)
			p2["ready"] = float(p2["ready"]) - cut2
			secs -= cut2


func _pool() -> Array:
	var g: Dictionary = data.get("gather", {})
	var out: Array = g.get("low", []).duplicate()
	if G.realm >= int(g.get("mid_realm", 3)):
		out.append_array(g.get("mid", []))
	if G.realm >= int(g.get("high_realm", 6)):
		out.append_array(g.get("high", []))
	return out.filter(func(x): return G.items.has(str(x)))


func _gather(h: Dictionary, minutes: float, eff: float) -> void:
	var key: String = h["key"]
	prog[key] = float(prog.get(key, 0.0)) + minutes * eff
	var every := _r("gather_minutes", 50.0)
	var guard := 0
	while float(prog[key]) >= every and guard < 40:
		guard += 1
		prog[key] = float(prog[key]) - every
		if stock_total() >= stock_cap() or day_finds >= int(_r("day_cap", 40)):
			prog[key] = minf(float(prog[key]), every * 0.5)
			break
		var it := _find(h)
		if it == "":
			break
		haul[it] = int(haul.get(it, 0)) + 1
		day_finds += 1


func _find(h: Dictionary) -> String:
	var g: Dictionary = data.get("gather", {})
	var fortune := float(aptitude(h).get("fortune", 0.0))
	if rng.randf() < float(g.get("rare_base", 0.04)) + float(g.get("rare_per_fortune", 0.0012)) * fortune:
		var rare: Array = g.get("rare", []).filter(func(x): return G.items.has(str(x)))
		if not rare.is_empty():
			return str(rare[rng.randi() % rare.size()])
	if h["kind"] == "beast" and rng.randf() < 0.5:
		var IW = G.sys("inner_world")
		if IW != null:
			var fl: Array = IW.finds_of(h["rec"])
			if not fl.is_empty():
				return str(fl[rng.randi() % fl.size()])
	var pool := _pool()
	return str(pool[rng.randi() % pool.size()]) if not pool.is_empty() else ""


func collect() -> String:
	if haul.is_empty():
		return I18n.t("Nothing is waiting in the haul bin.")
	var bits := []
	for k in haul.keys():
		G.add_item(str(k), int(haul[k]), false)
		bits.append("%s x%d" % [G.item_name(str(k)), int(haul[k])])
	haul = {}
	G.log_event("crew_collect", {})
	G.stats_changed.emit()
	return I18n.t("CREW: they bring back %s.") % ", ".join(bits)


# ---- the gifts and the small print ---------------------------------------------------------------------------------------

func effects() -> Array:
	var out := []
	var M = G.sys("menagerie")
	for b in G.beasts_out():
		var eff: Dictionary = spec_of(b).get("effect", {})
		if eff.is_empty() or M == null:
			continue
		var one := {}
		M._scale(eff, M.beast_grow(b), one)
		out.append(one)
	return out


func lines(c: Dictionary) -> Array:
	## for the party page: its knack and its focus
	if not specs().has(str(c.get("spec", ""))):
		var h := {"kind": "construct" if bool(c.get("construct", false)) else "beast", "name": str(c.get("name", c.get("species", ""))), "rec": c}
		ensure(h)
	var out := []
	var sp := spec_of(c)
	out.append(I18n.t("Knack: %s -- %s") % [spec_name(c), I18n.t(str(sp.get("desc", "")))])
	out.append(I18n.t("Focus: %s (level %d)  ·  Job: %s") % [_skill_name(str(c.get("focus", ""))), focus_level(c), job_name(str(c.get("job", "rest")))])
	return out


func status_lines() -> Array:
	return [I18n.t("%d at work  ·  %.1f hours of work done  ·  haul bin %d of %d") % [working(), worked, stock_total(), stock_cap()]]
