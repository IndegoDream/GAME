extends RefCounted
## Round 126: "one more run". Three things that make the next fight pull harder than the last (Robert: "do 3, 2, 1"):
##   3  combat feel   -- kill chains (a run of kills keeps a clock; milestones heal, give qi, pop a word), the slow breath on a
##                       master's fall or a phase change, a camera punch.
##   2  the loot hit   -- a luck meter: every foe slain without a Superior-or-better find tilts the next drop upward, a hint
##                       when it's near, and a guaranteed Superior+ at the top; it resets on the find.
##   1  the daily pull -- a login streak with a reward that grows, and three daily challenges (slay N, chain, find gear), a
##                       bonus for all three; the next one shows in the NEXT line.
## All of it lives in Game.counters (saved with the slot). Nothing here touches the shared (online) world.

const FX := preload("res://scripts/fx/FX.gd")
const CHAIN_MS := 7000
const MILESTONES := [3, 5, 8, 12, 16, 20, 30]
const PITY_HINT := 18
const PITY_FULL := 30

static var chain := 0
static var chain_at := 0
static var _fresh := true


static func _player() -> Node3D:
	var t = Game.get_tree()
	return t.get_first_node_in_group("player") if t else null


static func _c(key: String) -> float:
	return float(Game.counters.get(key, 0.0))


static func _put(key: String, v: float) -> void:
	Game.counters[key] = v


static func today() -> int:
	return int(floor(Time.get_unix_time_from_system() / 86400.0))


# ---- 3: combat feel ---------------------------------------------------------------------------------------------------

static func on_kill(etype: String) -> void:
	var st: Dictionary = Game.enemies.get(etype, {})
	if bool(st.get("passive", false)) or Game.OnlineGen.is_online(str(Game.current_level)):
		return
	var now := Time.get_ticks_msec()
	if now - chain_at > CHAIN_MS:
		chain = 0
	chain += 1
	chain_at = now
	var boss := bool(st.get("boss", false))
	_pity_tick(1)
	_daily_progress("slay", 1)
	_daily_progress("chain", chain, true)
	var pl := _player()
	if chain in MILESTONES and pl != null and FX.on():
		var heal := int(round(Game.max_hp() * (0.03 + 0.01 * MILESTONES.find(chain))))
		Game.heal(heal)
		Game.add_qi(Game.kill_qi_at(Game.depth) * 0.3 * float(chain) / 3.0, "a chain of %d" % chain)
		FX.word(pl.global_position + Vector3(0, 2.8, 0), "CHAIN  x%d" % chain, Color(1.0, 0.78, 0.3), 50)
		FX.ring(pl.global_position, Color(1.0, 0.8, 0.35), 3.0, 0.45)
		Game.message.emit(I18n.t("Chain x%d -- you catch your breath (+%d HP) and the qi runs hot.") % [chain, heal])
		Game.sfx("bell", 0.5)
	mastery(etype)
	gauntlet_leech()
	watch_power()
	if boss:
		moment(0.22, 0.5, 0.35, "FALLEN")
		if not Game.arena_active():
			teaser(etype)


static func moment(scale: float, secs: float, shake: float, word: String = "") -> void:
	## the world slows a breath, the camera punches, a word hangs
	Game.slow_mo(scale, secs)
	var pl := _player()
	if pl != null:
		if pl.has_method("_shake"):
			pl._shake(shake)
		if word != "" and FX.on():
			FX.word(pl.global_position + Vector3(0, 3.2, 0), word, Color(1.0, 0.5, 0.35), 58)


static func chain_now() -> int:
	return chain if Time.get_ticks_msec() - chain_at <= CHAIN_MS else 0


# ---- 2: the loot hit -----------------------------------------------------------------------------------------------------

static func _pity_tick(n: int) -> void:
	var before := _c("hook_pity")
	_put("hook_pity", before + n)
	if before < PITY_HINT and before + n >= PITY_HINT:
		Game.message.emit("Fortune stirs... something fine is close.")


