extends "res://scripts/systems/GameSystem.gd"
## Round 152 (Robert: "what else would make this game more inviting and addicting"). The small things that make
## the next minute worth playing:
##   * teasers()      -- the few things closest to done (a step, a point, a bond stage, a chapter, an oath), so a
##                       run ends on "just a little more" instead of on a bare tally
##   * sit_line()     -- while you sit: how long, how fast qi comes, and when the next step lands
##   * omens          -- now and then something glows in the deep (a cache, a spirit, a hermit's afterglow); walk into it
##   * barks          -- the beasts and people at your side say a line when a floor opens, a master falls, a floor is cleared
##   * pet / feed     -- a real answer to "scratch behind the ears": a little bond, a role-flavoured reaction
##   * streak titles  -- a name earned by coming back (7, 14, 30, 60, 100 days)
## Fair pay: everything here is earned by playing; nothing is bought or exclusive.

var cfg := {}
var _sit_t := 0.0
var _sit_q0 := 0.0
var _sit_rate := 0.0
var _bark_at := -999.0
var _was_sitting := false
var omens_found := 0
var _ready_t := 5.0
var _was_ready := {}


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/pull.json", {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	omens_found = 0
	_bark_at = -999.0


func save_state() -> Dictionary:
	return {"omens": omens_found}


func load_state(d: Dictionary) -> void:
	omens_found = int(d.get("omens", 0))


# ---- teasers -----------------------------------------------------------------------------------------------------

func candidates() -> Array:
	## [fraction, text] -- every thing that is partway to done
	var out := []
	var need: float = G.qi_to_next()
	if need > 0.0 and G.qi < need:
		out.append([G.qi / need, I18n.t("Your next step: %d%% of the way") % int(G.qi / need * 100.0)])
	if G.lattice_focus != "" and not G.lattice.has(G.lattice_focus):
		var f: float = G.point_fraction(G.lattice_focus)
		out.append([f, I18n.t("%s: %d%% open") % [str(G.lattice_point(G.lattice_focus).get("name", G.lattice_focus)), int(f * 100.0)]])
	var WS = G.sys("stories")
	var MN = G.sys("menagerie")
	if MN != null:
		for nm in MN.party_wayfarers():
			if WS != null and WS.act.has(nm) and not WS.goal_of(nm).is_empty():
				var p: Array = WS.progress(nm)
				if int(p[1]) > 0:
					if WS.is_ready(nm):
						out.append([1.0, I18n.t("%s is waiting for you to finish their chapter") % nm])
					else:
						out.append([float(p[0]) / float(p[1]), I18n.t("%s's chapter: %d of %d") % [nm, int(p[0]), int(p[1])]])
			var ot := float(MN.data.get("trust", {}).get("oath_trust", 60))
			var tr: float = MN.trust_of(nm)
			if not MN.is_sworn(nm) and tr < ot:
				out.append([tr / ot, I18n.t("%s's trust: %d of %d for an oath") % [nm, int(tr), int(ot)]])
	var stages: Array = G.companions_data().get("familiar", {}).get("stages", [])
	for b in G.beasts_out():
		var bond := float(b.get("bond", 0.0))
		for s in stages:
			var sb := float(s.get("bond", 0))
			if sb > bond:
				out.append([bond / sb, I18n.t("%s: bond %d of %d for its next form") % [str(b.get("name", "")), int(bond), int(sb)]])
				break
	var SK = G.sys("seek")
	if SK != null:
		for sl in [0, 1]:
			if SK.searching(sl):
				var ss: Dictionary = SK.state(sl)
				var tot: float = maxf(1.0, float(ss.get("end", 0.0)) - float(ss.get("start", 0.0)))
				var fr: float = clampf(1.0 - SK.left(sl) / tot, 0.0, 0.99)
				out.append([fr, I18n.t("%s's search: back in %s") % [str(G.cslot(sl).get("name", "")), G._dur(SK.left(sl))]])
	var CN = G.sys("constructs")
	if CN != null and not CN.voyage.is_empty():
		var vt: float = maxf(1.0, float(CN.voyage.get("end", 0.0)) - float(CN.voyage.get("start", 0.0)))
		out.append([clampf(1.0 - CN.voyage_left() / vt, 0.0, 0.99), I18n.t("%s's voyage: home in %s") % [str(CN.voyage.get("crew", "")), G._dur(CN.voyage_left())]])
	var al: String = G.almost()
	if al != "":
		out.append([0.9, al])
	return out


