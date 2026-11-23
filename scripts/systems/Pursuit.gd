extends "res://scripts/systems/GameSystem.gd"
## Pursuit (round 63): downtime that's worth something, and can't be gamed.
## Robert, 2026-10-05: "make sure the down time is actually useful and
## regulated so it's not abused. Down time shouldn't mean a time skip -- it
## should be what you do when the game is running but you are AFK, or while
## the game is off: the character can be moving towards goals."
##
##   a pursuit      what your character works at when you're not playing:
##                  meditate, train a skill, go out gathering, or work at the
##                  bench (Game.away_task) -- now with a GOAL: train Sword to
##                  12, bring back 25 herbs, sit until the next breakthrough.
##                  Reach it and they stop and rest, and it's in the report.
##   both ways      game closed: when you're back, the hours are worked through
##                  in quarter-hour steps and you read what happened, in order
##                  (a timeline, not a lump). Game open but you've stepped away
##                  (no input for a minute and a half, nothing hunting you):
##                  your character takes up the pursuit right there -- sits to
##                  meditate, or works at it -- and a chip says how it's going.
##                  Touch anything and you're back, with a line of what got done.
##   regulated      * a PURSUIT BANK: hours of pursuit you have in hand, up to
##                    12; it refills with real time (about 10 hours a day) and
##                    pursuing spends it -- open or closed, AFK or away. Past
##                    it, your character only rests (the nanites' trickle).
##                  * the longer one stretch goes, the less each hour gives
##                    (all of it for 2 hours, 3/4 to 6, then half)
##                  * the clock can't be gamed: time only counts forward from
##                    the latest moment the game has ever seen (a high-water
##                    mark); wind the clock back and nothing counts until real
##                    time catches up; wind it forward and you've only spent
##                    your bank early. Time while the game runs is counted on
##                    the engine's own steady clock, not the wall clock.
## Every number is in data/pursuit.json.

signal afk_changed(on: bool)

var cfg := {}
var bank := 6.0               # hours of pursuit in hand
var high_water := 0.0         # the latest unix time this game has seen
var stretch := 0.0            # hours into this stretch of pursuit
var carry := {}               # fractions carried between steps ("haul", "craft")
var report := []              # the last report's lines
var total := 0.0              # hours pursued, ever
var afk := false              # pursuing right now, in front of an idle screen
var afk_gain := {}            # what this AFK stretch has given (for the line when you're back)
var afk_secs := 0.0
var _idle := 0.0              # seconds since the last input (steady clock)
var _acc := 0.0               # seconds of AFK waiting to be worked
var _last_ms := 0


func setup(game) -> void:
	super.setup(game)
	cfg = G._load_json("res://data/pursuit.json", {})
	process_mode = Node.PROCESS_MODE_ALWAYS
	bank = _n("start_bank_h", 6.0)
	_last_ms = Time.get_ticks_msec()


func reset() -> void:
	bank = _n("start_bank_h", 6.0)
	high_water = Time.get_unix_time_from_system()
	stretch = 0.0
	carry = {}
	report = []
	total = 0.0
	_stop_afk(false)


func save_state() -> Dictionary:
	return {"bank": bank, "high_water": high_water, "stretch": stretch, "carry": carry, "total": total}


func load_state(d: Dictionary) -> void:
	bank = clampf(float(d.get("bank", _n("start_bank_h", 6.0))), 0.0, cap())
	high_water = float(d.get("high_water", 0.0))
	stretch = float(d.get("stretch", 0.0))
	carry = d.get("carry", {}) if d.get("carry", {}) is Dictionary else {}
	total = float(d.get("total", 0.0))


func _n(key: String, dflt: float) -> float:
	return float(cfg.get(key, dflt))


func cap() -> float:
	return _n("bank_max_h", 12.0)


func refill_rate() -> float:
	return _n("bank_refill_per_h", 0.42)


# ---- the goal ------------------------------------------------------------------------------

func goal_text(t: Dictionary = {}) -> String:
	var a: Dictionary = t if not t.is_empty() else G.away_task
	var g := int(a.get("goal", 0))
	match str(a.get("kind", "")):
		"meditate":
			return I18n.t("until your next breakthrough") if g > 0 else I18n.t("for as long as it takes")
		"train":
			return (I18n.t("to level %d") % g) if g > 0 else I18n.t("with no end in mind")
		"gather":
			return (I18n.t("until you've %d") % g) if g > 0 else I18n.t("for as long as it takes")
		"craft":
			return I18n.t("%d to make") % int(a.get("count", 0))
	return ""


