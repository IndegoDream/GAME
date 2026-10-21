extends "res://scripts/systems/GameSystem.gd"
## The Paths (round 121). Robert, 2026-10-16: "build out several more class
## types the players can build out." Nine classes, each a road of five ranks.
##
##   * you walk ONE path (the primary). From rank 3 a SECOND opens and gives
##     half of what a path gives -- a hybrid, never a double.
##   * ranks are earned by DEEDS (kills with the right weapon, parries, shots,
##     crafts ...), counted from the play log, and held back by your realm.
##   * each rank gives a perk (data/classes.json "always" / "weapon" -- the
##     weapon ones only count while that kind of weapon is in hand).
##     Rank 2 teaches the path's signature ART (key 6 / the PATH button);
##     rank 4 a KEYSTONE: something that happens when you do the path's thing.
##   * every total is capped per key (data/classes.json "caps").
## Switching your primary costs gold (free while you are still rank 1).
## Rank and deeds are kept per path: go away and come back, nothing is lost.

const FX := preload("res://scripts/fx/FX.gd")

var cfg := {}
var primary := ""
var secondary := ""
var art_slot := "primary"             # which path's art key 6 casts
var prog := {}                        # path id -> {deed: count}
var ranks := {}                       # path id -> rank reached (1..5)
var _cool := {}                       # path id -> seconds until its art is ready
var _icd := {}                        # keystone id -> seconds until it can fire again
var _riposte_t := 0.0
var _riposte := {}
var _fx: Array = []
var _fx_key := ""
var _offered := false


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/classes.json", {})
	cfg = d if d is Dictionary else {}
	_fx_key = ""


func reset() -> void:
	primary = ""
	secondary = ""
	art_slot = "primary"
	prog = {}
	ranks = {}
	_cool = {}
	_icd = {}
	_riposte_t = 0.0
	_fx = []
	_fx_key = ""
	_offered = false


func save_state() -> Dictionary:
	return {"primary": primary, "secondary": secondary, "art_slot": art_slot, "prog": prog, "ranks": ranks, "offered": _offered}


func load_state(d: Dictionary) -> void:
	primary = str(d.get("primary", ""))
	secondary = str(d.get("secondary", ""))
	art_slot = str(d.get("art_slot", "primary"))
	var p = d.get("prog", {})
	prog = p if p is Dictionary else {}
	var r = d.get("ranks", {})
	ranks = r if r is Dictionary else {}
	_offered = bool(d.get("offered", false))
	_cool = {}
	_icd = {}
	_fx = []
	_fx_key = ""
	if def(primary).is_empty():
		primary = ""
	if def(secondary).is_empty() or secondary == primary:
		secondary = ""


# ---- reading the data ------------------------------------------------------------------

func paths() -> Array:
	return cfg.get("paths", [])


func def(pid: String) -> Dictionary:
	for p in paths():
		if str(p.get("id", "")) == pid:
			return p
	return {}


func rank_name(i: int) -> String:
	var n: Array = cfg.get("rank_names", ["Initiate", "Adept", "Veteran", "Master", "Paragon"])
	return str(n[clampi(i - 1, 0, n.size() - 1)])


func rank_of(pid: String) -> int:
	return int(ranks.get(pid, 0))


func deed(pid: String, did: String) -> int:
	var d: Dictionary = prog.get(pid, {})
	return int(d.get(did, 0))


func rank_def(pid: String, r: int) -> Dictionary:
	var rs: Array = def(pid).get("ranks", [])
	if r < 1 or r > rs.size():
		return {}
	return rs[r - 1]


func has_art(pid: String) -> bool:
	return rank_of(pid) >= 2 and not (def(pid).get("art", {}) as Dictionary).is_empty()


func share_of(pid: String) -> float:
	if pid == primary:
		return 1.0
	if pid == secondary:
		return float(cfg.get("second_path_share", 0.5))
	return 0.0


func walking() -> Array:
	var out := []
	if primary != "":
		out.append(primary)
	if secondary != "":
		out.append(secondary)
	return out


func suggested() -> String:
	## the path your past points at (shown on the Path page; never chosen for you)
	var bg := str(G.background)
	var map := {"swordsman": "duelist", "spearman": "vanguard", "woodcutter": "vanguard", "cutpurse": "shadowblade", "wanderer": "ki_adept",
		"smith": "forgewright", "physician": "mender", "herbalist": "mender", "alchemist": "mender", "miner": "delver", "fisher": "delver",
		"jeweler": "delver", "hunter": "ranger"}
	return str(map.get(bg, ""))


