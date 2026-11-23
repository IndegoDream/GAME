extends "res://scripts/systems/GameSystem.gd"
## Round 188: found your own sect. Robert, 2026-11-08: "...or be able to start our own sect and own guild" -- he chose
## the full founding.
##
## WHERE: the Empty Seat, an old walled compound in the valley south of the river, by the north road (Valley.gd, the
## seventh seat). Until you found a sect there, a board at its gate tells you what it takes.
## WHAT IT TAKES: Core Formation and 3,000 gold, and no other sect (leave yours first).
## FOUNDING: a name, an element, a colour for the banners, a creed, and up to three of YOUR arts to teach. Two disciples
## answer the call. The hall is yours: sitting in it is the same x2.5 any sect gives its own (Game.SECT_HALL_AID).
## DISCIPLES: new hopefuls come to the gate every day (three, with an aptitude of one to five stars). Each one grows by
## the hour (aptitude x hours), faster when you teach them one of the sect's arts (once a day each), encourage them,
## or sit in the hall with them; they break through realms up to one below yours. Send one on an errand and they come
## back with a few of a material you've found (a daily cap by realm). They train in the yard and talk in the sect chat.
## THE HALL: three levels (gold and materials of the sect's element): more disciples (4 / 8 / 12) and a fuller yard.
## Fair play: at hall level 3 the sect has matured and gives what the top rank of any sect gives (meditation x1.15) --
## not before, not more.

var data := {}
var sect := {}                     # {} = not founded; {"name", "element", "color", "creed", "arts", "hall", "since"}
var disciples: Array = []          # [{"name", "apt", "el", "trait", "realm", "prog", "mood", "taught", "cheered", "errand"}]
var hired_day := {}                # candidate name -> day taken (so today's list doesn't offer them again)
var errand_value_today := 0
var day := ""
var last_t := 0.0
var time_shift := 0.0              # (tests) move the clock
var rng := RandomNumberGenerator.new()
var _chat_t := 90.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/fellowship.json").get("sect", {})
	rng.randomize()


func reset() -> void:
	sect = {}
	disciples = []
	hired_day = {}
	errand_value_today = 0
	day = ""
	last_t = now() if G != null else 0.0
	_chat_t = 90.0


func save_state() -> Dictionary:
	return {"sect": sect, "disciples": disciples, "hired_day": hired_day, "errand_value_today": errand_value_today, "day": day, "last_t": now()}


func load_state(d: Dictionary) -> void:
	reset()
	sect = d.get("sect", {}) if d.get("sect", {}) is Dictionary else {}
	disciples = d.get("disciples", []) if d.get("disciples", []) is Array else []
	hired_day = d.get("hired_day", {}) if d.get("hired_day", {}) is Dictionary else {}
	errand_value_today = int(d.get("errand_value_today", 0))
	day = str(d.get("day", ""))
	last_t = float(d.get("last_t", now()))
	if last_t <= 0.0 or last_t > now():
		last_t = now()
	catch_up()


func now() -> float:
	return G._now() + time_shift


func cfg(k: String, dflt = 0):
	return data.get(k, dflt)


func founded() -> bool:
	return not sect.is_empty()


func effects() -> Array:
	return []                       # (the matured sect's x1.15 goes through Game.sect_effect, like every sect's)


func mature_effect() -> Dictionary:
	if founded() and int(sect.get("hall", 1)) >= int(cfg("mature_hall", 3)):
		return {"meditate_mult": float(cfg("mature_meditate_mult", 1.15))}
	return {}


func def() -> Dictionary:
	## what Game.sect_def("own") answers: the shape every sect has
	if not founded():
		return {}
	var arts := []
	for a in sect.get("arts", []):
		arts.append({"id": str(a), "rank": 1, "name": art_name(str(a))})
	return {"id": "own", "name": str(sect["name"]), "element": str(sect["element"]), "creed": str(sect.get("creed", "")), "arts": arts,
		"elder": {"name": G.char_name}, "own": true}


func art_name(aid: String) -> String:
	return I18n.t(str(G.technique_defs.get(aid, {}).get("name", aid.replace("_", " ").capitalize())))


func teachable_arts() -> Array:
	## your own arts that can be taught: the ones you know, with a name
	var out := []
	for aid in G.techniques:
		if G.technique_defs.has(str(aid)) and str(G.technique_defs[str(aid)].get("kind", "active")) != "passive_hidden":
			out.append(str(aid))
	out.sort()
	return out