func goal_done() -> bool:
	var a: Dictionary = G.away_task
	var g := int(a.get("goal", 0))
	match str(a.get("kind", "")):
		"meditate":
			return g > 0 and G.step_index() >= g
		"train":
			return g > 0 and G.skill_level(str(a.get("skill", ""))) >= g
		"gather":
			return g > 0 and int(a.get("got", 0)) >= g
		"craft":
			return int(a.get("count", 0)) <= 0
	return false


func set_goal(t: Dictionary) -> String:
	## Game.set_away_task with the goal pinned to now (a breakthrough goal is
	## "the step after the one you're on")
	var t2 := t.duplicate(true)
	if str(t2.get("kind", "")) == "meditate" and int(t2.get("goal", 0)) == 1:
		t2["goal"] = G.step_index() + 1
	if str(t2.get("kind", "")) == "gather":
		t2["got"] = 0
	stretch = 0.0
	return G.set_away_task(t2)


# ---- how much an hour gives --------------------------------------------------------------

func rate_at(h: float) -> float:
	## the share an hour gives, this far into a stretch
	for row in cfg.get("tiers", [[2, 1.0], [6, 0.75], [9999, 0.5]]):
		if h < float(row[0]):
			return float(row[1])
	return 0.5


func _effective(hours: float) -> float:
	## hours of pursuit, worth this many full hours (stretch moves on)
	if G.tester_endless():
		return hours                 # (no tiring: every hour counts in full)
	var eff := 0.0
	var left := hours
	while left > 0.0001:
		var step := minf(left, 0.25)
		eff += step * rate_at(stretch)
		stretch += step
		left -= step
	return eff


func _gain(eff: float, real_h: float, rng: RandomNumberGenerator, notes: Array, gain: Dictionary) -> void:
	## one slice of pursuit, worth `eff` full hours; facts into `gain`, moments into `notes`
	var a: Dictionary = G.away_task
	var kind := str(a.get("kind", ""))
	if goal_done():
		kind = ""                                    # the goal's met: rest
	# the nanites always refine (counted once, here, for open and closed alike)
	var mult: float = G.AFK_SHRINE_MULT if kind == "meditate" and not G.meditating else 1.0
	var base_q: float = maxf(G.AFK_QI_PER_HOUR, G.qi_to_next() * G.AWAY_QI_FRAC)
	var q: float = real_h * base_q * (1.0 if kind == "" else 0.0) + eff * base_q * mult * (0.0 if kind == "" else 1.0)
	if kind == "meditate" and G.meditating:
		q = 0.0                                      # (sitting already cultivates, live)
	var step0: int = G.step_index()
	if q > 0.0:
		G.add_qi(q)
		gain["qi"] = float(gain.get("qi", 0.0)) + q
	if G.step_index() > step0:
		notes.append(I18n.t("You broke through to %s.") % G.cultivation_label())
	match kind:
		"train":
			var sk := str(a.get("skill", "unarmed"))
			var lv0: int = G.skill_level(sk)
			var xp := eff * (10.0 * (lv0 + 1) + 15.0)
			G.add_skill_xp(sk, xp, "pursuit")
			gain["xp"] = float(gain.get("xp", 0.0)) + xp
			gain["skill"] = sk
			if G.skill_level(sk) > lv0:
				notes.append(I18n.t("%s reached level %d.") % [G.skill_name(sk), G.skill_level(sk)])
		"gather":
			var sk2 := str(a.get("skill", "herbalism"))
			var want: float = eff * (2.0 + G.skill_level(sk2) / 3.0) + float(carry.get("haul", 0.0))
			var n := int(want)
			carry["haul"] = want - n
			if n > 0:
				var haul: Dictionary = G._gather_haul(sk2, n, G.reach_depth(), rng)
				var got := 0
				for id in haul:
					G.add_item(str(id), int(haul[id]), false)
					var bag: Dictionary = gain.get("items", {})
					bag[str(id)] = int(bag.get(str(id), 0)) + int(haul[id])
					gain["items"] = bag
					got += int(haul[id])
				a["got"] = int(a.get("got", 0)) + got
			G.add_skill_xp(sk2, eff * 12.0, "pursuit")
		"craft":
			var r: Dictionary = G._recipe_for(str(a.get("recipe", "")))
			if r.is_empty():
				G.away_task = {}
				notes.append(I18n.t("You meant to craft, but never settled on what -- you rest instead."))
				return
			var per: float = 2.0 + G.skill_level(str(r.get("skill", "smithing"))) / 5.0
			var want2 := eff * per + float(carry.get("craft", 0.0))
			var tries := mini(int(want2), int(a.get("count", 0)))
			carry["craft"] = want2 - int(want2)
			for i in tries:
				G._pull_for(r)
				if not G.can_craft(r):
					notes.append(I18n.t("You ran out of materials for %s -- you rest instead.") % G.item_name(str(r["makes"])))
					a["count"] = 0
					break
				var res: Dictionary = G.craft_attempt(r, "balanced", rng.randf(), rng.randf())
				a["count"] = int(a.get("count", 0)) - 1
				if bool(res.get("success", false)):
					gain["made"] = int(gain.get("made", 0)) + 1
					gain["made_id"] = str(r["makes"])
				else:
					gain["spoiled"] = int(gain.get("spoiled", 0)) + 1
	if kind != "" and goal_done():
		notes.append(I18n.t("Goal reached (%s) -- you rest now.") % _short_task())


