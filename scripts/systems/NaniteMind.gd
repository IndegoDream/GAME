extends "res://scripts/systems/GameSystem.gd"
## Round 146: the swarm wakes. Robert, 2026-10-18: "have the nanites eventually turn into an ai companion whose personality is based on how
## the player has played the game up to that point; it can help connect to the ki and tech more effectively and efficiently; it can also
## provide tips, tricks and hints at key times utilizing the player's build, skills and aspects."
##   AWAKENS at swarm tier 4 (Nanite Ascendance). Its character is read from your play -- how much you fought, made, sat, wandered, studied
##   and befriended -- and keeps shifting as you play. It takes a name that fits.
##   RAPPORT grows with time together; with it the swarm helps your ki and tech: a little more qi, faster meridian focus, research and cleansing,
##   and stronger ki arts.
##   TIPS: at key moments (low life, a breakthrough ready, unspent points, the aspect faded, a commission to hand in, a garden to pick ...) it
##   says one short useful thing, in its own voice, never more than one every couple of minutes, and any can be turned off for good.
##   Ask it for advice any time (Swarm page). Offline game only. data/nanite_mind.json.

var data := {}
var awake := false
var char_name := ""
var tips_on := true
var rapport := 0.0
var traits := {}              # trait -> share 0..1
var last := {}                # rule id -> unix time last said
var told := 0
var _last_any := 0.0
var _acc := 0.0
var _slow := 0.0
var now_override := -1.0      # tests


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/nanite_mind.json")
	reset()


func reset() -> void:
	awake = false
	char_name = ""
	tips_on = true
	rapport = 0.0
	traits = {}
	last = {}
	told = 0
	_last_any = 0.0
	_acc = 0.0
	_slow = 0.0


func save_state() -> Dictionary:
	return {"awake": awake, "name": char_name, "tips_on": tips_on, "rapport": rapport, "traits": traits, "last": last, "told": told}


func load_state(d: Dictionary) -> void:
	reset()
	awake = bool(d.get("awake", false))
	char_name = str(d.get("name", ""))
	tips_on = bool(d.get("tips_on", true))
	rapport = clampf(float(d.get("rapport", 0.0)), 0.0, float(data.get("rapport_cap", 100)))
	var t = d.get("traits", {})
	if t is Dictionary:
		for k in t:
			if (data.get("traits", {}) as Dictionary).has(str(k)):
				traits[str(k)] = clampf(float(t[k]), 0.0, 1.0)
	var l = d.get("last", {})
	if l is Dictionary:
		for k in l:
			last[str(k)] = float(l[k])
	told = int(d.get("told", 0))
	if awake and char_name == "":
		char_name = _pick_name()


func _now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


func online() -> bool:
	return G.OnlineGen.is_online(str(G.current_level))


func in_town() -> bool:
	var tr = G.sys("travel")
	return tr != null and tr.is_town(str(G.current_level))


func fighting() -> bool:
	var p = G.get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return false
	for e in G.get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and is_instance_valid(e) and (e.global_position - p.global_position).length() < 14.0:
			return true
	return false


# ---- character ------------------------------------------------------------------------------------------------------------------

func _raw() -> Dictionary:
	var c: Dictionary = G.counters
	var cb = G.sys("craftbook")
	var made: float = float(cb.recipe_keys().size()) if cb != null else 0.0
	var ws = G.sys("stories")
	var stories := 0.0
	if ws != null:
		for n in ws.done:
			stories += float(ws.done[n])
	var asp = G.sys("aspect")
	return {
		"warrior": float(c.get("kills", 0.0)) + 10.0 * float(c.get("bosses", 0.0)) + 3.0 * float(c.get("elites", 0.0)) + 2.0 * float(c.get("parries", 0.0)),
		"maker": made * 3.0 + float(c.get("commissions", 0.0)) * 4.0 + float(c.get("garden_picks", 0.0)) + float(c.get("runes_set", 0.0)) * 2.0,
		"sitter": float(c.get("shrine_seconds", 0.0)) / 60.0 + float(c.get("cleansings", 0.0)) * 3.0 + (float(c.get("flow_breaths", 0.0)) / 10.0 if asp != null else 0.0),
		"wanderer": float(c.get("floors", 0.0)) + 3.0 * float(c.get("gates_passed", 0.0)) + float(c.get("tower_floors", 0.0)) + float(G.reach_depth()),
		"scholar": float(c.get("lessons", 0.0)) * 3.0 + float(c.get("experiments", 0.0)) * 2.0 + float(c.get("discoveries", 0.0)) * 3.0 + float(c.get("researched", 0.0)) * 3.0,
		"bonder": float(c.get("contracts_deepened", 0.0)) * 5.0 + float(c.get("errands", 0.0)) * 2.0 + float(c.get("settlement_help", 0.0)) * 2.0 + float(c.get("masters_taught", 0.0)) * 3.0 + stories * 3.0}


