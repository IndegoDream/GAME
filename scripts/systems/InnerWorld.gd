extends "res://scripts/systems/GameSystem.gd"
## Round 147: the inner world. Robert, 2026-10-18: "Make an inner world that can be cultivated into a biosphere for inner training, housing
## animal companions, a garden that can grow depending on use and needs. A practice ground for techniques and meditate on enlightenment of the dao."
##   OPENS with the swarm (tier 2). It has a LEVEL (ten of them) that grows with sitting, tending, drilling and the beasts that live there.
##   BIOSPHERE: three living meters -- qi, flora, fauna -- each worth a small permanent gift. The realm has a NEED each day (one of the three):
##     feeding that need grows it twice as fast. So what you do (sit / pick herbs / keep beasts) shapes what the realm becomes.
##   GARDEN (level 1): 2..5 plots that grow in half the time, faster with flora; picks a day capped.
##   HABITAT (level 2): the beasts resting in your spirit space live here: bond grows faster, and each brings back a find now and then
##     (its species' own finds, or by role). Capacity grows with the level.
##   PRACTICE GROUND (level 3): while you sit, put your sitting into DRILLING a weapon or ki skill (capped a day).
##   DAO POOL (level 4): while you sit, put it into the dao you follow (Dao.gd keeps its own daily caps).
## Time passes while you are away (up to 8 hours for the habitat). Offline game only. data/inner_world.json.

var data := {}
var xp := 0.0
var meters := {"qi": 0.0, "flora": 0.0, "fauna": 0.0}
var plots := []                  # [{"herb": id, "ready": unix} or {}]
var stock := {}                  # item -> n waiting in the habitat
var prog := {}                   # beast name -> minutes toward its next find
var focus := "grow"              # what sitting feeds: grow / drill / pool
var drill_skill := ""
var day := ""
var day_xp := 0.0
var day_sit := 0.0
var day_drill := 0.0
var day_picks := 0
var day_finds := 0
var last_t := 0.0
var _acc := 0.0
var _lvl := 0
var now_override := -1.0         # tests
var day_override := ""           # tests


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/inner_world.json")
	reset()


func reset() -> void:
	xp = 0.0
	meters = {"qi": 0.0, "flora": 0.0, "fauna": 0.0}
	plots = []
	stock = {}
	prog = {}
	focus = "grow"
	drill_skill = ""
	day = ""
	day_xp = 0.0
	day_sit = 0.0
	day_drill = 0.0
	day_picks = 0
	day_finds = 0
	last_t = 0.0
	_acc = 0.0
	_lvl = 0
	for i in int((data.get("garden", {}) as Dictionary).get("max_plots", 5)):
		plots.append({})


func save_state() -> Dictionary:
	return {"xp": xp, "meters": meters, "plots": plots, "stock": stock, "prog": prog, "focus": focus, "drill": drill_skill, "day": day,
		"day_xp": day_xp, "day_sit": day_sit, "day_drill": day_drill, "day_picks": day_picks, "day_finds": day_finds, "last_t": last_t}


func load_state(d: Dictionary) -> void:
	reset()
	xp = maxf(0.0, float(d.get("xp", 0.0)))
	var m = d.get("meters", {})
	if m is Dictionary:
		for k in meters:
			meters[k] = clampf(float(m.get(k, 0.0)), 0.0, 100.0)
	var p = d.get("plots", [])
	if p is Array:
		for i in mini(p.size(), plots.size()):
			var e = p[i]
			if e is Dictionary and str(e.get("herb", "")) != "" and G.items.has(str(e["herb"])):
				plots[i] = {"herb": str(e["herb"]), "ready": float(e.get("ready", 0.0))}
	var s = d.get("stock", {})
	if s is Dictionary:
		for k in s:
			if G.items.has(str(k)) and int(s[k]) > 0:
				stock[str(k)] = int(s[k])
	var pr = d.get("prog", {})
	if pr is Dictionary:
		for k in pr:
			prog[str(k)] = float(pr[k])
	focus = str(d.get("focus", "grow")) if str(d.get("focus", "grow")) in ["grow", "drill", "pool"] else "grow"
	drill_skill = str(d.get("drill", ""))
	day = str(d.get("day", ""))
	day_xp = float(d.get("day_xp", 0.0))
	day_sit = float(d.get("day_sit", 0.0))
	day_drill = float(d.get("day_drill", 0.0))
	day_picks = int(d.get("day_picks", 0))
	day_finds = int(d.get("day_finds", 0))
	last_t = float(d.get("last_t", 0.0))
	_lvl = level()