func _short_task() -> String:
	return G.away_task_text()


# ---- the bank -------------------------------------------------------------------------------

func _refill(real_h: float) -> void:
	bank = minf(cap(), bank + real_h * refill_rate())


func _spend(hours: float) -> float:
	## pursue up to `hours`; returns how many the bank allowed
	if G.tester_endless():
		total += hours
		return hours                 # (the test kit: the bank never runs dry)
	var got := minf(hours, bank)
	bank -= got
	total += got
	return got


func bank_text() -> String:
	return I18n.t("%s of pursuit in hand (refills about %d hours a day, up to %d)") % [G._dur(bank * 3600.0), int(round(refill_rate() * 24.0)), int(cap())]


# ---- game closed ----------------------------------------------------------------------------

func elapsed_since(saved_at: float, now: float = -1.0) -> Dictionary:
	## {hours, note}: the time that counts, by the high-water mark
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	var from := maxf(saved_at, high_water)
	if from <= 0.0:
		high_water = now
		return {"hours": 0.0, "note": ""}
	if now < from - _n("clock_slack_s", 300.0):
		return {"hours": 0.0, "note": "Your clock reads earlier than when you last played -- no away time counts until it catches up."}
	var hours := maxf(0.0, (now - from) / 3600.0)
	if hours >= 0.05:
		high_water = maxf(high_water, floorf(now / 60.0) * 60.0)
	return {"hours": hours, "note": ""}