# ---- choosing --------------------------------------------------------------------------

func respec_cost() -> int:
	if primary == "" or rank_of(primary) < int(cfg.get("respec_free_below_rank", 2)):
		return 0
	return int(cfg.get("respec_gold_per_realm", 120)) * (1 + G.realm)


func can_second() -> bool:
	return primary != "" and rank_of(primary) >= int(cfg.get("second_path_rank", 3))


func choose(pid: String, as_second: bool = false) -> Dictionary:
	## {ok, text}. The first choice is free; changing a path you've grown costs gold.
	if def(pid).is_empty():
		return {"ok": false, "text": "No such path."}
	if as_second:
		if not can_second():
			return {"ok": false, "text": "A second path opens at %s on your first." % rank_name(int(cfg.get("second_path_rank", 3)))}
		if pid == primary:
			return {"ok": false, "text": "That is already your first path."}
		if pid == secondary:
			return {"ok": false, "text": "That is already your second path."}
		secondary = pid
		ranks[pid] = maxi(1, rank_of(pid))
		_changed()
		_check_ranks()
		return {"ok": true, "text": "Second path: %s. It gives half of what a path gives." % str(def(pid).get("name", pid))}
	if pid == primary:
		return {"ok": false, "text": "That is already your path."}
	var cost := respec_cost() if primary != "" else 0
	if cost > G.gold:
		return {"ok": false, "text": I18n.t("Changing path costs %d gold; you have %d.") % [cost, G.gold]}
	G.gold -= cost
	var old := primary
	primary = pid
	ranks[pid] = maxi(1, rank_of(pid))
	if secondary == pid:
		secondary = ""
	art_slot = "primary"
	_changed()
	_check_ranks()
	G.log_event("path_chosen", {"id": pid, "from": old})
	return {"ok": true, "text": I18n.t("You take the road of the %s%s.") % [str(def(pid).get("name", pid)), (I18n.t(" (%d gold)") % cost) if cost > 0 else ""]}


func drop_second() -> void:
	secondary = ""
	if art_slot == "second":
		art_slot = "primary"
	_changed()


func set_art_slot(s: String) -> void:
	art_slot = "second" if (s == "second" and secondary != "") else "primary"


func cycle_art() -> String:
	if secondary == "":
		return I18n.t("You walk one path.")
	art_slot = "second" if art_slot == "primary" else "primary"
	var pid := _slot_path()
	return I18n.t("Readied: %s.") % str(def(pid).get("art", {}).get("name", I18n.t("(no art yet)")))


func _slot_path() -> String:
	return secondary if (art_slot == "second" and secondary != "") else primary


func _changed() -> void:
	_fx_key = ""
	G.stats_changed.emit()


# ---- ranks -----------------------------------------------------------------------------

func next_needs(pid: String) -> Dictionary:
	## {rank, name, realm_ok, realm_need, needs: [{id,label,have,need}], met}
	var r := rank_of(pid) + 1
	var rd := rank_def(pid, r)
	if rd.is_empty():
		return {}
	var out := {"rank": r, "name": str(rd.get("name", "")), "realm_need": int(rd.get("realm", 0)), "needs": [], "text": str(rd.get("text", ""))}
	out["realm_ok"] = G.realm >= int(out["realm_need"])
	var met := bool(out["realm_ok"])
	var dd: Dictionary = def(pid).get("deeds", {})
	var nd: Dictionary = rd.get("needs", {})
	for k in nd:
		var have := deed(pid, str(k))
		var need := int(nd[k])
		if have < need:
			met = false
		(out["needs"] as Array).append({"id": str(k), "label": str(dd.get(k, {}).get("label", k)), "have": mini(have, need), "need": need})
	out["met"] = met
	return out