# ---- the realm ------------------------------------------------------------------------------------------------------------------

func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


func _today() -> String:
	return day_override if day_override != "" else str(G.today())


func _roll_day() -> void:
	var t := _today()
	if day != t:
		day = t
		day_xp = 0.0
		day_sit = 0.0
		day_drill = 0.0
		day_picks = 0
		day_finds = 0


func open() -> bool:
	return G.nanite_tier() >= int(data.get("min_tier", 2)) and not G.OnlineGen.is_online(str(G.current_level))


func levels() -> Array:
	return data.get("levels", [])


func _W():
	return G.sys("workshop")


func has_seed() -> bool:
	var w = _W()
	return w != null and w.has("seed")


func has_heaven() -> bool:
	var w = _W()
	return w != null and w.has("heaven")


func level_cap() -> int:
	## the long road (Workshop.gd): every sect technique you win raises the ceiling
	var c: Dictionary = data.get("cap", {})
	var n := int(c.get("base", 3))
	var w = _W()
	if w != null:
		for id in c.get("unlock", {}):
			if w.has(str(id)):
				n += int(c["unlock"][id])
	return mini(n, levels().size())


func improvements() -> Array:
	## [[line id, text, won]] for the page: what each line of the long road does here
	var out := []
	var w = _W()
	for id in data.get("cap", {}).get("text", {}):
		out.append([str(id), str(data["cap"]["text"][id]), w != null and w.has(str(id))])
	return out


func _has(id: String) -> bool:
	var w = _W()
	return w != null and w.has(id)


func level() -> int:
	var n := 1
	for i in levels().size():
		if xp >= float(levels()[i]["at"]):
			n = i + 1
	return mini(n, level_cap())


func level_def() -> Dictionary:
	return levels()[level() - 1] if levels().size() >= level() else {}


func next_at() -> float:
	return float(levels()[level()]["at"]) if level() < level_cap() else -1.0


func room_open(room: String) -> bool:
	return level() >= int(data.get("rooms", {}).get(room, 99))


func need() -> String:
	var ns: Array = data.get("needs", ["qi"])
	return str(ns[absi(_today().hash()) % ns.size()])


func _add_xp(n: float, capped: bool = true) -> void:
	_roll_day()
	var take := n * (1.5 if has_seed() else 1.0)
	if capped:
		var cap := float(data.get("xp", {}).get("day_cap_other", 60))
		take = minf(n, maxf(0.0, cap - day_xp))
		day_xp += take
	if take <= 0.0:
		return
	xp += take
	var lv := level()
	if lv > _lvl:
		if _lvl > 0:
			G.message.emit(I18n.t("INNER WORLD -- %s. %s") % [I18n.t(str(level_def().get("name", ""))), I18n.t(str(level_def().get("text", "")))])
			for r in data.get("rooms", {}):
				if int(data["rooms"][r]) == lv:
					G.message.emit(I18n.t("INNER WORLD: a new room opens -- %s.") % room_name(str(r)))
			G.log_event("inner_world_level", {"level": lv})
			G.stats_changed.emit()
		_lvl = lv


func room_name(r: String) -> String:
	return {"garden": I18n.t("the garden"), "habitat": I18n.t("the habitat"), "ground": I18n.t("the practice ground"), "pool": I18n.t("the Dao pool")}.get(r, r)


func _feed(m: String, n: float) -> void:
	if need() == m:
		n *= float(data.get("meters", {}).get("need_mult", 2.0))
	meters[m] = minf(100.0, float(meters[m]) + n * (1.0 - float(meters[m]) / 130.0))


func meter_text(m: String) -> String:
	return {"qi": I18n.t("Qi"), "flora": I18n.t("Flora"), "fauna": I18n.t("Fauna")}.get(m, m)


func effects() -> Array:
	if not open():
		return []
	var g: Dictionary = data.get("gifts", {})
	var k := 1.5 if has_heaven() else 1.0
	return [{"qi_mult": 1.0 + float(g.get("qi_mult", 0.06)) * k * float(meters["qi"]) / 100.0,
		"gather_chance": float(g.get("gather_chance", 0.04)) * k * float(meters["flora"]) / 100.0,
		"bond_mult": 1.0 + float(g.get("bond_mult", 0.05)) * k * float(meters["fauna"]) / 100.0}]


# ---- sitting: tend / drill / pool ---------------------------------------------------------------------------------------------------