func offline(saved_at: float, was_meditating: bool, now: float = -1.0, rng_seed: int = -1) -> Array:
	## Game.load_game: the time away, worked through in order -> report lines
	var e := elapsed_since(saved_at, now)
	var hours: float = float(e["hours"])
	var lines := []
	if str(e["note"]) != "":
		lines.append(str(e["note"]))
		return lines
	if hours < 0.05:
		return lines
	var sat := was_meditating and str(G.away_task.get("kind", "")) == ""
	if sat:
		G.away_task = {"kind": "meditate"}         # (left sitting: you sat the time away -- just this once)
	G.meditating = false               # (sitting "live" doesn't apply to time away; Game.load_game clears it after anyway)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system()) if rng_seed < 0 else rng_seed
	var start_bank := minf(cap(), bank + hours * refill_rate())
	bank = start_bank
	stretch = 0.0
	var pursued := 0.0
	var gain := {}
	var timeline := []
	var t := 0.0
	var step := _n("step_min", 15.0) / 60.0
	var lim := minf(hours, 336.0 if G.tester_endless() else _n("count_max_h", 48.0))
	var rest_said := false
	while t < lim - 0.0001:
		var dt := minf(step, lim - t)
		var notes := []
		var p: float = _spend(dt) if str(G.away_task.get("kind", "")) != "" and not goal_done() else 0.0
		if p > 0.0:
			_gain(_effective(p), 0.0, rng, notes, gain)
			pursued += p
		var rest := dt - p
		if rest > 0.0:
			var kind_was: Dictionary = G.away_task
			var saved: Dictionary = kind_was.duplicate(true)
			G.away_task = {}
			_gain(0.0, rest, rng, notes, gain)            # resting: the nanites' trickle
			G.away_task = saved
			if p == 0.0 and not rest_said and str(saved.get("kind", "")) != "" and not goal_done():
				notes.append(I18n.t("Your pursuit bank ran dry -- you rest the remaining hours."))
				rest_said = true
		for n in notes:
			timeline.append([t + dt, n])
		t += dt
	# a moment from the pursuit itself, in Dev's words (data/drafts/pursuit_moments.json)
	if pursued >= 1.0:
		var m := moment(str(G.away_task.get("kind", "")), rng)
		if m != "":
			timeline.append([pursued * 0.5, m])
	# the report: what happened, in order, then the sum
	lines.append(I18n.t("Away %s. You pursued %s for %s%s.") % [G._dur(hours * 3600.0), G.away_task_text() if pursued > 0.0 else I18n.t("nothing in particular"),
		G._dur(pursued * 3600.0), (" -- " + goal_text()) if pursued > 0.0 and goal_text() != "" else ""])
	# the turning points always show (the goal met, the bank run dry); then the
	# earliest of the rest, up to 8 lines -- all in order of when they happened
	var keep := []
	for row in timeline:
		if str(row[1]).begins_with("Goal reached") or str(row[1]).contains("bank ran dry") or str(row[1]).contains("ran out of"):
			keep.append(row)
	for row in timeline:
		if keep.size() >= 8:
			break
		if not keep.has(row):
			keep.append(row)
	keep.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for row in keep:
		lines.append("%s  %s" % [_clock(float(row[0])), str(row[1])])
	if timeline.size() > keep.size():
		lines.append(I18n.t("... and %d more moments.") % (timeline.size() - keep.size()))
	lines.append_array(_sum_lines(gain))
	lines.append(I18n.t("Pursuit bank: %s.") % G._dur(bank * 3600.0))
	report = lines.duplicate()
	if sat:
		G.away_task = {}
	G.log_event("pursuit_offline", {"hours": hours, "pursued": pursued, "bank": bank})
	return lines


func _clock(h: float) -> String:
	return "%dh%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func _sum_lines(gain: Dictionary) -> Array:
	var out := []
	if float(gain.get("qi", 0.0)) >= 1.0:
		out.append("+%d qi." % int(gain["qi"]))
	if float(gain.get("xp", 0.0)) >= 1.0:
		out.append(I18n.t("+%d %s practice.") % [int(gain["xp"]), G.skill_name(str(gain.get("skill", "")))])
	var items: Dictionary = gain.get("items", {})
	if not items.is_empty():
		var parts := []
		for id in items:
			parts.append("%d %s" % [int(items[id]), G.item_name(str(id))])
		out.append(I18n.t("You brought back ") + ", ".join(parts) + ".")
	if int(gain.get("made", 0)) + int(gain.get("spoiled", 0)) > 0:
		out.append(I18n.t("At the bench: %d %s made, %d spoiled.") % [int(gain.get("made", 0)), G.item_name(str(gain.get("made_id", ""))), int(gain.get("spoiled", 0))])
	return out


# ---- game open, you've stepped away -----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch \
			or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0) \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		poke()


func poke() -> void:
	## any input: you're back
	_idle = 0.0
	if afk:
		_stop_afk(true)


func can_afk() -> bool:
	if not bool(G.downtime_live):
		return false
	if str(G.away_task.get("kind", "")) == "" or goal_done() or bank <= 0.0:
		return false
	if G.arena_active() or str(G.current_level).contains(":"):
		return false
	var tree: SceneTree = G.get_tree()
	var p = tree.get_first_node_in_group("player") if tree else null
	if p == null or bool(p.get("dead")):
		return false
	if Time.get_unix_time_from_system() - G.last_hurt_at < 20.0:
		return false
	for e in tree.get_nodes_in_group("enemy"):
		if e is Node3D and e.is_inside_tree() and e.get("_dead") != true and e.get("_dummy") != true and (e as Node3D).global_position.distance_to(p.global_position) < _n("afk_clear_m", 18.0):
			return false
	return true