func teasers(n: int = -1) -> Array:
	var t: Dictionary = cfg.get("teaser", {})
	var lo := float(t.get("min_frac", 0.55))
	var mx := n if n > 0 else int(t.get("max", 3))
	var c := candidates().filter(func(x): return float(x[0]) >= lo)
	c.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out := []
	for x in c:
		out.append(str(x[1]))
		if out.size() >= mx:
			break
	return out


func teaser_block() -> String:
	var t := teasers()
	if t.is_empty():
		return ""
	return I18n.t("Nearly there:") + "\n  " + "\n  ".join(t)


# ---- sitting -----------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_ready_t -= delta
	if _ready_t <= 0.0:
		_ready_t = 3.0
		_deed_cues()
	if G.sitting:
		if not _was_sitting:
			_was_sitting = true
			_sit_t = 0.0
			_sit_q0 = G.qi
			_sit_rate = 0.0
		_sit_t += delta
		if _sit_t > 4.0:
			var inst := maxf(0.0, G.qi - _sit_q0) / _sit_t * 60.0       # qi a minute since you sat (adds from other sources count too)
			_sit_rate = inst
	else:
		_was_sitting = false


func _deed_cues() -> void:
	## a soft chime and a line when a deed you asked for is ready to ask again
	var MN = G.sys("menagerie")
	if MN == null or G.current_level == "title":
		return
	var now := {}
	for b in G.beasts_out():
		var di: Dictionary = MN.beast_deed_info(b)
		if not di.is_empty():
			now["b:" + str(b.get("name", ""))] = [float(di.get("left", 0.0)) <= 0.0, str(b.get("name", "")), str(di.get("name", ""))]
	for nm in MN.party_wayfarers():
		var hi: Dictionary = MN.human_deed_info(nm)
		if not hi.is_empty():
			now["h:" + nm] = [float(hi.get("left", 0.0)) <= 0.0, nm, str(hi.get("name", ""))]
	for k in now:
		var rdy: bool = now[k][0]
		if rdy and _was_ready.has(k) and not bool(_was_ready[k]):
			G.sfx("ui_ok", 0.55)
			G.message.emit(I18n.t("%s is ready again: %s") % [str(now[k][1]), str(now[k][2])])
		_was_ready[k] = rdy


func sit_line() -> String:
	if not G.sitting or _sit_t < 1.0:
		return ""
	var bits := [I18n.t("Sitting %s") % _mmss(_sit_t)]
	if _sit_rate > 0.05:
		bits.append(I18n.t("+%.1f qi a minute") % _sit_rate)
		var need: float = G.qi_to_next() - G.qi
		if need > 0.0:
			bits.append(I18n.t("next step in %s") % _mmss(need / _sit_rate * 60.0))
	if G.lattice_focus != "" and not G.lattice.has(G.lattice_focus):
		bits.append(I18n.t("%s %d%%") % [str(G.lattice_point(G.lattice_focus).get("name", G.lattice_focus)), int(G.point_fraction(G.lattice_focus) * 100.0)])
	return " · ".join(bits)


func _mmss(secs: float) -> String:
	var s := int(secs)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


# ---- omens -------------------------------------------------------------------------------------------------------

func pick_omen(rng: RandomNumberGenerator) -> String:
	var w: Dictionary = cfg.get("omen", {}).get("weights", {})
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	var r := rng.randf() * tot
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return str(k)
	return "cache"