func set_focus(f: String, skill: String = "") -> String:
	if f == "drill":
		if not room_open("ground"):
			return I18n.t("The practice ground is not open yet.")
		if skill != "":
			drill_skill = skill
		if drill_skill == "":
			drill_skill = G.weapon_skill()
	elif f == "pool" and not room_open("pool"):
		return I18n.t("The Dao pool is not open yet.")
	focus = f
	G.stats_changed.emit()
	return I18n.t("When you sit, you now put your breath into: %s.") % focus_text()


func focus_text() -> String:
	match focus:
		"drill":
			return I18n.t("the practice ground (%s)") % I18n.t(str(G.skill_defs.get(drill_skill, {}).get("name", drill_skill)))
		"pool":
			return I18n.t("the Dao pool")
	return I18n.t("tending the realm")


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	if not open():
		return
	_roll_day()
	var mins := secs / 60.0
	var xc: Dictionary = data.get("xp", {})
	var sit_take := minf(mins * float(xc.get("sit_per_min", 1.0)), maxf(0.0, float(xc.get("sit_day_cap", 60)) - day_sit))
	if sit_take > 0.0:
		day_sit += sit_take
		_add_xp(sit_take, false)
	_feed("qi", mins * float(data.get("meters", {}).get("qi_per_min", 0.5)))
	var lv := float(level())
	match focus:
		"drill":
			if room_open("ground") and drill_skill != "":
				var g: Dictionary = data.get("ground", {})
				var take := minf(mins, maxf(0.0, float(g.get("day_cap", 45)) + (float(data.get("cap", {}).get("hands_drill_bonus", 25)) if _has("hands") else 0.0) - day_drill))
				if take > 0.0:
					day_drill += take
					G.add_skill_xp(drill_skill, take * float(g.get("xp_per_min", 4.0)) * (1.0 + float(g.get("level_gain", 0.1)) * (lv - 3.0)), "the practice ground")
					_add_xp(take * float(xc.get("drill_per_min", 0.6)))
		"pool":
			if room_open("pool"):
				var D = G.sys("dao")
				if D != null:
					var did: String = D.focus if D.focus != "" else (str(D.dao_ids()[0]) if D.dao_ids().size() > 0 else "")
					if did != "":
						var pl: Dictionary = data.get("pool", {})
						var got: float = D.gain(did, mins * float(pl.get("pts_per_min", 1.2)) * (1.0 + float(pl.get("level_gain", 0.1)) * (lv - 4.0)) * (float(data.get("cap", {}).get("breath_pool_mult", 1.25)) if _has("breath") else 1.0), true)
						if got > 0.0:
							_add_xp(mins * float(xc.get("pool_per_min", 0.8)))


# ---- the garden -----------------------------------------------------------------------------------------------------------------------

func plot_count() -> int:
	var g: Dictionary = data.get("garden", {})
	return mini(int(g.get("max_plots", 5)), int(g.get("base_plots", 2)) + int((level() - 1) / int(g.get("level_per_plot", 3))) + (1 if has_seed() else 0))


func herbs() -> Array:
	var GA = G.sys("garden")
	return GA.herbs() if GA != null else []


func grow_minutes(herb: String) -> float:
	var GA = G.sys("garden")
	var base := float(GA.herb_def(herb).get("minutes", 180)) if GA != null else 180.0
	var g: Dictionary = data.get("garden", {})
	return maxf(10.0, base * float(g.get("time_mult", 0.5)) * (1.0 - float(g.get("flora_speed", 0.4)) * float(meters["flora"]) / 100.0))


func state(i: int) -> String:
	if i < 0 or i >= plot_count():
		return "locked"
	var p: Dictionary = plots[i]
	if p.is_empty():
		return "empty"
	return "ready" if _now() >= float(p["ready"]) else "growing"


func minutes_left(i: int) -> int:
	return maxi(0, int(ceil((float(plots[i].get("ready", 0.0)) - _now()) / 60.0)))


func plant(i: int, herb: String) -> String:
	if not open():
		return I18n.t("The inner world is closed to you right now.")
	if state(i) != "empty":
		return ""
	if G.count(herb) < 1 or not G.remove_item(herb, 1):
		return I18n.t("You have none of that to plant.")
	plots[i] = {"herb": herb, "ready": _now() + grow_minutes(herb) * 60.0}
	G.stats_changed.emit()
	return I18n.t("You plant %s in the inner world. About %d minutes.") % [G.item_name(herb), int(grow_minutes(herb))]


