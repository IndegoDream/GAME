extends "res://scripts/systems/GameSystem.gd"
## Time and seasons (round 44). Robert, 2026-10-04: "bring more depth to the
## world ... time and seasons ... there needs to be a sense of continuity in
## the world, so give the visual game aspects more to work with."
##
## THE CALENDAR runs on the real date: a season is a few real days, a year is
## four seasons, so the world keeps turning while you're away and comes back
## the way you'd expect it to. THE HOUR is your own clock (Game.hour): night,
## dawn, day, dusk -- in the village under the sky, and in the deep as a
## dimming of the light and a hunger in the things that live there.
## WEATHER is rolled for each quarter of a day, for each place: rain, storm,
## fog, snow on the surface; qi mist, spore drift, ash fall, cold seep down
## below. FESTIVALS fall on one day of each season in Eliet.
## Everything here has an effect you can feel and a look you can see
## (WorldFX.gd); the World page shows it all. data/world.json.

var data := {}
var calm := false          # tools/tests: an ordinary, steady world (no effects, no foes' moods)
var day_override := -1     # tools/tests: pretend it's this world day
var seen_seasons := {}     # season id -> times you've lived through its start (for "since you were here")
var gifts := {}            # festival key -> true (one gift per festival)
var last_day := -1         # the world day you were last here
var _eff_cache := []
var _eff_key := ""


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/world.json")
	# Dev's words: names and descriptions, entry by entry
	for brief in ["world_seasons", "world_weather", "festivals"]:
		var dr = G._load_json("res://data/drafts/%s.json" % brief, {})
		if not (dr is Dictionary):
			continue
		for it in dr.get("items", []):
			if it is Dictionary:
				_reword(str(it.get("id", "")), it)


func _reword(wid: String, it: Dictionary) -> void:
	var txt := str(it.get("text", it.get("desc", ""))).strip_edges()
	if wid == "" or txt == "":
		return
	for s in data.get("seasons", []):
		if str(s.get("id", "")) == wid:
			s["desc"] = txt
			return
	for table in ["surface_weather", "deep_currents"]:
		if data.get(table, {}).has(wid):
			data[table][wid]["desc"] = txt
			return
	for sk in data.get("festivals", {}):
		if str(data["festivals"][sk].get("id", "")) == wid:
			data["festivals"][sk]["desc"] = txt
			return


func reset() -> void:
	seen_seasons = {}
	gifts = {}
	last_day = -1


func save_state() -> Dictionary:
	return {"seen": seen_seasons, "gifts": gifts, "last_day": last_day}


func load_state(d: Dictionary) -> void:
	seen_seasons = d.get("seen", {}) if d.get("seen", {}) is Dictionary else {}
	gifts = d.get("gifts", {}) if d.get("gifts", {}) is Dictionary else {}
	last_day = int(d.get("last_day", -1))


# ---- the calendar ------------------------------------------------------------------------

func _epoch_unix() -> float:
	var e := str(data.get("epoch", "2026-01-01")).split("-")
	if e.size() < 3:
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict({"year": int(e[0]), "month": int(e[1]), "day": int(e[2]), "hour": 0, "minute": 0, "second": 0}))


func day() -> int:
	## the world's day number (0 = the first day of the first Thaw)
	if day_override >= 0:
		return day_override
	var tz := Time.get_time_zone_from_system()
	var local := Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0
	return maxi(0, int(floor((local - _epoch_unix()) / 86400.0)))


func season_days() -> int:
	return maxi(1, int(data.get("season_days", 5)))


func season_index(d: int = -1) -> int:
	if d < 0:
		d = day()
	return int(d / season_days()) % 4


func season(d: int = -1) -> Dictionary:
	var ss: Array = data.get("seasons", [])
	return ss[season_index(d)] if ss.size() == 4 else {}


func season_id() -> String:
	return str(season().get("id", ""))


func day_of_season(d: int = -1) -> int:
	if d < 0:
		d = day()
	return d % season_days() + 1


func year(d: int = -1) -> int:
	if d < 0:
		d = day()
	return int(d / (season_days() * 4)) + 1


func date_text() -> String:
	return I18n.t("Day %d of %s, Year %d") % [day_of_season(), str(season().get("name", "")), year()]


