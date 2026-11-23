extends SceneTree
## round 127: "pay for convenience, not to win" -- proven, not promised.
##  1. what a purchase changes: none of the power numbers (health, damage, qi, drop odds, prices, locks)
##  2. the power functions never mention the store (source scan)
##  3. the catalogue only holds allowed kinds of product
var passed := 0
var failed := 0
var f := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func snap(G) -> Dictionary:
	seed(777)
	var lo := 0
	var hi := 0
	for i in 400:
		lo += G.roll_quality(0)
		hi += G.roll_quality(3)
	return {"hp": G.max_hp(), "dmg": G.damage(), "qi": G.kill_qi_at(5), "q0": lo, "q3": hi, "sell": G.sell_price("iron_sword"),
		"power_dmg": G.Hook.power("dmg"), "power_hp": G.Hook.power("hp"), "lock30": G.store.level_locked("floor30"), "pity": G.Hook.pity_boost()}
func body(src: String, fn: String) -> String:
	var a := src.find("\nfunc %s(" % fn)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + 5)
	return src.substr(a, (b if b > 0 else src.length()) - a)
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.save_path = "user://fair_save.json"
	G.save_base = "user://fair_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	var S = G.store
	S.file_path = "user://fair_store.json"
	S.owned = {}
	S.backend = "test"
	var base: Dictionary = snap(G)
	check("free copy: three slots, no comforts, no style", G.SLOTS == 3 and not G.Comfort.comfort() and not G.Comfort.style())
	S.grant("full_game", "fair_check")
	check("the full game opens the comforts", G.Comfort.comfort() and G.SLOTS == 5 and not G.Comfort.style())
	S.grant("style_pack", "fair_check")
	check("the style pack opens the auras", G.Comfort.style())
	var paid: Dictionary = snap(G)
	for k in base:
		check("buying changes no '%s'" % k, base[k] == paid[k], "%s -> %s" % [str(base[k]), str(paid[k])])
	# the steam demo and the paid steam game
	S.owned = {}
	S.backend = "demo"
	check("the demo has no comforts", not G.Comfort.comfort())
	check("the demo keeps floor 5, the village and the valley open", S.travel_check("floor5") == "" and S.travel_check("village") == "" and S.travel_check("valley") == "")
	check("the demo stops at floor 6", S.travel_check("floor6") == "locked")
	var leaks := []
	for rid in G.FrontierGen.data().get("regions", {}):
		var d := int(G.FrontierGen.region(rid).get("depth", 0))
		if (d > S.free_depth()) != (S.travel_check("frontier:" + rid) == "locked"):
			leaks.append(rid)
	check("the demo stops at every Land deeper than its floors", leaks.is_empty(), str(leaks))
	S.backend = "full"
	check("the paid game has comforts and style from the start", G.Comfort.comfort() and G.Comfort.style())
	var steam: Dictionary = snap(G)
	for k in base:
		check("the paid game's '%s' is the same" % k, base[k] == steam[k], "%s -> %s" % [str(base[k]), str(steam[k])])
	# the comforts really work
	S.backend = "test"
	S.grant("full_game", "fair_check")
	G.home = {"have": true, "plots": 3, "garden": [{}, {}, {}], "stash": {}, "queue": {}, "rested_until": 0.0, "stage": 0}
	var mat := ""
	for id in G.items:
		if str(G.items[id].get("type", "")) == "material":
			mat = str(id)
			break
	G.add_item(mat, 5, false)
	G.Comfort.on_village()
	check("auto-stash moves materials home", G.count(mat) == 0 and int(G.home["stash"].get(mat, 0)) == 5)
	G.counters["comfort_autostash"] = 0.0
	G.add_item(mat, 3, false)
	G.Comfort.on_village()
	check("auto-stash can be turned off", G.count(mat) == 3)
	check("stash from anywhere", G.Comfort.stash_now() == 3 and G.count(mat) == 0)
	var sw: String = G.gear_pool(1, ["weapon"])[0]
	G.add_item(sw, 2)
	var g0: int = G.gold
	var spare: Array = G.Comfort.spare_list()
	check("spare gear is listed", spare.size() > 0)
	var r: Array = G.Comfort.sell_spare()
	check("spare gear sells for gold", r[0] >= 1 and G.gold == g0 + r[1] and r[1] > 0, str(r))
	check("nothing spare is left", G.Comfort.spare_list().is_empty())
	S.grant("style_pack", "fair_check")
	G.Comfort.cycle_aura()
	check("an aura cycles", G.Comfort.aura_index() == 1 and G.Comfort.aura_color().a > 0.0)
	# source scan: the power functions must never see the store
	var src := FileAccess.get_file_as_string("res://scripts/core/Game.gd")
	for fn in ["max_hp", "damage", "weapon_damage", "roll_quality", "kill_qi_at", "drop_gear", "gain_insight", "add_qi", "heal", "sell_price", "record_kill", "proficiency_mult"]:
		var b := body(src, fn)
		check("Game.%s exists" % fn, b != "")
		for w in ["store", "Comfort", "owned.", "full_game", "ads_on"]:
			check("Game.%s never mentions %s" % [fn, w], not b.contains(w))
	var hk := FileAccess.get_file_as_string("res://scripts/systems/Hook.gd")
	for w in ["store", "Comfort", "full_game"]:
		check("Hook never mentions %s" % w, not hk.contains(w))
	# the pretend store can't be switched on in a store build
	check("a Play build never gets the pretend store", not S.test_allowed(true, false))
	check("a Steam build never gets the pretend store", not S.test_allowed(false, true))
	check("a box build can", S.test_allowed(false, false))
	# a hand-edited record of purchases is dropped
	S.owned = {}
	S.backend = "google"
	S.file_path = "user://fair_store2.json"
	S.owned = {"full_game": true}
	S._save()
	S.owned = {}
	S._load()
	check("a genuine record loads", S.owned.has("full_game") and not S.tampered)
	var txt := FileAccess.get_file_as_string("user://fair_store2.json")
	var forged = JSON.parse_string(txt)
	forged["owned"]["style_pack"] = true
	var ff := FileAccess.open("user://fair_store2.json", FileAccess.WRITE)
	ff.store_string(JSON.stringify(forged))
	ff.close()
	S.owned = {}
	S._load()
	check("an added purchase breaks the seal", S.owned.is_empty() and S.tampered)
	S.tampered = false
	forged["owned"] = {"full_game": true}
	forged.erase("sig")
	ff = FileAccess.open("user://fair_store2.json", FileAccess.WRITE)
	ff.store_string(JSON.stringify(forged))
	ff.close()
	S.owned = {}
	S._load()
	check("an unsigned record is not believed", S.owned.is_empty() and S.tampered)
	S.backend = "test"
	# the catalogue
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/store.json"))
	var allowed: Array = d["fair_play"]["kinds_allowed"]
	for key in d["products"]:
		check("product %s has an allowed kind" % key, str(d["products"][key].get("kind", "")) in allowed)
	check("the promise is written", str(d["fair_play"]["promise"]).contains("never power"))
	for c in G.Comfort.COMFORTS:
		check("comfort %s is not a power word" % c[0], not (str(c[0]) in d["fair_play"]["never_sold"]))
	# round 182: rewarded ads count too -- an ad you watch is a price paid in time, so it buys looks only
	var never: Array = d["fair_play"]["never_sold"]
	for gid in d.get("ads", {}).get("gifts", {}):
		var gg: Dictionary = d["ads"]["gifts"][gid]
		check("ad gift %s carries no effect numbers" % gid, not gg.has("effect"), str(gg.get("effect", "")))
		var ask := str(gg.get("ask", "")).to_lower()
		for w in ["insight", "luck", "gold", "damage", "health", "qi ", "experience", "drop"]:
			if ask.contains(w) and not ask.contains("stay exactly the same"):
				check("ad gift %s doesn't offer %s" % [gid, w], false, ask)
	var ads_src := FileAccess.get_file_as_string("res://scripts/core/Ads.gd")
	var give := body(ads_src, "_give")
	check("Ads._give exists", give != "")
	for w in ["Game.gold", "add_buff", "add_item", "add_qi", "gain_insight", "loot_luck", "insight_mult", "add_skill_xp"]:
		check("an ad gift never touches %s" % w, not give.contains(w))
	S.owned = {}
	S.backend = "test"
	var A = G.ads
	A.file_path = "user://fair_ads.json"
	A.reset_record()
	var before: Dictionary = snap(G)
	check("no style before the ad", not G.Comfort.style())
	A._give("try_style")
	check("an ad's day of the Style pack: auras on", G.Comfort.style() and A.style_trial_left() > 86000.0)
	var after: Dictionary = snap(G)
	for k in before:
		check("an ad gift changes no '%s'" % k, before[k] == after[k], "%s -> %s" % [str(before[k]), str(after[k])])
	A._rec["style_until"] = 0.0
	check("and it ends", not G.Comfort.style())
	A.reset_record()
	# round 183: the look packs -- every pack owned and every look chosen changes no number
	var LK = G.sys("looks")
	check("the looks system is there", LK != null)
	S.owned = {}
	S.backend = "test"
	var lbase: Dictionary = snap(G)
	for pk in LK.packs():
		check("look pack %s is a cosmetic product" % pk, str(d["products"].get(pk, {}).get("kind", "")) == "cosmetic")
		S.grant(str(pk), "fair_check")
	S.grant("look_collection", "fair_check")
	for kind in ["coats", "skies", "seats", "spirits", "trinkets"]:
		LK.cycle(kind)
	for sl in ["chest", "cowl", "boots"]:                 # round 183b: the wardrobe changes what's drawn, never a number
		LK.set_wardrobe(sl, "-")
	check("every look chosen", not LK.current("coats").is_empty() and not LK.current("seats").is_empty() and not LK.current("skies").is_empty() and not LK.current("spirits").is_empty())
	var lafter: Dictionary = snap(G)
	for k in lbase:
		check("every look on changes no '%s'" % k, lbase[k] == lafter[k], "%s -> %s" % [str(lbase[k]), str(lafter[k])])
	var lsrc := FileAccess.get_file_as_string("res://scripts/systems/Looks.gd")
	for w in ["add_qi", "gain_insight", "add_buff", "Game.gold", "G.gold", "add_item", "loot_luck", "damage_mult", "max_hp"]:
		check("Looks never touches %s" % w, not lsrc.contains(w))
	for fn in ["max_hp", "damage", "weapon_damage", "kill_qi_at", "add_qi", "gain_insight"]:
		check("Game.%s never mentions the looks" % fn, not body(src, fn).contains("looks"))
	LK.reset()
	S.owned = {}
	for fn in DirAccess.get_files_at("user://"):
		if fn.begins_with("fair_"):
			DirAccess.remove_absolute("user://" + fn)
	print("FAIR CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