func place(lvl) -> void:
	## called by Level after the beasts: now and then, something glows
	if lvl.is_town():
		return
	var lid := str(lvl.level_id)
	if lid.begins_with("online"):
		return
	var o: Dictionary = cfg.get("omen", {})
	var ch := float(o.get("valley_chance", 0.6)) if lid == "valley" else float(o.get("chance", 0.42))
	if not (lid.begins_with("floor") or lid == "valley"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("omen:%s:%d:%d" % [lid, int(G.Hook.today()), _salt()])          # one a day on a floor, the same place all day
	if G.has_flag(_taken_key(lid)) or rng.randf() > ch:
		return
	var MN = G.sys("menagerie")
	if MN == null:
		return
	var cells: Array = MN._cells(lvl)
	if cells.is_empty():
		return
	var cell: Vector2i = cells[rng.randi() % cells.size()]
	var kind := pick_omen(rng)
	lvl._spawn_script("res://scripts/actors/Omen.gd", lvl.cell_to_world(cell), {"cell": cell, "kind": kind})
	lvl._count("omens")
	var P: Array = lvl.spawns.get("P", [])
	var hint := ""
	if not P.is_empty():
		hint = _compass(Vector2(cell - (P[0] as Vector2i)))
	G.message.emit.call_deferred(I18n.t("Something glows in the distance%s.") % ((I18n.t(" -- to the %s") % hint) if hint != "" else ""))


func _salt() -> int:
	if int(G.counters.get("pull_salt", 0.0)) == 0:
		G.counters["pull_salt"] = float(randi() % 1000000 + 1)
	return int(G.counters["pull_salt"])


func _taken_key(lid: String) -> String:
	return "omen:%s:%d" % [lid, int(G.Hook.today())]


func _compass(d: Vector2) -> String:
	if d.length() < 3.0:
		return ""
	var a := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)          # 0 = up the map (north), clockwise
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return I18n.t(str(names[int(round(a / 45.0)) % 8]))


func omen_def(kind: String) -> Dictionary:
	return cfg.get("omens", {}).get(kind, {})


func collect(kind: String, at: Vector3) -> void:
	G.set_flag(_taken_key(str(G.current_level)))
	var d: int = maxi(G.depth, 1)
	var def := omen_def(kind)
	var rest := float(cfg.get("omen", {}).get("rest", 90.0))
	omens_found += 1
	G.jingle("discovery")
	G.banner.emit(I18n.t(str(def.get("name", "An omen"))).to_upper(), Color(0.95, 0.85, 0.5))
	var gives := []
	match kind:
		"cache":
			var gold := 25 + d * 12
			G.add_item("gold", gold, false)
			gives.append(I18n.t("%d gold") % gold)
			G.drop_gear(d, 1 + (1 if randf() < 0.25 else 0))
			gives.append(I18n.t("and a piece of gear"))
		"spirit":
			var q := 20.0 + d * 6.0
			G.add_qi(q, I18n.t("a wandering spirit"))
			G.add_buff("pull_spirit", {"move_mult": 1.1, "regen": 1.5, "sight": 2.0}, rest)
			gives.append(I18n.t("%d qi and a lightness for %d seconds") % [int(q), int(rest)])
		"sage":
			var ins := 3.0 + d * 0.5
			G.gain_insight(ins, "")
			G.add_buff("pull_sage", {"insight_mult": 1.25, "meditate_mult": 1.2}, rest * 2.0)
			gives.append(I18n.t("+%d insight and a calm that lasts") % int(ins))
	G.message.emit(I18n.t(str(def.get("found", ""))) + " (" + ", ".join(gives) + ")")
	G.log_event("omen", {"kind": kind})
	G.stats_changed.emit()


# ---- barks -------------------------------------------------------------------------------------------------------

func on_event(kind: String, d: Dictionary) -> void:
	var which := ""
	if kind == "enter_level" and str(d.get("id", "")).begins_with("floor"):
		which = "floor"
	elif kind == "boss_kill":
		which = "boss"
	elif kind == "floor_cleared":
		which = "clear"
	if which != "":
		_bark(which)
	if kind == "enter_level" and str(d.get("id", "")) == "valley":
		_nemesis()


func nemesis() -> String:
	## the rival who has beaten you most (more losses than wins); "" if none
	var best := ""
	var gap := 0
	for r in G.rivals:
		var rr: Dictionary = G.rivals[r]
		var g := int(rr.get("lost", 0)) - int(rr.get("beat", 0))
		if g > gap:
			gap = g
			best = str(r)
	return best


func _nemesis() -> void:
	var nm := nemesis()
	if nm != "":
		G.message.emit(I18n.t("Word on the road: %s is still waiting for a rematch.") % nm)