# ---- founding ----------------------------------------------------------------------------------------------------

func found_check() -> String:
	if founded():
		return I18n.t("You already lead the %s.") % str(sect.get("name", ""))
	if G.realm < int(cfg("found_realm", 3)):
		return I18n.t("Founding a sect takes %s. (You are %s.)") % [G.realm_info(int(cfg("found_realm", 3)))["name"], G.realm_name()]
	if G.in_sect():
		return I18n.t("You belong to the %s. Leave it before you found your own.") % str(G.sect_def(str(G.sect.get("id", ""))).get("name", ""))
	if G.gold < int(cfg("found_gold", 3000)):
		return I18n.t("Founding a sect costs %d gold (the seat, the hall's repair, the first rice). You have %d.") % [int(cfg("found_gold", 3000)), G.gold]
	return ""


func found(nm: String, element: String, color_i: int, creed: String, arts: Array) -> String:
	var why := found_check()
	if why != "":
		return why
	var n := nm.strip_edges()
	if n.length() < 3 or n.length() > 32:
		return I18n.t("A sect's name needs 3 to 32 letters.")
	for s in G.valley_data().get("sects", []):
		if str(s.get("name", "")).to_lower() == n.to_lower():
			return I18n.t("That name is already a sect's in the valley.")
	var els: Array = cfg("elements", ["earth"])
	if not element in els:
		element = str(els[0])
	var teach := []
	for a in arts:
		if str(a) in G.techniques and teach.size() < 3:
			teach.append(str(a))
	G.remove_item("gold", int(cfg("found_gold", 3000)))
	var cols: Array = cfg("colors", [[1, 0.8, 0.4]])
	sect = {"name": n, "element": element, "color": cols[clampi(color_i, 0, cols.size() - 1)], "creed": creed.strip_edges().left(120),
		"arts": teach, "hall": 1, "since": G.today(), "decor": []}
	disciples = []
	for i in int(cfg("start_disciples", 2)):
		var c := _candidate(rng, {})
		c["apt"] = maxi(2, int(c["apt"]))
		disciples.append(_disciple(c))
	G.sect = {"id": "own", "rank": G.sect_ranks().size() - 1, "contrib": 0.0}
	last_t = now()
	var FS = G.sys("fellowship")
	if FS != null:
		FS.owned["title_master"] = true
		FS.add_line("sect", "", _fmt(_pick(cfg("lines", {}).get("founded", [""])), {"m": str(disciples[0]["name"]), "m2": str(disciples[1]["name"]) if disciples.size() > 1 else ""}), "sys")
	G.log_event("own_sect_found", {"name": n, "element": element})
	G.bump("sects_founded")
	G.stats_changed.emit()
	return I18n.t("SECT: the %s is founded at the Empty Seat in the valley. You are its master.") % n


func disband() -> String:
	if not founded():
		return ""
	var nm := str(sect["name"])
	sect = {}
	disciples = []
	if str(G.sect.get("id", "")) == "own":
		G.sect = {}
		G.flags["sect_left_day"] = G.today()
	G.log_event("own_sect_disband", {"name": nm})
	G.stats_changed.emit()
	return I18n.t("The %s is no more. The disciples bow and go their ways; the seat stands empty again.") % nm


# ---- disciples ---------------------------------------------------------------------------------------------------

func slots() -> int:
	var s: Array = cfg("slots_by_hall", [4, 8, 12])
	return int(s[clampi(int(sect.get("hall", 1)) - 1, 0, s.size() - 1)])


func _candidate(r: RandomNumberGenerator, used: Dictionary, avoid_disciples: bool = true) -> Dictionary:
	var names: Array = load_json("res://data/fellowship.json").get("names", ["Ash"])
	var nm := ""
	for i in 30:
		var c := str(names[r.randi() % names.size()])
		if not used.has(c) and not (avoid_disciples and _has_disciple(c)):
			nm = c
			break
	if nm == "":
		nm = "Hopeful %d" % r.randi_range(2, 99)
	var roll := r.randf()
	var apt := 5 if roll < 0.05 else (4 if roll < 0.2 else (3 if roll < 0.5 else (2 if roll < 0.8 else 1)))
	var els: Array = cfg("elements", ["earth"])
	var traits: Array = cfg("traits", ["diligent"])
	return {"name": nm, "apt": apt, "el": str(els[r.randi() % els.size()]), "trait": str(traits[r.randi() % traits.size()])}


