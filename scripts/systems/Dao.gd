extends "res://scripts/systems/GameSystem.gd"
## Round 139: the Dao. Robert, 2026-10-17: "introduce dao more deeply as a core part of the game -- start with dao sense and
## allow players to develop on their own direction."
##
## DAO SENSE is the first thing: how much of the world's grain you can feel. It grows a little from everything you do and
## from sitting still, and a few times a day you can CONTEMPLATE where you stand. Its stage (Dull ... Dao-seeing) is the
## ceiling on how deep any one dao can go -- you can't understand what you can't yet see.
## EIGHT DAOS (data/dao.json): each grows from the things that are naturally its own (blade from fighting, forge from making,
## seeker from finding ...). Follow one (your FOCUS) and it grows faster and gives its full gift; the rest still give 60%.
## At the top of a dao you may FOUND YOUR OWN: name it, pick a tenet; it gives half again as much.
## Gifts are small (a mastered dao is about +12%); this is a direction, not a power curve. Nothing here is sold.

var data := {}
var sense := 0.0
var pts := {}                 # dao id -> points
var focus := ""
var focus_day := ""
var day := ""
var day_pts := {}             # dao id -> points taken today (capped)
var day_med := 0.0            # sense taken from sitting today (capped)
var cont := {"day": "", "n": 0, "level": "", "dao": ""}     # today's contemplations
var founded := {}             # {"dao", "name", "tenet"}
var _last_rank := {}


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/dao.json")
	reset()


func reset() -> void:
	sense = 0.0
	pts = {}
	focus = ""
	focus_day = ""
	day = ""
	day_pts = {}
	day_med = 0.0
	cont = {"day": "", "n": 0, "level": "", "dao": ""}
	founded = {}
	_last_rank = {}


func save_state() -> Dictionary:
	return {"sense": sense, "pts": pts, "focus": focus, "focus_day": focus_day, "day": day, "day_pts": day_pts, "day_med": day_med,
		"cont": cont, "founded": founded}


func load_state(d: Dictionary) -> void:
	reset()
	sense = float(d.get("sense", 0.0))
	var p = d.get("pts", {})
	if p is Dictionary:
		for k in p:
			if data.get("daos", {}).has(str(k)):
				pts[str(k)] = maxf(0.0, float(p[k]))
	focus = str(d.get("focus", "")) if data.get("daos", {}).has(str(d.get("focus", ""))) else ""
	focus_day = str(d.get("focus_day", ""))
	day = str(d.get("day", ""))
	var dp = d.get("day_pts", {})
	day_pts = dp if dp is Dictionary else {}
	day_med = float(d.get("day_med", 0.0))
	var c = d.get("cont", {})
	if c is Dictionary:
		cont = {"day": str(c.get("day", "")), "n": int(c.get("n", 0)), "level": str(c.get("level", "")), "dao": str(c.get("dao", ""))}
	var f = d.get("founded", {})
	founded = f if (f is Dictionary and data.get("daos", {}).has(str(f.get("dao", "")))) else {}
	for k in data.get("daos", {}):
		_last_rank[k] = _rank_of(str(k))


# ---- the numbers -------------------------------------------------------------------------------------------------------

func dao_ids() -> Array:
	return data.get("daos", {}).keys()


func def(did: String) -> Dictionary:
	return data.get("daos", {}).get(did, {})


func stage() -> int:
	var st: Array = data.get("sense_stages", [])
	var s := 0
	for i in st.size():
		if sense >= float(st[i][0]):
			s = i
	return s


func stage_name() -> String:
	var st: Array = data.get("sense_stages", [])
	return str(st[stage()][1]) if not st.is_empty() else "Dull"


func stage_text() -> String:
	var st: Array = data.get("sense_stages", [])
	return str(st[stage()][2]) if not st.is_empty() else ""


func next_stage_at() -> float:
	var st: Array = data.get("sense_stages", [])
	var s := stage()
	return float(st[s + 1][0]) if s + 1 < st.size() else -1.0