static func pity() -> int:
	return int(_c("hook_pity"))


static func pity_boost() -> int:
	## extra odds for the next piece of gear: one step up at 10 foes without a find, two at 20, the top at the full meter
	var p := pity()
	if p >= PITY_FULL:
		return 4
	return 2 if p >= 20 else (1 if p >= 10 else 0)


static func found(quality: int) -> void:
	## a Superior (3) or Masterwork (4) find: the meter starts over
	if quality >= 3:
		_put("hook_pity", 0.0)
	_daily_progress("gear", 1)


# ---- 1: the daily pull ---------------------------------------------------------------------------------------------------

static func _challenges() -> Array:
	var d := Game.reach_depth()
	return [
		{"id": "slay", "text": "Slay %d foes" % clampi(10 + 2 * d, 10, 40), "need": clampi(10 + 2 * d, 10, 40), "gold": 30 + 12 * d},
		{"id": "chain", "text": "Reach a chain of 6", "need": 6, "gold": 40 + 15 * d},
		{"id": "gear", "text": "Find 2 pieces of gear", "need": 2, "gold": 35 + 14 * d},
	]


static func _day_reset() -> void:
	if int(_c("hook_day")) != today():
		_put("hook_day", float(today()))
		for k in ["slay", "chain", "gear"]:
			_put("hook_p_" + k, 0.0)
			_put("hook_done_" + k, 0.0)
		_put("hook_all", 0.0)


static func _daily_progress(id: String, n: float, as_max: bool = false) -> void:
	_day_reset()
	if _c("hook_done_" + id) > 0.0:
		return
	var key := "hook_p_" + id
	_put(key, maxf(_c(key), n) if as_max else _c(key) + n)
	for ch in _challenges():
		if ch["id"] == id and _c(key) >= float(ch["need"]):
			_put("hook_done_" + id, 1.0)
			Game.add_item("gold", int(ch["gold"]), false)
			Game.banner.emit.call_deferred("DAILY DONE", Color(1.0, 0.85, 0.4))
			Game.message.emit(I18n.t("Daily done: %s  (+%d gold).") % [ch["text"], int(ch["gold"])])
			if _c("hook_done_slay") > 0.0 and _c("hook_done_chain") > 0.0 and _c("hook_done_gear") > 0.0 and _c("hook_all") < 1.0:
				_put("hook_all", 1.0)
				Game.message.emit("All three dailies done -- a prize waits in your pack.")
				Game.drop_gear(maxi(Game.depth, 1), 3)
			Game.stats_changed.emit()


static func daily_login() -> void:
	## once a day: the streak grows (or starts again) and pays
	var t := today()
	var last := int(_c("hook_login"))
	if last == t:
		return
	if last > t:
		return                                       # the clock went backwards: nothing new today
	var played := Game.playtime - _c("hook_login_pt")
	if last > 0 and played < 60.0:
		return                                       # a new day on the clock isn't a new day played: a minute of real play first
	_put("hook_login_pt", Game.playtime)
	var streak := int(_c("hook_streak"))
	streak = streak + 1 if last == t - 1 else 1
	_put("hook_login", float(t))
	_put("hook_streak", float(streak))
	_put("hook_best_streak", maxf(_c("hook_best_streak"), float(streak)))
	if Game.sys("pull") != null:
		Game.sys("pull").award_streak(streak)            # round 152: a name for coming back
	_day_reset()
	var gold := mini(40 * mini(streak, 10), 40 + 8 * int(played / 60.0))      # (never more than the time played can account for)
	Game.add_item("gold", gold, false)
	var extra := ""
	if played < 300.0 and last > 0:
		pass                                         # (a quick look in: the gold only; the gear and pills wait for a real sitting)
	elif streak % 14 == 0:
		Game.add_item("breakthrough_pill", 1, false)
		Game.drop_gear(maxi(Game.depth, 1), 3)
		extra = " A breakthrough pill and a fine piece of gear."
	elif streak % 7 == 0:
		Game.drop_gear(maxi(Game.depth, 1), 2)
		extra = " A fine piece of gear."
	elif streak % 3 == 0:
		Game.add_item("breakthrough_pill", 1, false)
		extra = " A breakthrough pill."
	var next := 3 - (streak % 3) if streak % 3 != 0 else 3
	Game.banner.emit.call_deferred("DAY %d" % streak, Color(1.0, 0.8, 0.4))
	Game.message.emit.call_deferred("Day %d of your streak: +%d gold.%s Come back tomorrow%s." % [streak, gold, extra, (I18n.t(" -- a pill waits at day %d") % (streak + next)) if streak % 3 != 0 else ""])
	Game.stats_changed.emit()