func _disciple(c: Dictionary) -> Dictionary:
	return {"name": str(c["name"]), "apt": int(c["apt"]), "el": str(c["el"]), "trait": str(c["trait"]), "realm": 0, "prog": 0.0, "mood": 0.6,
		"taught": "", "cheered": "", "errand": {}, "since": G.today()}


func _has_disciple(nm: String) -> bool:
	for d in disciples:
		if str(d["name"]) == nm:
			return true
	return false


func candidates() -> Array:
	## today's hopefuls at the gate (seeded by the day: they don't reroll when you look again)
	if not founded():
		return []
	var r := RandomNumberGenerator.new()
	r.seed = hash("hopefuls|" + G.today() + "|" + str(sect.get("name", "")))
	var used := {}
	# (round 191 fix) disciples who were already here before today are never drawn again -- else on some days a
	# hopeful shared a name with one of them and was dropped, leaving two at the gate (or one). Those taken in
	# TODAY stay in the draw, so the day's three stay the same whoever you take in.
	for d in disciples:
		if str(hired_day.get(str(d["name"]), "")) != G.today():
			used[str(d["name"])] = true
	var out := []
	for i in int(cfg("candidates_per_day", 3)):
		var c := _candidate(r, used, false)          # (the same three all day, whoever you take in)
		used[str(c["name"])] = true
		if str(hired_day.get(str(c["name"]), "")) == G.today() or _has_disciple(str(c["name"])):
			continue
		out.append(c)
	return out


func recruit(nm: String) -> String:
	if not founded():
		return ""
	if disciples.size() >= slots():
		return I18n.t("The hall sleeps %d. Raise the hall to take more.") % slots()
	for c in candidates():
		if str(c["name"]) == nm:
			disciples.append(_disciple(c))
			hired_day[nm] = G.today()
			_line(_fmt(_pick(cfg("lines", {}).get("joined", [])), {"m": nm}))
			G.log_event("own_sect_recruit", {"name": nm, "apt": int(c["apt"])})
			G.stats_changed.emit()
			return I18n.t("%s joins the %s.") % [nm, sect["name"]]
	return I18n.t("They've gone home.")


func dismiss(nm: String) -> String:
	for d in disciples:
		if str(d["name"]) == nm:
			disciples.erase(d)
			G.stats_changed.emit()
			return I18n.t("%s bows and leaves the sect.") % nm
	return ""


func disciple(nm: String) -> Dictionary:
	for d in disciples:
		if str(d["name"]) == nm:
			return d
	return {}


func realm_cap() -> int:
	return maxi(0, G.realm - 1)


func _grow(d: Dictionary, amount: float) -> void:
	if int(d["realm"]) >= realm_cap():
		d["prog"] = minf(float(d["prog"]) + amount, 1.0)
		return
	d["prog"] = float(d["prog"]) + amount
	while float(d["prog"]) >= 1.0 and int(d["realm"]) < realm_cap():
		d["prog"] = float(d["prog"]) - 1.0
		d["realm"] = int(d["realm"]) + 1
		_line(_fmt(_pick(cfg("lines", {}).get("breakthrough", [])), {"m": str(d["name"]), "realm": G.realm_info(int(d["realm"]))["name"]}))
		G.log_event("own_sect_breakthrough", {"name": str(d["name"]), "realm": int(d["realm"])})
	if int(d["realm"]) >= realm_cap():
		d["prog"] = minf(float(d["prog"]), 1.0)


func teach(nm: String, aid: String = "") -> String:
	var d := disciple(nm)
	if d.is_empty():
		return ""
	if str(d.get("taught", "")) == G.today():
		return I18n.t("%s has had a lesson today. Let it settle.") % nm
	var arts: Array = sect.get("arts", [])
	if aid == "":
		aid = str(arts[rng.randi() % arts.size()]) if arts.size() > 0 else ""
	d["taught"] = G.today()
	_grow(d, float(cfg("teach_boost", 0.12)) * (0.6 + 0.2 * float(d["apt"])))
	d["mood"] = minf(1.0, float(d.get("mood", 0.6)) + 0.1)
	_line(_fmt(_pick(cfg("lines", {}).get("taught", [])), {"m": nm, "art": art_name(aid) if aid != "" else I18n.t("the first form")}))
	G.stats_changed.emit()
	return I18n.t("You teach %s.") % nm