func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	var dt := clampf((now_ms - _last_ms) / 1000.0, 0.0, 1.0)      # the engine's steady clock; never more than a second a frame
	_last_ms = now_ms
	_refill(dt / 3600.0)
	high_water = maxf(high_water, floorf(Time.get_unix_time_from_system() / 60.0) * 60.0)     # (to the minute)
	_idle += dt
	if not afk:
		if _idle >= _n("idle_after_s", 90.0) and can_afk():
			_start_afk()
		return
	if not can_afk():
		_stop_afk(true)
		return
	_acc += dt
	afk_secs += dt
	if _acc >= _n("afk_step_s", 10.0):
		var h := _acc / 3600.0
		_acc = 0.0
		if str(G.away_task.get("kind", "")) == "meditate" and G.meditating:
			return                      # (sitting already cultivates, live: no bank spent for nothing)
		var p := _spend(h)
		var notes := []
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		if p > 0.0:
			_gain(_effective(p), 0.0, rng, notes, afk_gain)
		for n in notes:
			G.message.emit(n)
		G.stats_changed.emit()


func _start_afk() -> void:
	afk = true
	afk_gain = {}
	afk_secs = 0.0
	_acc = 0.0
	stretch = 0.0
	var pl = G.get_tree().get_first_node_in_group("player")
	if str(G.away_task.get("kind", "")) == "meditate" and pl and pl.has_method("start_meditating") and not G.meditating:
		pl.start_meditating(false)
	G.log_event("pursuit_afk", {"kind": str(G.away_task.get("kind", ""))})
	afk_changed.emit(true)


func _stop_afk(say: bool) -> void:
	if not afk:
		return
	afk = false
	var sums := _sum_lines(afk_gain)
	if say and afk_secs >= 20.0 and not sums.is_empty():
		G.message.emit(I18n.t("While you stood idle (%s): %s") % [G._dur(afk_secs), " ".join(sums)])
	afk_gain = {}
	afk_changed.emit(false)


func chip_text() -> String:
	## the HUD's line while you're away from the keys
	if not afk:
		return ""
	var eta := eta_text()
	var goal_part := goal_text()
	if not eta.is_empty():
		goal_part += " (%s)" % eta
	return I18n.t("Pursuing: %s %s  ·  %s  ·  bank %s") % [G.away_task_text(), goal_part, G._dur(afk_secs), G._dur(bank * 3600.0)]


func eta_text() -> String:
	## round 75 (Dev's w002, finished by hand): about how many hours of pursuit a train goal still needs.
	## Same rate as _gain: an effective hour gives 10 * (level + 1) + 15 xp; a skill level L starts at 10 * L * L xp.
	var a: Dictionary = G.away_task
	if str(a.get("kind", "")) != "train":
		return ""
	var g := int(a.get("goal", 0))
	if g <= 0:
		return ""
	var sk := str(a.get("skill", "unarmed"))
	if G.skill_level(sk) >= g:
		return ""
	var xp: float = float(G.skills.get(sk, 0.0))
	var hours := 0.0
	var lv: int = G.skill_level(sk)
	while lv < g:
		var need: float = maxf(0.0, 10.0 * float((lv + 1) * (lv + 1)) - xp)
		hours += need / (10.0 * float(lv + 1) + 15.0)
		xp = 10.0 * float((lv + 1) * (lv + 1))
		lv += 1
	return I18n.t("about %dh to go") % maxi(1, int(ceil(hours)))


func moment(kind: String, rng: RandomNumberGenerator) -> String:
	## a line about the pursuit itself -- Dev's (writing room brief
	## "pursuit_moments", ids m_/t_/g_/c_ for meditate/train/gather/craft)
	var pre: String = {"meditate": "m_", "train": "t_", "gather": "g_", "craft": "c_"}.get(kind, "")
	if pre == "":
		return ""
	var opts := []
	var dev: Dictionary = G.draft_texts("pursuit_moments")
	for k in dev:
		if str(k).begins_with(pre) and str(dev[k]).strip_edges() != "":
			opts.append(str(dev[k]).strip_edges())
	if opts.is_empty():
		opts = (cfg.get("moments", {}) as Dictionary).get(kind, [])
	return str(opts[rng.randi() % opts.size()]) if not opts.is_empty() else ""