static func next_line() -> String:
	## the unfinished daily that is closest to done, for the NEXT list
	_day_reset()
	var best := ""
	var bp := -1.0
	for ch in _challenges():
		if _c("hook_done_" + str(ch["id"])) > 0.0:
			continue
		var p := _c("hook_p_" + str(ch["id"])) / float(ch["need"])
		if p > bp:
			bp = p
			best = I18n.t("Daily: %s (%d/%d)") % [ch["text"], int(_c("hook_p_" + str(ch["id"]))), int(ch["need"])]
	return best


static func describe() -> String:
	_day_reset()
	var lines := ["Streak: %d day(s)  (best %d)" % [int(_c("hook_streak")), int(_c("hook_best_streak"))]]
	for ch in _challenges():
		lines.append("%s %s (%d/%d)" % ["[done]" if _c("hook_done_" + str(ch["id"])) > 0.0 else I18n.t("Daily:"), ch["text"], int(_c("hook_p_" + str(ch["id"]))), int(ch["need"])])
	lines.append(I18n.t("Luck: %d / %d foes since your last fine find") % [mini(pity(), PITY_FULL), PITY_FULL])
	lines.append(I18n.t("Foes slain: %d    Kinds you have mastered: %d") % [int(_c("hook_kills")), bane_count()])
	lines.append(I18n.t("Ember Gauntlet: best %d of %d waves, %d embers in hand") % [int(_c("gauntlet_best")), WAVES, int(_c("embers"))])
	var sn := season()
	if not sn.is_empty():
		lines.append(I18n.t("%s is on: luck runs high and embers pay double.") % sn["name"])
	return "\n".join(PackedStringArray(lines))


# ---- round 126b: options 4 - 8 ("do it all") ------------------------------------------------------------------------
##   4  power you can see  -- "POWER +14%" when gear or growth lifts you, and FOUND lines say what a piece is worth to you
##   5  mastery            -- kill totals earn titles, each kind of foe has a bane tier (50/150/400) that pays out
##   6  the Ember Gauntlet -- a roguelite run in the ring: waves, a boon between them, a rival at the end, embers to spend
##   7  teasers + rivals   -- a fallen boss hints at what is next; the rival you've met the most waits at the Gauntlet's end
##   8  welcome back       -- a chest after time away; seasonal nights that tilt luck and double embers

const SEASONS := [
	{"name": "Hollow Nights", "from": [10, 24], "to": [11, 2], "color": [0.7, 0.45, 1.0]},
	{"name": "Lantern Festival", "from": [12, 20], "to": [1, 2], "color": [1.0, 0.75, 0.35]},
	{"name": "Spring Thaw", "from": [3, 18], "to": [3, 28], "color": [0.5, 1.0, 0.7]},
	{"name": "Harvest Moon", "from": [9, 15], "to": [9, 25], "color": [1.0, 0.85, 0.4]},
]
const TOTAL_TITLES := {100: "Hundredfold", 500: "Reaper of Five Hundred", 1000: "The Thousand-Strong", 5000: "Death Walks Beside Them"}
const BANE_TIERS := [50, 150, 400]
const WAVES := 10
const BOONS := {
	"fury": ["Fury", "+20% damage for the rest of the run"],
	"bulwark": ["Bulwark", "+25% max health, and you are healed"],
	"leech": ["Bloodthirst", "heal 5% of your health on every kill"],
	"second": ["Second Wind", "if you fall, rise once at full health"],
	"windfall": ["Windfall", "+50% embers when the run ends"],
}
const BLESS := {"might": ["Might", "+3% damage per rank"], "vigor": ["Vigor", "+3% max health per rank"]}