func encourage(nm: String) -> String:
	var d := disciple(nm)
	if d.is_empty():
		return ""
	if str(d.get("cheered", "")) == G.today():
		return I18n.t("%s is still glowing from the last word.") % nm
	d["cheered"] = G.today()
	d["mood"] = minf(1.0, float(d.get("mood", 0.6)) + 0.2)
	_grow(d, 0.03)
	_line(_fmt(_pick(cfg("lines", {}).get("encouraged", [])), {"m": nm}))
	G.stats_changed.emit()
	return I18n.t("%s stands a little taller.") % nm


func errand_cap() -> int:
	return int(cfg("errand_value_day_base", 60)) + int(cfg("errand_value_day_per_realm", 30)) * G.realm


func send_errand(nm: String) -> String:
	var d := disciple(nm)
	if d.is_empty():
		return ""
	if not (d.get("errand", {}) as Dictionary).is_empty():
		return I18n.t("%s is already out.") % nm
	_new_day()
	if errand_value_today >= errand_cap():
		return I18n.t("The sect has run enough errands today.")
	var FS = G.sys("fellowship")
	var pool: Array = FS.allowed_items() if FS != null else []
	var el := str(sect.get("element", ""))
	var mine := pool.filter(func(i): return str(G.items[i].get("element", "")) == el)
	if mine.size() > 0 and rng.randf() < 0.6:
		pool = mine
	if pool.is_empty():
		return I18n.t("There's nothing you've found yet that they could fetch.")
	var id: String = pool[rng.randi() % pool.size()]
	var v := maxi(1, int(G.items[id].get("value", 1)))
	var n := clampi(int((errand_cap() - errand_value_today) / v), 0, 2 + int(d["apt"]))
	if n <= 0:
		return I18n.t("The sect has run enough errands today.")
	errand_value_today += n * v
	var mins: Array = cfg("errand_minutes", [30, 90])
	d["errand"] = {"item": id, "n": n, "due": now() + rng.randf_range(float(mins[0]), float(mins[1])) * 60.0}
	G.stats_changed.emit()
	return I18n.t("%s sets out for %s.") % [nm, G.item_name(id)]


func _new_day() -> void:
	if day != G.today():
		day = G.today()
		errand_value_today = 0


# ---- the hall ----------------------------------------------------------------------------------------------------

func upgrade_cost() -> Dictionary:
	var h := int(sect.get("hall", 1))
	var ups: Array = cfg("hall_upgrade", [])
	if h >= ups.size():
		return {}
	return ups[h]


func element_material_value() -> int:
	var el := str(sect.get("element", ""))
	var v := 0
	for id in G.inventory:
		var d: Dictionary = G.items.get(G.base_id(str(id)), {})
		if str(d.get("type", "")) == "material" and str(d.get("element", "")) == el:
			v += int(d.get("value", 0)) * G.count(str(id))
	return v


func upgrade_check() -> String:
	if not founded():
		return I18n.t("Found a sect first.")
	var c := upgrade_cost()
	if c.is_empty():
		return I18n.t("The hall stands as tall as it can.")
	if G.gold < int(c.get("gold", 0)):
		return I18n.t("Raising the hall takes %d gold.") % int(c.get("gold", 0))
	if element_material_value() < int(c.get("material_value", 0)):
		return I18n.t("...and %d worth of %s materials (you carry %d).") % [int(c.get("material_value", 0)), str(sect["element"]), element_material_value()]
	return ""


func upgrade() -> String:
	var why := upgrade_check()
	if why != "":
		return why
	var c := upgrade_cost()
	G.remove_item("gold", int(c.get("gold", 0)))
	var need := int(c.get("material_value", 0))
	var el := str(sect.get("element", ""))
	var ids := []
	for id in G.inventory:
		var d: Dictionary = G.items.get(G.base_id(str(id)), {})
		if str(d.get("type", "")) == "material" and str(d.get("element", "")) == el:
			ids.append(str(id))
	ids.sort_custom(func(a, b): return int(G.items[G.base_id(a)].get("value", 0)) < int(G.items[G.base_id(b)].get("value", 0)))
	for id in ids:                                    # the cheapest first, only as much as needed
		var per := int(G.items[G.base_id(id)].get("value", 1))
		while need > 0 and G.count(id) > 0:
			G.remove_item(id, 1)
			need -= per
	sect["hall"] = int(sect.get("hall", 1)) + 1
	_line(I18n.t("The hall of the %s rises to level %d.") % [sect["name"], int(sect["hall"])])
	G.log_event("own_sect_hall", {"hall": int(sect["hall"])})
	G.stats_changed.emit()
	return I18n.t("The hall rises to level %d: room for %d disciples.") % [int(sect["hall"]), slots()]