func days_to_next_season() -> int:
	return season_days() - day_of_season() + 1


# ---- the hour -----------------------------------------------------------------------------

func phase() -> String:
	var h: float = G.hour()
	var P: Dictionary = data.get("phases", {})
	for pid in ["night", "dawn", "dusk", "day"]:
		var p: Dictionary = P.get(pid, {})
		var a := float(p.get("from", 0))
		var b := float(p.get("to", 0))
		if (a <= b and h >= a and h < b) or (a > b and (h >= a or h < b)):
			return pid
	return "day"


func phase_def() -> Dictionary:
	return data.get("phases", {}).get(phase(), {})


func deep_dim() -> float:
	return float(data.get("deep_dim", {}).get(phase(), 1.0))


# ---- weather ------------------------------------------------------------------------------

func region(level_id: String = "", level_def: Dictionary = {}) -> String:
	## "surface" under the sky; otherwise the kind of deep a floor is ("deep:forge")
	if level_id == "":
		level_id = str(G.current_level)
	var lv = _level()
	if level_def.is_empty() and lv and str(lv.level_id) == level_id:
		level_def = lv.def
	var theme := str(level_def.get("theme", "dungeon"))
	if level_id == "village" or theme in ["village", "wilds"]:
		return "surface"
	if theme == "settlement":
		return "town:" + level_id
	var key := ""
	if lv and str(lv.level_id) == level_id:
		key = str(lv.look_key)
	return "deep:" + (key if key != "" else level_id)


func _level():
	if not G.is_inside_tree():
		return null
	for lv in G.get_tree().get_nodes_in_group("level"):
		if is_instance_valid(lv) and not lv.is_queued_for_deletion():
			return lv
	return null


func quarter() -> int:
	return clampi(int(G.hour() / 6.0), 0, 3)


func weather_id(reg: String = "", d: int = -1, q: int = -1) -> String:
	## the weather in a place, this quarter of the day
	if reg == "":
		reg = region()
	if d < 0:
		d = day()
	if q < 0:
		q = quarter()
	if reg.begins_with("town:"):
		return "still"                         # a cavern town keeps its own air
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather|%s|%d|%d" % [reg, d, q])
	var pool := []
	var total := 0.0
	if reg == "surface":
		var sid := str(season(d).get("id", "thaw"))
		var W: Dictionary = data.get("surface_weather", {})
		var ks: Array = W.keys()
		ks.sort()
		for k in ks:
			var w := float(W[k].get("weight", {}).get(sid, 0))
			if w > 0.0:
				pool.append([k, w])
				total += w
	else:
		var biome := reg.trim_prefix("deep:")
		var C: Dictionary = data.get("deep_currents", {})
		var ks2: Array = C.keys()
		ks2.sort()
		for k in ks2:
			var tags: Array = C[k].get("tags", [])
			if not tags.is_empty() and not (biome in tags):
				continue
			var w2 := float(C[k].get("weight", 1))
			pool.append([k, w2])
			total += w2
	if pool.is_empty():
		return "clear" if reg == "surface" else "still"
	var r := rng.randf() * total
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return str(p[0])
	return str(pool[-1][0])


func weather(reg: String = "") -> Dictionary:
	if reg == "":
		reg = region()
	var wid := weather_id(reg)
	var t: Dictionary = data.get("surface_weather" if reg == "surface" else "deep_currents", {})
	var w: Dictionary = (t.get(wid, {}) as Dictionary).duplicate()
	w["id"] = wid
	return w


func forecast(reg: String = "surface") -> Array:
	## the rest of today and tomorrow morning: [[label, name], ...]
	var out := []
	var d := day()
	var q := quarter()
	var labels := ["Small hours", "Morning", "Afternoon", "Evening"]
	for i in 4:
		var qq := (q + i) % 4
		var dd := d + int((q + i) / 4)
		var wid := weather_id(reg, dd, qq)
		var t: Dictionary = data.get("surface_weather" if reg == "surface" else "deep_currents", {})
		out.append([(I18n.t("Tomorrow, ") if dd > d else "") + labels[qq].to_lower() if i > 0 else "Now", str(t.get(wid, {}).get("name", wid))])
	return out


# ---- festivals ----------------------------------------------------------------------------