static func _md(m: int, d: int) -> int:
	return m * 100 + d


static func season(now: Dictionary = {}) -> Dictionary:
	var t: Dictionary = now if not now.is_empty() else Time.get_date_dict_from_system()
	var cur := _md(int(t["month"]), int(t["day"]))
	for s in SEASONS:
		var a := _md(int(s["from"][0]), int(s["from"][1]))
		var b := _md(int(s["to"][0]), int(s["to"][1]))
		if (a <= b and cur >= a and cur <= b) or (a > b and (cur >= a or cur <= b)):
			return s
	return {}


# 4 -- power -----------------------------------------------------------------------------------------------------------

static func power(key: String) -> float:
	## the multiplier Game.max_hp() / weapon_damage() ask for: Ember blessings, and the boons of a run in progress
	var m := 1.0
	var a: Dictionary = Game.arena
	if not a.is_empty() and str(a.get("event", "")) == "gauntlet":
		var b: Dictionary = a.get("boons", {})
		if key == "dmg":
			m *= 1.0 + 0.2 * float(b.get("fury", 0))
		elif key == "hp":
			m *= 1.0 + 0.25 * float(b.get("bulwark", 0))
	m *= 1.0 + 0.03 * _c("hook_bless_" + ("might" if key == "dmg" else "vigor"))
	return m


static func watch_power() -> void:
	if Game.arena_active():
		return
	var p: float = float(Game.max_hp()) * float(Game.damage())
	var last := _c("hook_power")
	if last <= 0.0 or p < last * 0.8:
		_put("hook_power", p)
		return
	if p >= last * 1.10:
		var pct := int(round((p / last - 1.0) * 100.0))
		_put("hook_power", p)
		Game.banner.emit("POWER +%d%%" % pct, Color(1.0, 0.85, 0.4))
		var pl := _player()
		if pl != null and FX.on():
			FX.ring(pl.global_position, Color(1.0, 0.85, 0.4), 3.2, 0.5)
			FX.word(pl.global_position + Vector3(0, 2.8, 0), "POWER +%d%%" % pct, Color(1.0, 0.85, 0.4), 52)


static func compare(id: String) -> String:
	## what a found piece is worth next to what you wear: " (+12 damage)" / " (-3 health)" / ""
	if id == "" or not Game.has_item_def(id):
		return ""
	var d: Dictionary = Game.item_def(id)
	if d.has("damage") and int(d.get("damage", 0)) > 0:
		var cur: int = Game.weapon_damage(Game.weapon)
		var dd: int = Game.weapon_damage(id) - cur
		return I18n.t(" (%s%d damage)") % ["+" if dd >= 0 else "", dd]
	if d.has("hp") and int(d.get("hp", 0)) != 0:
		var fam: String = Game.gear_family(id)
		var worn := 0
		for sl in Game.equipment:
			var e := str(Game.equipment[sl])
			if e != "" and Game.has_item_def(e) and Game.gear_family(e) == fam:
				worn = int(Game.item_def(e).get("hp", 0))
		var hd := int(d.get("hp", 0)) - worn
		return I18n.t(" (%s%d health)") % ["+" if hd >= 0 else "", hd]
	return ""


# 5 -- mastery ---------------------------------------------------------------------------------------------------------