# ---- time --------------------------------------------------------------------------------------------------------

func catch_up() -> void:
	## the hours you were away: the disciples kept training (at most a day of it), errands came home
	if not founded():
		last_t = now()
		return
	var hrs := clampf((now() - last_t) / 3600.0, 0.0, 24.0)
	last_t = now()
	if hrs > 0.0:
		for d in disciples:
			if (d.get("errand", {}) as Dictionary).is_empty():
				_grow(d, float(cfg("growth_per_hour", 0.03)) * float(d["apt"]) * (0.7 + 0.5 * float(d.get("mood", 0.6))) * hrs)
	_errands_home()


func _errands_home() -> void:
	for d in disciples:
		var e: Dictionary = d.get("errand", {})
		if not e.is_empty() and float(e.get("due", 0.0)) <= now():
			d["errand"] = {}
			if G.items.has(str(e.get("item", ""))):
				G.add_item(str(e["item"]), int(e["n"]), false)
				_line(_fmt(_pick(cfg("lines", {}).get("errand_back", [])), {"m": str(d["name"]), "n": int(e["n"]), "item": G.item_name(str(e["item"]))}))


var _acc := 0.0


func tick(delta: float) -> void:
	if not founded():
		return
	_acc += delta
	if _acc >= 10.0:
		_acc = 0.0
		catch_up()
	_chat_t -= delta
	if _chat_t <= 0.0:
		_chat_t = rng.randf_range(110.0, 220.0)
		_chatter()


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	## sitting in your own hall: the disciples sit with you and it carries them too
	if founded() and G.in_sect("own") and is_equal_approx(G.sit_aid, G.SECT_HALL_AID) and G.current_level == "valley":
		for d in disciples:
			if (d.get("errand", {}) as Dictionary).is_empty():
				_grow(d, float(cfg("hall_sit_boost_per_min", 0.004)) * float(d["apt"]) * secs / 60.0)


func _chatter() -> void:
	if disciples.is_empty():
		return
	var d: Dictionary = disciples[rng.randi() % disciples.size()]
	if not (d.get("errand", {}) as Dictionary).is_empty():
		return
	var key := "ask" if rng.randf() < 0.35 else "train"
	var arts: Array = sect.get("arts", [])
	_line(_fmt(_pick(cfg("lines", {}).get(key, [])), {"m": str(d["name"]), "art": art_name(str(arts[rng.randi() % arts.size()])) if arts.size() > 0 else I18n.t("the first form")}))


func greet() -> void:
	if founded():
		_line(_fmt(_pick(cfg("lines", {}).get("greet", []))))


func _line(text: String) -> void:
	var FS = G.sys("fellowship")
	if FS != null and text.strip_edges() != "":
		FS.add_line("sect", "", text, "sect")


func _pick(arr) -> String:
	if not (arr is Array) or (arr as Array).is_empty():
		return ""
	return I18n.t(str(arr[rng.randi() % arr.size()]))


func _fmt(s: String, extra: Dictionary = {}) -> String:
	var d := {"p": G.char_name if str(G.char_name) != "" else I18n.t("Master"), "s": str(sect.get("name", "")), "realm": G.realm_name()}
	d.merge(extra, true)
	return s.format(d)


func site() -> Dictionary:
	## what the valley draws at the Empty Seat
	if not founded():
		return {"founded": false}
	var ds := []
	for d in disciples:
		if (d.get("errand", {}) as Dictionary).is_empty():
			ds.append({"name": str(d["name"]), "el": str(d["el"]), "realm": int(d["realm"])})
	var FS = G.sys("fellowship")
	var decor := []
	if FS != null:
		for k in ["hall_lanterns", "hall_statue", "hall_banners"]:
			if FS.owned.has(k):
				decor.append(k)
	return {"founded": true, "name": str(sect["name"]), "element": str(sect["element"]), "color": sect.get("color", [1, 0.8, 0.4]), "hall": int(sect.get("hall", 1)),
		"disciples": ds.slice(0, 6), "decor": decor}