func _rank_of(did: String) -> int:
	## by points alone
	var rk: Array = data.get("ranks", [0])
	var p := float(pts.get(did, 0.0))
	var r := 0
	for i in rk.size():
		if p >= float(rk[i]):
			r = i
	return r


func rank(did: String) -> int:
	## the rank you can actually use: points, held down by how much you can sense
	return mini(_rank_of(did), stage())


func rank_name(r: int) -> String:
	var n: Array = data.get("rank_names", [])
	return str(n[clampi(r, 0, n.size() - 1)]) if not n.is_empty() else ""


func next_rank_at(did: String) -> float:
	var rk: Array = data.get("ranks", [0])
	var r := _rank_of(did)
	return float(rk[r + 1]) if r + 1 < rk.size() else -1.0


func is_founded(did: String) -> bool:
	return not founded.is_empty() and str(founded.get("dao", "")) == did


func can_found() -> bool:
	if not founded.is_empty() or focus == "":
		return false
	var rk: Array = data.get("ranks", [0])
	return stage() >= rk.size() - 1 and _rank_of(focus) >= rk.size() - 1


func today() -> String:
	return G.today()


func _roll_day() -> void:
	if day != today():
		day = today()
		day_pts = {}
		day_med = 0.0


func resonance(level_id: String) -> String:
	## the dao a place leans toward -- fixed by the place, the same for everyone
	var ids := dao_ids()
	ids.sort()
	if ids.is_empty():
		return ""
	return str(ids[absi(level_id.hash()) % ids.size()])


# ---- growth --------------------------------------------------------------------------------------------------------------

func gain(did: String, n: float, quiet: bool = false) -> float:
	## points in a dao (capped per day), a little sense with them. Returns what was taken.
	if n <= 0.0 or not data.get("daos", {}).has(did):
		return 0.0
	_roll_day()
	var cap := float(data.get("day_cap_per_dao", 80))
	var take := minf(n, maxf(0.0, cap - float(day_pts.get(did, 0.0))))
	if take <= 0.0:
		return 0.0
	day_pts[did] = float(day_pts.get(did, 0.0)) + take
	pts[did] = float(pts.get(did, 0.0)) + take
	_add_sense(take * float(data.get("sense_share", 0.25)))
	_check_rank(did, quiet)
	return take


func _add_sense(n: float) -> void:
	var before := stage()
	sense += n
	if stage() > before:
		var st: Array = data.get("sense_stages", [])
		G.message.emit(I18n.t("DAO SENSE -- %s. %s") % [str(st[stage()][1]), str(st[stage()][2])])
		G.log_event("dao_sense", {"stage": stage()})
		for k in dao_ids():
			_check_rank(str(k), false)


func _check_rank(did: String, quiet: bool) -> void:
	var r := rank(did)
	var was := int(_last_rank.get(did, 0))
	if r > was:
		_last_rank[did] = r
		if not quiet:
			G.message.emit(I18n.t("DAO -- %s: %s. %s") % [str(def(did).get("name", did)), rank_name(r), I18n.t("Follow it from the Dao page to deepen it faster.") if focus == "" else ""])
		G.log_event("dao_rank", {"dao": did, "rank": r})
		G.stats_changed.emit()
	elif r < was:
		_last_rank[did] = r


func on_event(kind: String, d: Dictionary) -> void:
	var row: Dictionary = data.get("events", {}).get(kind, {})
	if row.is_empty():
		return
	for did in row:
		var n := float(row[did])
		if str(did) == focus:
			n *= 1.0 + float(data.get("focus_bonus", 0.6))
		if cont.get("day", "") == today() and str(cont.get("level", "")) == G.current_level and str(cont.get("dao", "")) == str(did):
			n *= 1.0 + float(data.get("resonance_bonus", 1.0))
		gain(str(did), n)


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	_roll_day()
	var cap := float(data.get("sense_meditate_day_cap", 60))
	var take := minf(secs * float(data.get("sense_per_second", 0.02)), maxf(0.0, cap - day_med))
	if take > 0.0:
		day_med += take
		_add_sense(take)
	if focus == "tide":
		gain("tide", secs * 0.01, true)


# ---- what you can do -----------------------------------------------------------------------------------------------------