static func mastery(etype: String) -> void:
	var total := _c("hook_kills") + 1.0
	_put("hook_kills", total)
	for k in TOTAL_TITLES:
		if int(total) == int(k) and not (TOTAL_TITLES[k] in Game.titles):
			Game.titles.append(TOTAL_TITLES[k])
			Game.banner.emit.call_deferred("TITLE: %s" % TOTAL_TITLES[k], Color(1.0, 0.8, 0.4))
			Game.message.emit(I18n.t("%d foes fallen to you. A title is yours: %s.") % [int(k), TOTAL_TITLES[k]])
	var key := "hook_k_" + etype
	var n := _c(key) + 1.0
	_put(key, n)
	var tier := BANE_TIERS.find(int(n))
	if tier >= 0:
		var nm := str(Game.enemies.get(etype, {}).get("name", etype.replace("_", " ")))
		var gold := 60 * (tier + 1)
		Game.add_item("gold", gold, false)
		Game.add_qi(Game.kill_qi_at(Game.depth) * 6.0 * float(tier + 1), "mastery of %s" % nm)
		if tier == 2 and not ((I18n.t("Bane of ") + nm) in Game.titles):
			Game.titles.append(I18n.t("Bane of ") + nm)
		Game.banner.emit.call_deferred("%s mastery %s" % [nm, ["I", "II", "III"][tier]], Color(0.9, 0.75, 0.45))
		Game.message.emit(I18n.t("You know the %s now (%d slain): +%d gold and a surge of insight.") % [nm, int(n), gold])


static func bane_count() -> int:
	var n := 0
	for k in Game.counters:
		if str(k).begins_with("hook_k_") and float(Game.counters[k]) >= float(BANE_TIERS[0]):
			n += 1
	return n


# 7 -- teasers ---------------------------------------------------------------------------------------------------------

const TEASERS := [
	"Its death rattle carries a name you don't know. Something deeper heard it.",
	"A sigil on the corpse points down. The floor below is watching.",
	"The silence after is wrong -- like something much larger drew a breath.",
	"You find a scrap of a map. The next room on it has no name, only a mark.",
	"The walls are humming. Whatever sleeps below has noticed you.",
]


static func teaser(etype: String) -> void:
	var line: String = TEASERS[(Game.depth + etype.length()) % TEASERS.size()]
	Game.message.emit.call_deferred("%s (Floor %d lies beyond.)" % [line, Game.depth + 1])


# 8 -- welcome back + season ---------------------------------------------------------------------------------------------

static func welcome_back() -> void:
	var now := Time.get_unix_time_from_system()
	var last := _c("hook_seen")
	if now < last:
		return                                       # the clock went backwards: keep the old mark, pay nothing
	_put("hook_seen", now)
	if last <= 0.0:
		return
	var sat := Game.playtime - _c("hook_chest_pt")
	if sat < 600.0 and _c("hook_chest_pt") > 0.0:
		return                                       # one chest per ten minutes actually played
	var hours := (now - last) / 3600.0
	if hours < 4.0:
		return
	_put("hook_chest_pt", Game.playtime)
	var h := minf(hours, 24.0)
	var gold := int(round(h * 12.0 * (1.0 + 0.15 * float(Game.reach_depth()))))
	Game.add_item("gold", gold, false)
	var extra := ""
	if hours >= 12.0:
		Game.drop_gear(maxi(Game.reach_depth(), 1), 1)
		extra = " and a find from the rack"
	Game.banner.emit.call_deferred("WELCOME BACK", Color(0.6, 0.9, 1.0))
	Game.message.emit.call_deferred("While you were away (%d h) a chest gathered: %d gold%s." % [int(hours), gold, extra])


static func season_notice() -> void:
	var s := season()
	if s.is_empty():
		return
	var key := "hook_season_" + str(s["name"]).replace(" ", "_")
	if _c(key) == float(Time.get_date_dict_from_system()["year"]):
		return
	_put(key, float(Time.get_date_dict_from_system()["year"]))
	var c: Array = s["color"]
	Game.banner.emit.call_deferred(str(s["name"]).to_upper(), Color(c[0], c[1], c[2]))
	Game.message.emit.call_deferred("%s: luck runs high and the Gauntlet pays double embers until it passes." % s["name"])


# 6 -- the Ember Gauntlet -----------------------------------------------------------------------------------------------