func festival(d: int = -1) -> Dictionary:
	## today's festival in Eliet ({} = an ordinary day)
	if d < 0:
		d = day()
	var f: Dictionary = data.get("festivals", {}).get(str(season(d).get("id", "")), {})
	if f.is_empty() or day_of_season(d) != int(f.get("day", 0)):
		return {}
	return f


func festival_key() -> String:
	var f := festival()
	return "" if f.is_empty() else "%s:%d" % [str(f.get("id", "")), year()]


func festival_discount() -> float:
	if calm or str(G.current_level) != "village":
		return 0.0
	return float(festival().get("discount", 0.0))


func claim_gift() -> String:
	## the elder's festival gift: once a festival
	var f := festival()
	if f.is_empty():
		return ""
	var k := festival_key()
	if gifts.has(k):
		return ""
	gifts[k] = true
	var got := []
	for id in f.get("gift", {}):
		if G.has_item_def(str(id)):
			G.add_item(str(id), int(f["gift"][id]), false)
			got.append("%d %s" % [int(f["gift"][id]), G.item_name(str(id))])
	G.log_event("festival_gift", {"festival": f.get("id", "")})
	var fname := str(f.get("name", ""))
	if fname.to_lower().begins_with("the "):
		fname = fname.substr(4)           # ("For the Longest Night", not "For the The Longest Night")
	return I18n.t("For the %s: %s.") % [fname, ", ".join(got)] if got.size() > 0 else ""


func next_festival_in() -> int:
	for i in range(0, season_days() * 4 + 1):
		if not festival(day() + i).is_empty():
			return i
	return -1


# ---- what it does ------------------------------------------------------------------------

func _merge(into: Dictionary, e: Dictionary) -> void:
	for k in e:
		if e[k] is Dictionary:
			continue
		if k in G.ADDITIVE_KEYS or str(k).begins_with("craft_") or k in ["gather_bonus", "loot_luck"]:
			into[k] = float(into.get(k, 0.0)) + float(e[k])
		else:
			into[k] = float(into.get(k, 1.0)) * float(e[k])


func effects() -> Array:
	if calm:
		return []
	var reg := region()
	var key := "%d|%s|%s|%d|%s" % [day(), phase(), reg, quarter(), str(G.current_level)]
	if key == _eff_key:
		return _eff_cache
	_eff_key = key
	var e := {}
	_merge(e, season().get("effect", {}))
	_merge(e, phase_def().get("effect", {}))
	_merge(e, weather(reg).get("effect", {}))
	if str(G.current_level) == "village":
		_merge(e, festival().get("effect", {}))
	_eff_cache = [e] if not e.is_empty() else []
	return _eff_cache


func foe_mod(level_id: String, level_def: Dictionary, key: String) -> float:
	## for a monster on that floor: night's hunger, the season, the air down there
	if calm or level_id == "village" or str(level_def.get("theme", "")) in ["village", "settlement"]:
		return 1.0
	var v := float(season().get("foes", {}).get(key, 1.0))
	v *= float(phase_def().get("foes", {}).get(key, 1.0))
	var reg := region(level_id, level_def)
	v *= float(weather(reg).get("foes", {}).get(key, 1.0))
	return v


func tick(_delta: float) -> void:
	# a new season since you were last here: say so, once
	var d := day()
	if d == last_day:
		return
	var was := last_day
	last_day = d
	if was < 0 or calm:
		return
	if season_index(was) != season_index(d) or d - was >= season_days():
		var s := season()
		G.message.emit(I18n.t("THE SEASON HAS TURNED: it's %s now. %s") % [str(s.get("name", "")), str(s.get("desc", ""))])
		G.log_event("season_turned", {"season": s.get("id", ""), "away_days": d - was})
	if not festival().is_empty():
		G.message.emit(I18n.t("Today is the %s in Eliet. %s") % [str(festival().get("name", "")), str(festival().get("desc", ""))])


func summary() -> String:
	## one line for the HUD: "Day 3 of Thaw · Dusk · Rain"
	var w := weather()
	var f := festival()
	return "%s  ·  %s  ·  %s%s" % [date_text(), str(phase_def().get("name", "")), str(w.get("name", "")),
		("  ·  " + str(f.get("name", ""))) if not f.is_empty() and str(G.current_level) == "village" else ""]