func _check_ranks() -> void:
	for pid in walking():
		var guard := 0
		while guard < 6:
			guard += 1
			var nn := next_needs(str(pid))
			if nn.is_empty() or not bool(nn.get("met", false)):
				break
			var r := int(nn["rank"])
			ranks[str(pid)] = r
			_fx_key = ""
			var rd := rank_def(str(pid), r)
			var line := I18n.t("PATH: %s -- %s, rank %d: %s.") % [str(def(str(pid)).get("name", pid)), rank_name(r), r, str(rd.get("name", ""))]
			G.message.emit(line)
			if bool(rd.get("art", false)):
				G.message.emit(I18n.t("You learn %s -- press %s.") % [str(def(str(pid)).get("art", {}).get("name", "")), str(cfg.get("key", "6"))])
			if rd.has("trigger"):
				G.message.emit("Keystone: %s" % str((rd["trigger"] as Dictionary).get("text", "")))
			var ti := str(rd.get("title", ""))
			if ti != "" and not G.titles.has(ti):
				G.titles.append(ti)
				G.message.emit("TITLE: %s." % ti)
			G.log_event("path_rank", {"id": str(pid), "rank": r})
			G.stats_changed.emit()


# ---- deeds -----------------------------------------------------------------------------

func _recipe_skill(makes: String) -> String:
	for r in G.recipes:
		if str(r.get("makes", "")) == makes:
			return str(r.get("skill", ""))
	return ""


func _passes(f: Dictionary, kind: String, data: Dictionary) -> bool:
	## the filters a deed or keystone can carry
	if f.has("skills") and not (G.weapon_skill() in (f["skills"] as Array)):
		return false
	if f.has("charged") and bool(data.get("charged", false)) != bool(f["charged"]):
		return false
	if bool(f.get("success", false)) and not bool(data.get("success", true)):
		return false
	if f.has("craft_skills"):
		var sk := _recipe_skill(str(data.get("makes", ""))) if kind == "craft" else str(data.get("family", ""))
		if kind == "craft" and not (sk in (f["craft_skills"] as Array)):
			return false
	if f.has("gather_kinds") and not (str(data.get("kind", "")) in (f["gather_kinds"] as Array)):
		return false
	if bool(f.get("heal", false)):
		var def_i: Dictionary = G.item_def(str(data.get("id", ""))) if G.has_item_def(str(data.get("id", ""))) else {}
		if not def_i.has("heal"):
			return false
	return true


func on_event(kind: String, data: Dictionary) -> void:
	if primary == "":
		_offer_check(kind)
		return
	var changed := false
	for pid in walking():
		var dd: Dictionary = def(str(pid)).get("deeds", {})
		for did in dd:
			var d: Dictionary = dd[did]
			if not (kind in (d.get("ev", []) as Array)):
				continue
			if not _passes(d, kind, data):
				continue
			if not prog.has(str(pid)):
				prog[str(pid)] = {}
			prog[str(pid)][str(did)] = int(prog[str(pid)].get(str(did), 0)) + 1
			changed = true
	if changed:
		_check_ranks()
	_run_keystones(kind, data)
	if kind == "parry" and _riposte_t > 0.0 and not _riposte.is_empty():
		_arm(float(_riposte.get("mult", 1.5)), float(_riposte.get("secs", 3.0)))


func _offer_check(kind: String) -> void:
	## the one-time nudge: after a handful of kills, say the Paths exist (never opens a window)
	if _offered or kind != "kill":
		return
	if float(G.counters.get("paths_kills", 0.0)) < 4.0:
		G.counters["paths_kills"] = float(G.counters.get("paths_kills", 0.0)) + 1.0
		return
	_offered = true
	var s := suggested()
	var hint := ""
	if s != "":
		hint = " Your past points toward the %s." % str(def(s).get("name", s))
	G.message.emit(I18n.t("PATHS: you can walk a Path now -- menu > Path. Nine roads, ranks earned by what you do, an art on key %s.%s") % [str(cfg.get("key", "6")), hint])


func _player():
	return G.get_tree().get_first_node_in_group("player") if G.get_tree() != null else null


func _arm(mult: float, secs: float) -> void:
	var p = _player()
	if p == null:
		return
	p._ambush_mult = maxf(float(p._ambush_mult) if float(p._ambush_t) > 0.0 else 1.0, mult)
	p._ambush_t = maxf(float(p._ambush_t), secs)