static func embers() -> int:
	return int(_c("embers"))


static func bless_rank(id: String) -> int:
	return int(_c("hook_bless_" + id))


static func bless_cost(id: String) -> int:
	return 25 * (bless_rank(id) + 1)


static func bless_buy(id: String) -> bool:
	if bless_rank(id) >= 10 or embers() < bless_cost(id):
		return false
	_put("embers", _c("embers") - float(bless_cost(id)))
	_put("hook_bless_" + id, _c("hook_bless_" + id) + 1.0)
	Game.hp = mini(Game.hp, Game.max_hp())
	Game.stats_changed.emit()
	return true


static func gauntlet_build(depth: int, rival_pick: int = -1) -> Dictionary:
	var rounds := []
	var names := []
	var defs := {}
	var rv: Dictionary = {}
	var best := -1
	for r in Game.Arena.RIVALS:
		var met := int(Game.rivals.get(r["name"], {}).get("met", 0))
		if met > best:
			best = met
			rv = r
	for i in WAVES:
		var pool: Array = Game.floor_foes(depth + int(i / 3.0))
		var a: String = pool[0] if pool.size() > 0 else "goblin"
		var b: String = pool[pool.size() - 1] if pool.size() > 0 else "goblin"
		var c := mini(2 + int(i / 2.0), 5)
		var wave := [{"id": a, "count": c}]
		if i >= 2:
			wave.append({"id": b, "count": maxi(1, int(c / 2.0))})
		if i == WAVES - 1 and not rv.is_empty():
			var eid := "rival_" + str(rv["name"]).to_lower().replace(" ", "_")
			defs[eid] = Game.Arena.rival_def(rv, depth + 1, maxi(best, 0))
			wave = [{"id": eid, "count": 1}, {"id": a, "count": 2}]
			names.append(I18n.t("The Rival: %s") % rv["name"])
		else:
			names.append(I18n.t("Wave %d") % (i + 1))
		rounds.append(wave)
	return {"event": "gauntlet", "host": "village", "host_name": "the Ember Gauntlet", "depth": depth, "tier": depth,
		"title": "The Ember Gauntlet", "round_names": names, "rounds": rounds, "defs": defs, "boons": {},
		"rival": str(rv.get("name", ""))}


static func gauntlet_start() -> void:
	Game._start_arena(gauntlet_build(maxi(Game.reach_depth(), 1)))
	Game.message.emit("THE EMBER GAUNTLET: %d waves, a boon between each, and a rival at the end. Fall and you keep your embers." % WAVES)


static func _hud() -> Node:
	var t = Game.get_tree()
	return t.get_first_node_in_group("hud") if t else null


static func gauntlet_take(id: String) -> void:
	var b: Dictionary = Game.arena.get("boons", {})
	b[id] = int(b.get(id, 0)) + 1
	Game.arena["boons"] = b
	if id == "bulwark":
		Game.hp = Game.max_hp()
	Game.stats_changed.emit()
	Game.message.emit(I18n.t("Boon: %s -- %s.") % [BOONS[id][0], BOONS[id][1]])


static func gauntlet_between() -> void:
	## a wave is down and another waits: offer three boons (the HUD's dialog), then go on
	var ids: Array = BOONS.keys()
	ids.shuffle()
	var offer: Array = ids.slice(0, 3)
	var got: Dictionary = Game.arena.get("boons", {})
	var wave := int(Game.arena.get("stage", 1))
	var hud := _hud()
	if hud == null or not hud.has_method("open_dialog"):
		gauntlet_take(offer[0])
		Game.arena_next()
		return
	var opts := []
	for id in offer:
		var bid: String = id
		opts.append(["%s  --  %s%s" % [BOONS[bid][0], BOONS[bid][1], (I18n.t("  (have %d)") % int(got[bid])) if got.has(bid) else ""],
			func():
				hud.close_dialog()
				gauntlet_take(bid)
				Game.arena_next()])
	hud.open_dialog("Wave %d cleared" % wave, "Pick a boon. They last until the run ends.\nEmbers this run: %d" % int(Game.arena.get("embers", 0)), opts)


