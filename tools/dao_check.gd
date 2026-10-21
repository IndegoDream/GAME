extends SceneTree
## Round 139: dao sense, the eight daos, a dao of your own, and your own difficulty.
## Run: godot --headless --path . --script tools/dao_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var D = G.sys("dao")
	var F = G.sys("difficulty")
	var ch := []
	ch.append(["systems exist", D != null and F != null])
	ch.append(["eight daos", D.dao_ids().size() == 8])
	ch.append(["starts dull, nothing felt", D.stage() == 0 and D.sense == 0.0 and D.dao_fx("blade").is_empty()])
	ch.append(["no effects before sense", D.effects().is_empty()])
	# ---- events feed the right dao, and sense follows
	for i in 10:
		G.log_event("kill", {"type": "goblin"})
	ch.append(["kills teach the blade", float(D.pts.get("blade", 0.0)) > 5.0])
	ch.append(["...and a little sense", D.sense > 1.0])
	G.log_event("craft", {})
	ch.append(["crafting teaches the forge", float(D.pts.get("forge", 0.0)) > 1.0])
	# ---- the daily cap
	for i in 400:
		G.log_event("kill", {"type": "goblin"})
	ch.append(["a day caps one dao (%d)" % int(D.pts["blade"]), float(D.pts["blade"]) <= 80.1])
	# ---- sense gates rank
	D.pts["blade"] = 1500.0
	D.sense = 0.0
	ch.append(["points alone give nothing without sense", D.rank("blade") == 0 and D.dao_fx("blade").is_empty()])
	D.sense = 30.0
	ch.append(["stirring allows glimpse only", D.stage() == 1 and D.rank("blade") == 1])
	D.sense = 1200.0
	ch.append(["dao-seeing allows own-way rank", D.stage() == 5 and D.rank("blade") == 5])
	# ---- effects: focus full, off-focus 60%
	var base: float = G.tech_effect("damage_mult", 1.0)
	var e_off: float = float(D.dao_fx("blade")["damage_mult"])
	D.focus = "blade"
	var e_on: float = float(D.dao_fx("blade")["damage_mult"])
	ch.append(["focus gives full, off-focus 60%% (%.3f vs %.3f)" % [e_on, e_off], absf((e_on - 1.0) - 0.12) < 0.001 and absf((e_off - 1.0) - 0.072) < 0.001])
	ch.append(["flows into the real damage multiplier", G.tech_effect("damage_mult", 1.0) > base * 1.04 and G.tech_effect("damage_mult", 1.0) >= 1.119])
	# ---- additive keys stay additive
	D.pts["seeker"] = 1500.0
	var sk: Dictionary = D.dao_fx("seeker")
	ch.append(["additive gift stays small (%s)" % str(sk), float(sk["gather_chance"]) < 0.2 and float(sk["sense_radius"]) < 3.0])
	# ---- contemplate
	D.sense = 100.0
	G.current_level = "floor_3"
	var t1: String = D.contemplate()
	ch.append(["aware: contemplating names the dao (%s)" % t1, t1.find("leans toward") >= 0 and D.cont["dao"] != ""])
	var res: String = str(D.cont["dao"])
	ch.append(["a place always leans the same way", D.resonance("floor_3") == res])
	var before: float = float(D.pts.get(res, 0.0))
	var dp: Dictionary = D.day_pts.duplicate()
	D.day_pts = {}
	D.on_event("kill" if res == "blade" else "craft", {})
	D.contemplate(); D.contemplate()
	ch.append(["only three a day", D.contemplates_left() == 0 and D.contemplate().find("tomorrow") >= 0])
	# ---- focus switching: once a day
	D.focus = ""
	D.focus_day = ""
	ch.append(["first focus is free", D.set_focus("forge").begins_with("You turn")])
	ch.append(["a second change the same day is refused", D.set_focus("blade").begins_with("You changed")])
	# ---- found your own
	D.focus = "blade"
	D.pts["blade"] = 1500.0
	D.sense = 1200.0
	ch.append(["can found at the top", D.can_found()])
	ch.append(["needs a name", D.found("  ", "keen").begins_with("A dao needs")])
	ch.append(["needs a real tenet", D.found("Sky", "nope").begins_with("Choose")])
	var off: float = G.tech_effect("crit_chance", 0.0)
	var msg: String = D.found("Sky-Splitting Way", "keen")
	ch.append(["founding works (%s)" % msg, D.is_founded("blade") and not D.can_found()])
	ch.append(["a founded dao gives half again", absf((float(D.dao_fx("blade")["damage_mult"]) - 1.0) - 0.18) < 0.001])
	ch.append(["its tenet is a real effect", G.tech_effect("crit_chance", 0.0) >= off + 0.049])
	# ---- save / load
	var saved: Dictionary = G._systems_save()
	var snap := JSON.stringify(D.save_state())
	G._systems_reset()
	ch.append(["reset clears it", D.sense == 0.0 and D.founded.is_empty() and D.focus == ""])
	G._systems_load(saved)
	ch.append(["load restores it exactly", JSON.stringify(D.save_state()) == snap])
	# ---- bad save data does not break it
	D.load_state({"pts": {"blade": "x", "nope": 5}, "focus": "zzz", "founded": {"dao": "zzz"}, "sense": "bad"})
	ch.append(["junk save loads clean", D.focus == "" and D.founded.is_empty() and not D.pts.has("nope")])
	# ---- difficulty
	G.new_game()
	D = G.sys("dao")
	F = G.sys("difficulty")
	ch.append(["standard changes nothing", F.is_standard() and F.reward() == 0.0 and G.diff_reward() == 1.0 and F.effects().is_empty()])
	G.current_level = "floor_2"
	ch.append(["not changeable away from the village", F.set_tier("hard").begins_with("Change this")])
	G.current_level = "village"
	ch.append(["hard in the village", F.set_tier("hard").begins_with("Difficulty") and absf(F.foe_hp() - 1.2) < 0.001])
	ch.append(["hard pays more", G.diff_reward() > 1.1])
	ch.append(["unknown tier refused", F.set_tier("zzz") == ""])
	var hp0: int = G.max_hp()
	F.toggle_handicap("frail")
	ch.append(["frail cuts life and pays (%d -> %d)" % [hp0, G.max_hp()], G.max_hp() < hp0 and F.reward() > 0.19])
	F.set_tier("gentle")
	ch.append(["gentle pays less", G.diff_reward() < 1.0])
	var sv: Dictionary = G._systems_save()
	var js := JSON.stringify(F.save_state())
	G._systems_reset()
	ch.append(["reset returns to standard", F.is_standard()])
	G._systems_load(sv)
	ch.append(["difficulty survives a save", JSON.stringify(F.save_state()) == js])
	F.load_state({"tier": "nope", "handicaps": {"x": true, "dull": true}})
	ch.append(["junk difficulty loads clean", F.tier == "standard" and F.handicaps.size() == 1])
	# ---- an enemy really changes
	F.reset()
	var base_hp := _foe_hp(G)
	F.set_tier("mythic")
	var m_hp := _foe_hp(G)
	ch.append(["a mythic foe has more life (%d -> %d)" % [base_hp, m_hp], m_hp > base_hp * 1.6])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("DAO CHECK ", ch.size() - bad, " passed, ", bad, " failed")
	quit(1 if bad > 0 else 0)


func _foe_hp(G) -> int:
	var E = load("res://scripts/actors/Enemy.gd").new()
	E.etype = "goblin"
	E.stats = G.enemies["goblin"].duplicate(true)
	E._round30_numbers({})
	var v := int(E.stats["hp"])
	E.free()
	return v