func contemplates_left() -> int:
	if str(cont.get("day", "")) != today():
		return int(data.get("contemplate_per_day", 3))
	return maxi(0, int(data.get("contemplate_per_day", 3)) - int(cont.get("n", 0)))


func contemplate() -> String:
	## stand still where you are and feel which way it leans
	if contemplates_left() <= 0:
		return I18n.t("You have looked as hard as you can today. Come back tomorrow.")
	if G.current_level == "":
		return I18n.t("Nothing to feel here.")
	if str(cont.get("day", "")) != today():
		cont = {"day": today(), "n": 0, "level": "", "dao": ""}
	cont["n"] = int(cont["n"]) + 1
	var st := stage()
	_add_sense(float(data.get("contemplate_sense", 4.0)) * (1.0 + 0.3 * st))
	var here := resonance(G.current_level)
	G.log_event("dao_contemplate", {"level": G.current_level, "dao": here, "stage": st})
	if st < 2:
		return I18n.t("You stand still. The air seems to lean, but you cannot tell which way. (Dao sense grows with sitting, and with doing.)")
	cont["level"] = G.current_level
	cont["dao"] = here
	G.stats_changed.emit()
	return I18n.t("This place leans toward the %s dao. Today, what you do here in its way is understood twice as deeply.") % str(def(here).get("name", here))


func set_focus(did: String) -> String:
	if not data.get("daos", {}).has(did):
		return ""
	if did == focus:
		return I18n.t("You already follow the %s dao.") % str(def(did).get("name", did))
	if focus != "" and focus_day == today():
		return I18n.t("You changed your mind today already. A way is not chosen twice in a day.")
	focus = did
	focus_day = today()
	G.log_event("dao_focus", {"dao": did})
	G.stats_changed.emit()
	return I18n.t("You turn toward the %s dao.") % str(def(did).get("name", did))


func found(own_name: String, tenet_id: String) -> String:
	if not can_found():
		return I18n.t("You are not ready to found a dao of your own.")
	var nm := own_name.strip_edges().left(28)
	if nm == "":
		return I18n.t("A dao needs a name.")
	var ok := false
	for t in def(focus).get("tenets", []):
		if str(t[0]) == tenet_id:
			ok = true
	if not ok:
		return I18n.t("Choose one of the tenets.")
	founded = {"dao": focus, "name": nm, "tenet": tenet_id}
	G.log_event("dao_founded", {"dao": focus, "name": nm, "tenet": tenet_id})
	G.stats_changed.emit()
	G.message.emit("You found your own dao: %s." % nm)
	return I18n.t("You found %s, a way of the %s.") % [nm, str(def(focus).get("name", focus))]


# ---- what it gives ---------------------------------------------------------------------------------------------------------

func _is_additive(key: String) -> bool:
	return key in G.ADDITIVE_KEYS or key.begins_with("craft_")


func dao_fx(did: String) -> Dictionary:
	var r := rank(did)
	if r <= 0:
		return {}
	var s := float(data.get("scale", [0])[r])
	var m := 1.0 if did == focus else float(data.get("off_focus", 0.6))
	if is_founded(did):
		m *= float(data.get("founded_mult", 1.5))
	var out := {}
	var fx: Dictionary = def(did).get("fx", {})
	for k in fx:
		var v := s * float(fx[k]) * m
		out[k] = v if _is_additive(str(k)) else 1.0 + v
	return out


func effects() -> Array:
	var out := []
	for did in dao_ids():
		var e := dao_fx(str(did))
		if not e.is_empty():
			out.append(e)
	if not founded.is_empty():
		for t in def(str(founded["dao"])).get("tenets", []):
			if str(t[0]) == str(founded.get("tenet", "")):
				out.append((t[3] as Dictionary).duplicate())
	return out


func summary_line() -> String:
	if stage() == 0:
		return I18n.t("Dao sense: dull")
	var f := ""
	if focus != "":
		f = " · following %s" % (str(founded["name"]) if is_founded(focus) else str(def(focus).get("name", focus)))
	return I18n.t("Dao sense: %s%s") % [stage_name(), f]
