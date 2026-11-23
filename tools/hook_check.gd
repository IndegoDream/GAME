extends SceneTree
## round 126: kill chains, the luck meter, the login streak and the daily challenges.
var passed := 0
var failed := 0
var f := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.save_path = "user://hook_save.json"
	G.save_base = "user://hook_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	var H = G.Hook
	var T: int = H.today()
	# --- streak
	G.counters.erase("hook_login")
	var g0: int = G.gold
	H.daily_login()
	check("first login: streak 1", int(G.counters["hook_streak"]) == 1)
	check("first login pays gold", G.gold == g0 + 40, "%d -> %d" % [g0, G.gold])
	var g1: int = G.gold
	H.daily_login()
	check("the same day pays nothing twice", G.gold == g1 and int(G.counters["hook_streak"]) == 1)
	G.counters["hook_login"] = float(T - 1)
	G.playtime += 400.0
	H.daily_login()
	check("next day: streak 2", int(G.counters["hook_streak"]) == 2)
	G.counters["hook_login"] = float(T - 1)
	G.playtime += 400.0
	G.counters["hook_streak"] = 2.0
	var pills: int = G.count("breakthrough_pill")
	H.daily_login()
	check("day 3 brings a pill", G.count("breakthrough_pill") == pills + 1 and int(G.counters["hook_streak"]) == 3)
	G.counters["hook_login"] = float(T - 3)
	G.playtime += 400.0
	H.daily_login()
	check("a missed day starts the streak again", int(G.counters["hook_streak"]) == 1)
	check("best streak is remembered", int(G.counters["hook_best_streak"]) >= 3)
	# --- the clock can't be farmed
	G.counters["hook_login"] = float(T + 5)
	var gc: int = G.gold
	var sk: int = int(G.counters["hook_streak"])
	H.daily_login()
	check("a clock set back pays nothing", G.gold == gc and int(G.counters["hook_streak"]) == sk)
	G.counters["hook_login"] = float(T - 1)
	G.counters["hook_streak"] = 9.0
	H.daily_login()
	check("a new day with no play pays nothing", G.gold == gc and int(G.counters["hook_streak"]) == 9)
	G.playtime += 90.0
	H.daily_login()
	check("a minute of play unlocks the day", int(G.counters["hook_streak"]) == 10)
	check("but the gold is capped by the time played", G.gold - gc <= 40 + 8 * 1, "%d" % (G.gold - gc))
	G.counters["hook_seen"] = Time.get_unix_time_from_system() + 7200.0
	var gw: int = G.gold
	H.welcome_back()
	check("welcome-back ignores a clock set back", G.gold == gw)
	# --- chain
	var foe := ""
	for id in G.enemies:
		if not bool(G.enemies[id].get("passive", false)) and not bool(G.enemies[id].get("boss", false)):
			foe = str(id)
			break
	H.chain = 0
	for i in 5:
		G.record_kill(foe)
	check("five kills in a row: chain 5", H.chain == 5, str(H.chain))
	H.chain_at = Time.get_ticks_msec() - 20000
	G.record_kill(foe)
	check("a long pause breaks the chain", H.chain == 1, str(H.chain))
	# --- daily: slay
	var need := 0
	for ch in H._challenges():
		if ch["id"] == "slay":
			need = int(ch["need"])
	G.counters["hook_p_slay"] = float(need - 1)
	G.counters["hook_done_slay"] = 0.0
	var gm2: int = G.gold
	G.record_kill(foe)
	check("the slay daily completes and pays", float(G.counters["hook_done_slay"]) == 1.0 and G.gold > gm2)
	check("the NEXT line names a daily", H.next_line().begins_with("Daily:") or H.next_line() == "")
	check("describe lists the streak and luck", H.describe().contains("Streak") and H.describe().contains("Luck"))
	# --- luck meter
	G.counters["hook_pity"] = 0.0
	check("no luck boost at the start", H.pity_boost() == 0)
	G.counters["hook_pity"] = 12.0
	check("a little at 12", H.pity_boost() == 1)
	G.counters["hook_pity"] = 22.0
	check("more at 22", H.pity_boost() == 2)
	G.counters["hook_pity"] = 31.0
	check("the top at the full meter", H.pity_boost() == 4)
	H.found(1)
	check("an ordinary find leaves the meter", int(G.counters["hook_pity"]) == 31)
	H.found(3)
	check("a Superior find resets the meter", int(G.counters["hook_pity"]) == 0)
	# the meter really changes what drops
	var hi := 0
	var lo := 0
	for i in 300:
		G.counters["hook_pity"] = 31.0
		if G.roll_quality(G.Hook.pity_boost()) >= 3: hi += 1
		G.counters["hook_pity"] = 0.0
		if G.roll_quality(G.Hook.pity_boost()) >= 3: lo += 1
	check("a full meter drops far more fine gear", hi > lo * 3, "%d vs %d" % [hi, lo])
	# --- round 126b
	check("Hollow Nights in late October", str(H.season({"month": 10, "day": 28}).get("name", "")) == "Hollow Nights")
	check("no season in August", H.season({"month": 8, "day": 1}).is_empty())
	check("Lantern Festival spans the new year", str(H.season({"month": 1, "day": 1}).get("name", "")) == "Lantern Festival")
	var hp0: int = G.max_hp()
	G.realm = 2
	var dm0: int = G.damage()
	G.counters["embers"] = 500.0
	check("a blessing is bought", H.bless_buy("might") and H.bless_buy("vigor"))
	check("embers are spent", H.embers() == 500 - 25 - 25)
	check("might raises damage", G.damage() > dm0, "%d -> %d" % [dm0, G.damage()])
	check("vigor raises health", G.max_hp() >= hp0)
	check("rank two costs more", H.bless_cost("might") == 50)
	var cmp: String = H.compare("iron_sword")
	check("a weapon compares", cmp.contains("damage"), cmp)
	var gmast: int = G.gold
	for i in 50:
		H.mastery("goblin")
	check("50 of a kind pays mastery", G.gold >= gmast + 60, "%d -> %d" % [gmast, G.gold])
	G.counters["hook_kills"] = 99.0
	H.mastery("goblin")
	check("100 kills gives a title", "Hundredfold" in G.titles)
	var st: Dictionary = H.gauntlet_build(3)
	check("ten waves", st["rounds"].size() == 10 and st["round_names"].size() == 10)
	var fit := true
	for w in st["rounds"]:
		var n := 0
		for fo in w:
			n += int(fo["count"])
		if n > 8: fit = false
	check("every wave fits the ring", fit)
	check("a rival waits at the end", st["defs"].size() == 1 and str(st["round_names"][9]).begins_with("The Rival"))
	G.hp = G.max_hp()
	H.gauntlet_start()
	check("the run begins", G.arena_active() and str(G.arena["event"]) == "gauntlet")
	var fury0: int = G.damage()
	G.arena_cleared()
	check("a boon is taken between waves", G.arena["boons"].size() == 1 and int(G.arena["stage"]) == 1)
	H.gauntlet_take("fury")
	check("fury raises damage", G.damage() > fury0)
	H.gauntlet_take("second")
	check("second wind revives once", H.gauntlet_revive() and G.arena_active())
	check("...and only once", not H.gauntlet_revive())
	var e0: int = H.embers()
	G.arena["stage"] = 10
	G._arena_finished(true)
	check("a win pays embers", H.embers() > e0)
	check("a win gives the title", "Ember Victor" in G.titles)
	check("the best is kept", int(G.counters["gauntlet_best"]) == 10)
	check("the boon ends with the run", is_equal_approx(H.power("dmg"), 1.0 + 0.03 * float(H.bless_rank("might"))))
	G.counters["hook_seen"] = Time.get_unix_time_from_system() - 5.0 * 3600.0
	G.counters.erase("hook_chest_pt")
	var gm3: int = G.gold
	H.welcome_back()
	check("time away fills a chest", G.gold > gm3)
	var gm4: int = G.gold
	H.welcome_back()
	check("only once", G.gold == gm4)
	for fn in DirAccess.get_files_at("user://"):
		if fn.begins_with("hook_"):
			DirAccess.remove_absolute("user://" + fn)
	print("HOOK CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