func read_play() -> void:
	## who the swarm thinks you are, from how you have played so far
	var raw := _raw()
	var tr_: Dictionary = data.get("traits", {})
	var score := {}
	var sum := 0.0
	for k in tr_:
		var v := float(raw.get(k, 0.0)) / float(tr_[k].get("scale", 50))
		v = v / (1.0 + v * 0.25) + 0.05      # a diminishing curve, so one road can't drown the rest entirely (and a fresh game has no strong lean)
		score[k] = v
		sum += v
	traits = {}
	for k in tr_:
		traits[k] = (float(score[k]) / sum) if sum > 0.0001 else (1.0 / float(tr_.size()))


func ranked() -> Array:
	## trait ids, strongest first
	var ks: Array = (data.get("traits", {}) as Dictionary).keys()
	ks.sort_custom(func(a, b): return float(traits.get(a, 0.0)) > float(traits.get(b, 0.0)) or (is_equal_approx(float(traits.get(a, 0.0)), float(traits.get(b, 0.0))) and str(a) < str(b)))
	return ks


func lead() -> String:
	var r := ranked()
	return str(r[0]) if r.size() > 0 else "scholar"


func voice() -> String:
	return str(data["traits"][lead()]["name"])


func summary() -> String:
	var r := ranked()
	if r.size() < 2:
		return ""
	return I18n.t("a %s first, a %s second") % [tr(str(data["traits"][r[0]]["name"])), tr(str(data["traits"][r[1]]["name"]))]


func _pick_name() -> String:
	var names: Array = (data.get("names", {}) as Dictionary).get(lead(), ["Echo"])
	return str(names[abs(hash(G.char_name + "|" + lead())) % names.size()])


func suit_element() -> String:
	return str(data["traits"][lead()].get("element", "fire"))


# ---- waking and rapport -----------------------------------------------------------------------------------------------------------

func can_wake() -> bool:
	return not awake and G.nanite_tier() >= int(data.get("awake_tier", 4)) and not online()


func wake() -> void:
	if awake:
		return
	read_play()
	awake = true
	char_name = _pick_name()
	rapport = 5.0
	G.log_event("swarm_wakes", {"lead": lead(), "name": char_name})
	G.message.emit(I18n.t("The swarm stirs. Something in it has been listening for a long time, and it knows how you move. \"%s,\" it says. \"Call me that, if you like.\" (Swarm page: your swarm's mind.)") % char_name)
	G.jingle("achievement")
	G.stats_changed.emit()


func rapport_frac() -> float:
	return rapport / maxf(1.0, float(data.get("rapport_cap", 100)))


func effects() -> Array:
	if not awake or online():
		return []
	var out := {}
	var s := rapport_frac()
	var gift: Dictionary = data.get("gift", {})
	for k in gift:
		out[k] = 1.0 + float(gift[k]) * s
	return [out]


# ---- tips ----------------------------------------------------------------------------------------------------------------------