func pick(i: int) -> String:
	if not open() or state(i) != "ready":
		return ""
	_roll_day()
	var g: Dictionary = data.get("garden", {})
	var each := int(g.get("yield", 2)) + (1 if level() >= int(g.get("bonus_yield_level", 6)) else 0) + (int(data.get("cap", {}).get("eye_yield", 1)) if _has("eye") else 0)
	if day_picks + each > int(g.get("day_cap", 10)):
		return I18n.t("You have picked enough for today. The rest keeps until tomorrow.")
	var herb := str(plots[i]["herb"])
	plots[i] = {}
	day_picks += each
	G.add_item(herb, each, false)
	_feed("flora", float(data.get("meters", {}).get("flora_per_pick", 2.5)))
	_add_xp(float(data.get("xp", {}).get("harvest", 3.0)))
	G.bump("inner_picks")
	G.log_event("inner_pick", {"herb": herb})
	G.stats_changed.emit()
	return I18n.t("INNER GARDEN: you pick %d x %s.") % [each, G.item_name(herb)]


# ---- the habitat ------------------------------------------------------------------------------------------------------------------------

func capacity() -> int:
	return int(data.get("habitat", {}).get("base_cap", 1)) + level() + (2 if has_seed() else 0) + (int(data.get("cap", {}).get("step_housed", 1)) if _has("step") else 0)


func housed() -> Array:
	## the beasts resting in your spirit space (not out at your side), up to what the realm holds
	if not room_open("habitat"):
		return []
	var out := []
	for c in G.contracts:
		if not bool(c.get("out", false)):
			out.append(c)
			if out.size() >= capacity():
				break
	return out


func finds_of(b: Dictionary) -> Array:
	var M = G.sys("menagerie")
	var sp := str(b.get("species", ""))
	var list := []
	if M != null:
		for ns in M.data.get("new_species", []):
			if str(ns.get("id", "")) == sp:
				list = ns.get("finds", [])
		if list.is_empty():
			list = data.get("forage", {}).get(M.role_id(sp), [])
	if list.is_empty():
		list = data.get("forage", {}).get("default", [])
	return list.filter(func(x): return G.items.has(str(x)))


func stock_total() -> int:
	var n := 0
	for k in stock:
		n += int(stock[k])
	return n


func _settle(minutes: float) -> void:
	## the beasts at rest: bond, a find now and then, the fauna meter, a little growth for the realm
	var h: Dictionary = data.get("habitat", {})
	var list := housed()
	if list.is_empty() or minutes <= 0.0:
		return
	_roll_day()
	var per := float(h.get("bond_per_min", 0.08)) + float(h.get("level_bond", 0.12)) * float(level()) / 10.0
	for b in list:
		G.grow_bond(per * minutes, b)
		var nm := str(b.get("name", b.get("species", "")))
		prog[nm] = float(prog.get(nm, 0.0)) + minutes
		var every := float(h.get("forage_minutes", 60))
		while float(prog[nm]) >= every:
			prog[nm] = float(prog[nm]) - every
			if stock_total() >= int(h.get("stock_cap", 8)) or day_finds >= int(h.get("day_cap", 12)):
				prog[nm] = minf(float(prog[nm]), every * 0.5)
				break
			var fl := finds_of(b)
			if fl.is_empty():
				break
			var it := str(fl[randi() % fl.size()])
			stock[it] = int(stock.get(it, 0)) + 1
			day_finds += 1
			_add_xp(float(data.get("xp", {}).get("forage", 1.0)))
		_feed("fauna", minutes / 60.0 * float(data.get("meters", {}).get("fauna_per_beast_hour", 0.35)))
		_add_xp(minutes / 60.0 * float(data.get("xp", {}).get("beast_hour", 0.4)))


func collect() -> String:
	if stock.is_empty():
		return I18n.t("Nothing is waiting in the habitat.")
	var bits := []
	for k in stock.keys():
		G.add_item(str(k), int(stock[k]), false)
		bits.append("%s x%d" % [G.item_name(str(k)), int(stock[k])])
	stock = {}
	G.log_event("inner_collect", {})
	G.stats_changed.emit()
	return I18n.t("HABITAT: your beasts bring back %s.") % ", ".join(bits)


func tick(delta: float) -> void:
	if not open():
		last_t = 0.0
		return
	_acc += delta
	if _acc < 20.0:
		return
	_acc = 0.0
	var now := _now()
	if last_t <= 0.0:
		last_t = now
		return
	var mins := minf((now - last_t) / 60.0, float(data.get("habitat", {}).get("away_cap_minutes", 480)))
	last_t = now
	_settle(mins)


# ---- the practice ground's skill list ---------------------------------------------------------------------------------------------------

func drill_skills() -> Array:
	return (data.get("ground", {}).get("skills", []) as Array).filter(func(s): return G.skill_defs.has(str(s)))