func _bark(which: String) -> void:
	var b: Dictionary = cfg.get("bark", {})
	if G.playtime - _bark_at < float(b.get("cool", 45.0)):
		return
	if randf() > float(b.get("chance", 0.55)) and which == "floor":
		return
	var MN = G.sys("menagerie")
	var who := []
	if MN != null:
		for nm in MN.party_wayfarers():
			who.append(["h", nm])
	for be in G.beasts_out():
		who.append(["b", be])
	if who.is_empty():
		return
	var pick: Array = who[randi() % who.size()]
	_bark_at = G.playtime
	if str(pick[0]) == "h":
		var style := str(MN.wayfarer(str(pick[1])).get("style", "guard"))
		var lines: Array = cfg.get("human_barks", {}).get(style, {}).get(which, [])
		if not lines.is_empty():
			G.message.emit("%s: \"%s\"" % [str(pick[1]), I18n.t(str(lines[randi() % lines.size()]))])
	else:
		var be2: Dictionary = pick[1]
		var line := beast_line(be2)
		if line != "":
			G.message.emit("%s %s" % [str(be2.get("name", "")), line])


func beast_line(be: Dictionary) -> String:
	var MN = G.sys("menagerie")
	var rid: String = MN.rid(be) if MN != null else ""
	var lines: Array = cfg.get("beast_barks", {}).get(rid, [])
	return I18n.t(str(lines[randi() % lines.size()])) if not lines.is_empty() else ""


# ---- petting and feeding -----------------------------------------------------------------------------------------

func _stamp(be: Dictionary, key: String, cool: float) -> bool:
	## true (and stamped) when the cooldown has passed
	var last := float(be.get(key, -99999.0))
	if G.playtime - last < cool:
		return false
	be[key] = G.playtime
	return true


func _raise(be: Dictionary, amount: float) -> void:
	be["bond"] = float(be.get("bond", 0.0)) + amount
	G.familiar_changed.emit()
	G.stats_changed.emit()


func pet(be: Dictionary) -> String:
	var p: Dictionary = cfg.get("pet", {})
	var nm := str(be.get("name", ""))
	if not _stamp(be, "pet_t", float(p.get("cool", 480.0))):
		return I18n.t("%s leans into your hand, content. (It has had your attention for now.)") % nm
	_raise(be, float(p.get("bond", 0.6)))
	G.sfx("pickup", 0.6)
	var line := beast_line(be)
	return I18n.t("%s leans into your hand. +bond.") % nm + ((" " + nm + " " + line) if line != "" else "")


func feed_item() -> String:
	for it in cfg.get("pet", {}).get("feed_items", []):
		if G.count(str(it)) > 0:
			return str(it)
	return ""


func feed(be: Dictionary) -> String:
	var p: Dictionary = cfg.get("pet", {})
	var nm := str(be.get("name", ""))
	var it := feed_item()
	if it == "":
		return I18n.t("You have nothing to feed %s (raw meat, a herb, broth or a moonpetal will do).") % nm
	if not _stamp(be, "feed_t", float(p.get("feed_cool", 240.0))):
		return I18n.t("%s is full for now.") % nm
	G.remove_item(it, 1)
	_raise(be, float(p.get("feed_bond", 2.0)))
	G.sfx("pickup", 0.6)
	return I18n.t("%s wolfs down the %s. +bond.") % [nm, G.item_name(it)]


# ---- streak titles -----------------------------------------------------------------------------------------------

func streak_title(streak: int) -> String:
	var t: Dictionary = cfg.get("streak_titles", {})
	return str(t.get(str(streak), ""))


func award_streak(streak: int) -> void:
	var tt := streak_title(streak)
	if tt != "" and not G.titles.has(tt):
		G.titles.append(tt)
		G.message.emit.call_deferred(I18n.t("A name for coming back: \"%s\".") % tt)


# ---- where ------------------------------------------------------------------------------------------------------

func where(kind: String) -> String:
	## " (about 40 m north-east)" for the nearest of: "elder" (Elder Mo), "shrine", "exit" (a way down); "" when unknown
	var tree: SceneTree = G.get_tree()
	if tree == null:
		return ""
	var pl = tree.get_first_node_in_group("player")
	if pl == null:
		return ""
	var best = null
	var bd := 1.0e9
	var nodes: Array = []
	match kind:
		"elder":
			nodes = tree.get_nodes_in_group("interactable").filter(func(n): return "role" in n and str(n.role) == "elder")
		"shrine":
			nodes = tree.get_nodes_in_group("shrine")
		"exit":
			nodes = tree.get_nodes_in_group("exit")
	for n in nodes:
		var d: float = (n.global_position - pl.global_position).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return ""
	if bd < 4.0:
		return " " + I18n.t("(right here)")
	var v: Vector3 = best.global_position - pl.global_position
	return " " + I18n.t("(about %d m %s)") % [int(round(bd)), _compass(Vector2(v.x, v.z))]