func _rules() -> Array:
	## [id, urgent, text-args]; the ones that are true right now, most pressing first
	var out := []
	var hp_frac := float(G.hp) / maxf(1.0, float(G.max_hp()))
	var town := in_town()
	var asp = G.sys("aspect")
	if hp_frac < 0.3 and not town:
		out.append(["low_life" if G.count("healing_salve") > 0 else "low_life_bare", true, []])
	if G.at_threshold() and G.breakthrough_missing().is_empty():
		out.append(["breakthrough", false, []])
	if G.attr_points_free() > 0:
		out.append(["attr_points", false, []])
	if G.running_hot() and not town:
		out.append(["heat", true, []])
	if asp != null and asp.available():
		if float(G.counters.get("flow_breaths", 0.0)) == 0.0:
			out.append(["aspect_first", false, []])
		elif not asp.buff_on() and not town and not asp.flowing:
			out.append(["aspect_idle", false, []])
		var want := suit_element()
		if asp.focus != want and float(asp.att.get(asp.focus, 0.0)) < 30.0 and float(G.counters.get("flow_breaths", 0.0)) > 0.0:
			out.append(["aspect_suit", false, [tr(voice()), tr(str(asp.aspect_def(want).get("name", want)))]])
	if town:
		var bo = G.sys("boons")
		if bo != null:
			if str(bo.run["boon"]) == "":
				out.append(["blessing", false, []])
			if bo.shrine_ready():
				out.append(["shrine", false, []])
			var q: Dictionary = bo.quarry()
			if str(q["species"]) != "" and not bool(q["paid"]):
				out.append(["quarry", false, [tr(str(q["name"]))]])
		var ga = G.sys("garden")
		if ga != null:
			for i in ga.plots.size():
				if ga.state(i) == "ready":
					out.append(["garden", false, []])
					break
		var cm = G.sys("commissions")
		if cm != null:
			var deliverable := false
			for o in cm.active_orders():
				if cm.can_deliver(o):
					deliverable = true
			if deliverable:
				out.append(["commission_ready", false, []])
			elif cm.active_orders().is_empty() and cm.board(str(G.current_level)).size() > 0:
				out.append(["commission_board", false, []])
	var sk: String = G.weapon_skill()
	if sk != "" and sk != "unarmed":
		out.append(["build_skill", false, [G.skill_name(sk), G.skill_level(sk)]])
	if rapport < 60.0:
		out.append(["ki_link", false, []])
	return out


func _gap(id: String) -> float:
	return float((data.get("gaps", {}) as Dictionary).get(id, data.get("rule_gap", 1200)))


func _say(id: String, args: Array) -> String:
	var tip := tr(str((data["tips"] as Dictionary).get(id, "")))
	if args.size() > 0:
		tip = tip % args
	var ops: Array = (data["openers"] as Dictionary).get(lead(), [""])
	var op := tr(str(ops[(told + abs(hash(id))) % ops.size()]))
	return "%s: %s %s" % [char_name, op, tip]


func advice(ignore_gaps: bool = false) -> String:
	## the most pressing thing to say right now, or "" (and it is remembered, so it isn't said again at once)
	if not awake:
		return ""
	var now := _now()
	for r in _rules():
		var id := str(r[0])
		if not ignore_gaps and now - float(last.get(id, 0.0)) < _gap(id):
			continue
		last[id] = now
		_last_any = now
		told += 1
		return _say(id, r[2])
	return ""


func ask() -> String:
	## "ask for advice": always answers, even if the rule was said a minute ago
	if not awake:
		return ""
	var a := advice(true)
	if a == "":
		a = "%s: %s" % [char_name, tr("Nothing presses. Walk, fight, sit -- whichever you like. I'm here.")]
	return a


func tick(delta: float) -> void:
	if online():
		return
	_acc += delta
	if _acc < 6.0:
		return
	var step := _acc
	_acc = 0.0
	if not awake:
		if can_wake():
			wake()
		return
	_slow += step
	rapport = minf(float(data.get("rapport_cap", 100)), rapport + step / 60.0 / float(data.get("rapport_minutes", 5)))
	if _slow >= 60.0:
		_slow = 0.0
		read_play()
	if not tips_on:
		return
	var now := _now()
	var urgent_ok := now - _last_any >= float(data.get("urgent_gap", 45))
	var calm_ok := now - _last_any >= float(data.get("tip_gap", 150)) and not fighting()
	if not (urgent_ok or calm_ok):
		return
	for r in _rules():
		var id := str(r[0])
		if now - float(last.get(id, 0.0)) < _gap(id):
			continue
		if bool(r[1]) and urgent_ok or (not bool(r[1])) and calm_ok:
			last[id] = now
			_last_any = now
			told += 1
			G.message.emit(_say(id, r[2]))
			return