static func gauntlet_wave_cleared() -> void:
	var depth := int(Game.arena.get("depth", 1))
	Game.arena["embers"] = int(Game.arena.get("embers", 0)) + 2 + depth


static func gauntlet_revive() -> bool:
	if str(Game.arena.get("event", "")) != "gauntlet":
		return false
	var b: Dictionary = Game.arena.get("boons", {})
	if int(b.get("second", 0)) <= 0 or bool(Game.arena.get("second_used", false)):
		return false
	Game.arena["second_used"] = true
	Game.hp = Game.max_hp()
	Game.message.emit("SECOND WIND -- you rise.")
	Game.go_to(Game.Arena.make_id(str(Game.arena["host"]), "gauntlet", int(Game.arena.get("stage", 0))), "P")
	return true


static func gauntlet_leech() -> void:
	if str(Game.arena.get("event", "")) != "gauntlet":
		return
	var n := int(Game.arena.get("boons", {}).get("leech", 0))
	if n > 0:
		Game.heal(int(round(Game.max_hp() * 0.05 * float(n))))


static func gauntlet_end(won: bool) -> String:
	var depth := int(Game.arena.get("depth", 1))
	var cleared := int(Game.arena.get("stage", 0))
	var boons: Dictionary = Game.arena.get("boons", {})
	var mult := 1.0 + (0.5 if int(boons.get("windfall", 0)) > 0 else 0.0)
	if not season().is_empty():
		mult *= 2.0
	var e := int(round((float(Game.arena.get("embers", 0)) + (10.0 * float(depth) if won else 0.0)) * mult))
	_put("embers", _c("embers") + float(e))
	var rv := str(Game.arena.get("rival", ""))
	if rv != "" and cleared >= WAVES - 1:
		Game._rival_meet(rv, won)
	var pb := int(_c("gauntlet_best"))
	var newb := cleared > pb
	if newb:
		_put("gauntlet_best", float(cleared))
	_put("gauntlet_runs", _c("gauntlet_runs") + 1.0)
	var text := ""
	if won:
		if not ("Ember Victor" in Game.titles):
			Game.titles.append(I18n.t("Ember Victor"))
		Game.drop_gear(depth + 1, 3)
		_put("gauntlet_wins", _c("gauntlet_wins") + 1.0)
		text = I18n.t("The ring goes quiet, then roars. All %d waves are yours: %d embers, a prize from the rack%s.") % [WAVES, e, (" -- and " + rv + I18n.t(" tips their head to you")) if rv != "" else ""]
	else:
		text = I18n.t("You fall after %d wave%s. %d embers for the effort%s.") % [cleared, "" if cleared == 1 else "s", e, I18n.t(" -- a new best!") if newb else I18n.t(" (best: %d)") % pb]
	return text


static func gauntlet_menu(hud) -> void:
	var lines := describe() + I18n.t("\n\nEmbers: %d    Best: %d of %d waves    Runs: %d    Victories: %d") % [embers(), int(_c("gauntlet_best")), WAVES, int(_c("gauntlet_runs")), int(_c("gauntlet_wins"))]
	var s := season()
	if not s.is_empty():
		lines += I18n.t("\n%s is on: embers pay double.") % s["name"]
	var opts := [["Begin the Gauntlet", func():
		hud.close_dialog()
		gauntlet_start()]]
	for id in BLESS:
		var bid: String = id
		var rk := bless_rank(bid)
		opts.append(["%s %d/10 -- %s (%s)" % [BLESS[bid][0], rk, BLESS[bid][1], (I18n.t("%d embers") % bless_cost(bid)) if rk < 10 else "max"], func():
			bless_buy(bid)
			gauntlet_menu(hud)])
	opts.append(["Leave", hud.close_dialog])
	hud.open_dialog("The Ember Stone", lines, opts)