func _run_keystones(kind: String, data: Dictionary) -> void:
	for pid in walking():
		var share := share_of(str(pid))
		var rk := rank_of(str(pid))
		for i in range(1, rk + 1):
			var rd := rank_def(str(pid), i)
			if not rd.has("trigger"):
				continue
			var t: Dictionary = rd["trigger"]
			if str(t.get("on", "")) != kind:
				continue
			var key := "%s:%d" % [str(pid), i]
			if float(_icd.get(key, 0.0)) > 0.0:
				continue
			if not _passes(t, kind, data):
				continue
			_icd[key] = float(t.get("icd", 1.0))
			_fire(str(pid), key, t, share)


func _fire(pid: String, key: String, t: Dictionary, share: float) -> void:
	match str(t.get("do", "")):
		"ambush":
			_arm(1.0 + (float(t.get("mult", 1.3)) - 1.0) * share, float(t.get("secs", 3.0)))
		"buff":
			var e := delta_to_effect(t.get("effect", {}) as Dictionary, share)
			G.add_buff("path_" + key.replace(":", "_"), e, float(t.get("secs", 3.0)))
		"ki":
			var p = _player()
			if p != null:
				var R: Dictionary = G.ranged_data("") if G.weapon_is_ranged() else {}
				var cap := float(R.get("pool", 6.0)) if not R.is_empty() else 6.0
				p.ki_shots = minf(cap, float(p.ki_shots) + float(t.get("n", 1.0)) * share)
		"heal_pct":
			G.heal(maxi(1, int(round(G.max_hp() * float(t.get("pct", 0.02)) * share))))


# ---- effects ---------------------------------------------------------------------------

func delta_to_effect(deltas: Dictionary, share: float = 1.0) -> Dictionary:
	## {"damage_taken": -0.3} -> {"damage_taken": 0.7}; additive keys stay deltas
	var out := {}
	for k in deltas:
		G._fold_effect(out, str(k), float(deltas[k]) * share)
	return out


func effects() -> Array:
	var sk: String = G.weapon_skill()
	var key := "%s|%s|%d|%d|%s" % [primary, secondary, rank_of(primary), rank_of(secondary), sk]
	if key != _fx_key:
		_fx_key = key
		_fx = [_build_effect(sk)]
	return _fx


func _build_effect(sk: String) -> Dictionary:
	var raw := {}
	for pid in walking():
		var share := share_of(str(pid))
		for i in range(1, rank_of(str(pid)) + 1):
			var rd := rank_def(str(pid), i)
			var al: Dictionary = rd.get("always", {})
			for k in al:
				raw[str(k)] = float(raw.get(str(k), 0.0)) + float(al[k]) * share
			if rd.has("weapon"):
				var w: Dictionary = rd["weapon"]
				if sk in (w.get("skills", []) as Array):
					var we: Dictionary = w.get("effect", {})
					for k2 in we:
						raw[str(k2)] = float(raw.get(str(k2), 0.0)) + float(we[k2]) * share
	var caps: Dictionary = cfg.get("caps", {})
	var out := {}
	for k3 in raw:
		var v := float(raw[k3])
		if caps.has(k3):
			var c := float(caps[k3])
			v = maxf(v, c) if c < 0.0 else minf(v, c)
		G._fold_effect(out, str(k3), v)
	return out


func capped_total(pid: String) -> Dictionary:
	## for the tests and the page: this path's own totals per key (weapon perks as w:key)
	var out := {}
	for i in range(1, 6):
		var rd := rank_def(pid, i)
		for k in (rd.get("always", {}) as Dictionary):
			out[str(k)] = float(out.get(str(k), 0.0)) + float(rd["always"][k])
		if rd.has("weapon"):
			for k2 in (rd["weapon"]["effect"] as Dictionary):
				out[str(k2)] = float(out.get(str(k2), 0.0)) + float(rd["weapon"]["effect"][k2])
	return out


# ---- the art (key 6) -------------------------------------------------------------------

func tick(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] = maxf(0.0, float(_cool[k]) - delta)
	for k2 in _icd.keys():
		_icd[k2] = maxf(0.0, float(_icd[k2]) - delta)
	if _riposte_t > 0.0:
		_riposte_t = maxf(0.0, _riposte_t - delta)


func art_power(pid: String) -> float:
	var p := 1.0 + 0.12 * float(maxi(0, rank_of(pid) - 2))
	return p * (1.0 if pid == primary else 0.75)


func art_cooldown_left() -> float:
	return float(_cool.get(_slot_path(), 0.0))


func art_line() -> String:
	## the HUD's status line ("" when there is nothing to show)
	var pid := _slot_path()
	if pid == "" or not has_art(pid):
		return ""
	var a: Dictionary = def(pid).get("art", {})
	var left := float(_cool.get(pid, 0.0))
	if left > 0.05:
		return "%s [%s]: %ds" % [str(a.get("name", "")), str(cfg.get("key", "6")), int(ceil(left))]
	return I18n.t("%s [%s]: ready") % [str(a.get("name", "")), str(cfg.get("key", "6"))]


func cast() -> String:
	## key 6. Returns the line to show ("" = nothing happened silently)
	var pid := _slot_path()
	if pid == "":
		return I18n.t("You walk no path yet -- menu > Path.")
	if not has_art(pid):
		return I18n.t("Your path teaches its art at %s.") % rank_name(2)
	var a: Dictionary = def(pid).get("art", {})
	var left := float(_cool.get(pid, 0.0))
	if left > 0.05:
		return I18n.t("%s is not ready (%ds).") % [str(a.get("name", "")), int(ceil(left))]
	if str(a.get("needs", "")) == "ranged" and not G.weapon_is_ranged():
		return I18n.t("%s needs a bow, crossbow or qi focus in hand.") % str(a.get("name", ""))
	var p = _player()
	if p == null:
		return ""
	var pw := art_power(pid)
	var secs := float(a.get("secs", 6.0))
	if a.has("buff"):
		var b: Dictionary = a["buff"]
		var scaled := {}
		for k in b:
			var v := float(b[k]) * pw
			if str(k) == "damage_taken":
				v = maxf(v, -0.6)
			if str(k) == "dodge_chance":
				v = minf(v, 0.3)
			scaled[str(k)] = v
		G.add_buff("pathart", delta_to_effect(scaled, 1.0), secs)
	if a.has("slam"):
		var s: Dictionary = a["slam"]
		var rad := float(s.get("radius", 4.0))
		var hit := 0
		for e in G.get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and not e._dead and (e.global_position - p.global_position).length() <= rad:
				e.take_damage(maxi(1, int(round(G.damage() * float(s.get("mult", 1.3)) * pw))), "you (%s)" % str(a.get("name", "")))
				if is_instance_valid(e) and e.has_method("stagger"):
					e.stagger(float(s.get("stagger", 1.5)))
				if is_instance_valid(e) and e.get("affixes") != null and "armoured" in e.affixes:
					e.set("sundered", 4.0)                     # the slam splits plating, as an axe does
					e.set("sunder_mult", 1.25)
				hit += 1
		if FX.on():
			FX.hit(p.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.5), true)
	if a.has("dash"):
		var fwd := Vector3(sin(p._model.rotation.y), 0, cos(p._model.rotation.y))
		p._dash_dir = fwd.normalized()
		p._dash_t = 0.22 * float(a["dash"]) / 7.0
		p._hurt_cool = 0.4
	if a.has("ambush"):
		_arm(1.0 + (float((a["ambush"] as Dictionary).get("mult", 2.0)) - 1.0) * minf(pw, 1.0), float((a["ambush"] as Dictionary).get("secs", 3.0)))
	if a.has("heal_pct"):
		G.heal(maxi(1, int(round(G.max_hp() * float(a["heal_pct"]) * pw))))
	if a.has("mend") and not G.injury.is_empty():
		G.mend_injuries(float(a["mend"]))
	if bool(a.get("refill_ki", false)):
		var R: Dictionary = G.ranged_data("") if G.weapon_is_ranged() else {}
		p.ki_shots = maxf(float(p.ki_shots), float(R.get("pool", 6.0)) if not R.is_empty() else 6.0)
	if a.has("on_parry_ambush"):
		_riposte = (a["on_parry_ambush"] as Dictionary).duplicate()
		_riposte_t = secs
	_cool[pid] = float(a.get("cooldown", 25.0)) * (1.0 if pid == primary else 1.25)
	if FX.on():
		FX.word(p.global_position + Vector3(0, 2.4, 0), str(a.get("name", "")).to_upper(), Color(def(pid).get("color", [1, 1, 1])[0], def(pid).get("color", [1, 1, 1])[1], def(pid).get("color", [1, 1, 1])[2]), 38)
	G.sfx("swing", 0.9)
	G.log_event("path_art", {"id": pid})
	return "%s!" % str(a.get("name", ""))
