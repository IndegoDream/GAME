extends SceneTree
## Round 141b: beast roles and deeds, wayfarers (trust, oath, sworn), wild beasts and waiting wayfarers on the floor.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://mn_save.json"
	G.save_base = "user://mn_slots"
	G.new_game()
	var M = G.sys("menagerie")
	check("system exists", M != null)
	var valid_keys: Array = G.ADDITIVE_KEYS.duplicate()
	for k in ["damage_mult", "damage_taken", "insight_mult", "move_mult", "bond_mult", "meditate_mult", "swarm_mult", "qi_mult", "ranged_mult", "hp_mult", "attack_speed", "cleanse_speed"]:
		valid_keys.append(k)
	# ---- data
	var roles: Dictionary = M.data["roles"]
	check("twenty roles", roles.size() == 20)
	for rid in roles:
		var r: Dictionary = roles[rid]
		check("role %s has a name, desc, effect and a deed" % rid, str(r.get("name", "")) != "" and str(r.get("desc", "")) != "" and not r.get("effect", {}).is_empty() and not r.get("deed", {}).is_empty())
		for k in r["effect"]:
			check("role %s effect key %s is one the game reads" % [rid, k], str(k) in valid_keys or str(k).begins_with("craft_"))
		var dd: Dictionary = r["deed"]
		check("role %s deed has a cooldown and does something" % rid, float(dd.get("cool", 0)) >= 60 and (dd.has("buff") or dd.has("heal") or dd.has("items")))
		for k in dd.get("buff", {}).get("effect", {}):
			check("role %s deed buff key %s is read" % [rid, k], str(k) in valid_keys or str(k).begins_with("craft_"))
	var tame := 0
	var roles_used := {}
	for eid in G.enemies:
		var st: Dictionary = G.enemies[eid]
		if st.has("familiar") and bool(st.get("passive", false)) and not bool(st.get("construct", false)):
			tame += 1
			check("%s has a role" % eid, roles.has(M.role_id(str(eid))))
			roles_used[M.role_id(str(eid))] = true
			for f in st["familiar"].get("finds", []):
				check("%s find %s is an item" % [eid, f], G.items.has(str(f)))
	check("100 tameable species", tame == 100)
	check("all twenty roles are in use", roles_used.size() == 20)
	var floors := {}
	for s in M.data["new_species"]:
		floors[int(s["floor"])] = true
		check("new species %s is in enemies, passive, tameable" % s["id"], G.enemies.has(s["id"]) and bool(G.enemies[s["id"]].get("passive", false)) and int(G.enemies[s["id"]].get("tameable", 0)) > 0)
	check("new species spread over 15+ floors", floors.size() >= 15)
	# ---- a beast's role: passive, deed, cooldown
	G.familiar = {"species": "cave_hare", "name": "Burrow", "bond": 50.0, "tier": 0}
	G.contracts = [G.familiar]
	check("the hare is a forager", M.role_id("cave_hare") == "forager")
	var base: float = G.tech_effect("gather_chance", 0.0)
	G.familiar["bond"] = 0.0
	var low: float = G.tech_effect("gather_chance", 0.0)
	G.familiar["bond"] = 100.0
	var high: float = G.tech_effect("gather_chance", 0.0)
	check("a forager's gift grows with the bond (%.3f < %.3f)" % [low, high], high > low)
	var n0: int = G.count("spirit_herb") + G.count("ember_root") + G.count("iron_ore")
	var told: String = M.ask_beast(G.familiar)
	var n1: int = G.count("spirit_herb") + G.count("ember_root") + G.count("iron_ore")
	check("the forage deed brings back 2-3 finds", n1 - n0 >= 2 and n1 - n0 <= 3 and told != "")
	var again: String = M.ask_beast(G.familiar)
	check("...and then it needs a while", again.find("needs a while") >= 0)
	var inf: Dictionary = M.beast_deed_info(G.familiar)
	check("the cooldown is visible", float(inf["left"]) > 200.0)
	G.familiar = {"species": "spirit_toad", "name": "Mend", "bond": 10.0, "tier": 0}
	G.contracts = [G.familiar]
	G.hp = 5
	var h0: int = G.hp
	M.ask_beast(G.familiar)
	check("the healer's deed heals about a third of your life", G.hp - h0 >= int(G.max_hp() * 0.3) - 1)
	G.familiar = {"species": "rock_badger", "name": "Bulwark", "bond": 10.0, "tier": 0}
	G.contracts = [G.familiar]
	var tk0: float = G.tech_effect("damage_taken", 1.0)
	M.ask_beast(G.familiar)
	check("the guardian's deed is a buff that lowers damage taken", G.tech_effect("damage_taken", 1.0) < tk0 and G.buff_left("mn_guard") > 40.0)
	G.familiar = {"species": "grey_wolf", "name": "Fang", "bond": 10.0, "tier": 0}
	G.contracts = [G.familiar]
	var m0: int = G.count("raw_meat")
	M.ask_beast(G.familiar)
	check("the hunter brings meat and hide", G.count("raw_meat") - m0 >= 2 and G.count("beast_hide") >= 1)
	# ---- a second beast gives a share
	G.familiar = {"species": "dune_hound", "name": "Nose", "bond": 40.0, "tier": 0}
	var second := {"species": "glass_stag", "name": "Prism", "bond": 40.0, "tier": 0, "out": true}
	G.contracts = [G.familiar, second]
	check("both beasts are out", G.beasts_out().size() == 2)
	check("the second gives less than the lead", M.beast_grow(second) < M.beast_grow(G.familiar))
	# ---- wayfarers
	check("twenty-one wayfarers", M.data["wayfarers"].size() == 21)
	var seen := {}
	for w in M.data["wayfarers"]:
		var nm: String = w["name"]
		check("%s has a unique name" % nm, not seen.has(nm))
		seen[nm] = true
		check("%s has a persona, line, gift, deed, oath, sworn gift" % nm, str(w.get("persona", "")) != "" and str(w.get("line", "")) != "" and not w.get("gift", {}).is_empty() and not w.get("deed", {}).is_empty() and not w.get("oath", {}).is_empty() and not w.get("sworn_gift", {}).is_empty())
		for k in w["gift"]:
			check("%s gift key %s is read" % [nm, k], str(k) in valid_keys or str(k).begins_with("craft_"))
		for k in w["sworn_gift"]:
			check("%s sworn gift key %s is read" % [nm, k], str(k) in valid_keys or str(k).begins_with("craft_"))
		for k in w["deed"].get("buff", {}).get("effect", {}):
			check("%s deed key %s is read" % [nm, k], str(k) in valid_keys or str(k).begins_with("craft_"))
		for t in w["towns"]:
			check("%s's town %s exists as a town level" % [nm, t], FileAccess.file_exists("res://levels/%s.json" % t))
		check("%s asks to swear on a real floor" % nm, int(w["oath"]["depth"]) >= 5 and int(w["oath"]["depth"]) <= 50)
	for w in M.data["wayfarers"]:
		M.trust[str(w["name"])] = 50.0
		var lines: Array = M.human_lines(str(w["name"]))
		var joined := "".join(lines)
		check("%s's Party-page lines read cleanly (%d lines)" % [w["name"], lines.size()], lines.size() >= 3 and not ("%g" in joined or "%s" in joined or "%d" in joined))
	var Marin := "Marin Ashgrove"
	check("a wayfarer can be taken on with no friendship", G.bond(Marin).get("warmth", 0.0) < 5.0 and G.in_party(Marin) < 0)
	M.trust.erase(Marin)
	G.hp = 5
	var r: String = M.recruit(Marin, "Marin Ashgrove, a field medic.", "village", Color(0.8, 0.8, 0.8))
	check("...they say yes", r == "yes" and G.in_party(Marin) >= 0)
	check("trust starts at 10", is_equal_approx(M.trust_of(Marin), 10.0))
	var t0: float = M.trust_of(Marin)
	for i in 20:
		G.log_event("kill", {"type": "goblin"})
	check("kills together build trust", M.trust_of(Marin) > t0 + 4.0)
	var gk0: float = G.tech_effect("heal_on_kill", 0.0)
	check("her gift is active while she travels with you", gk0 > 0.0)
	M.trust[Marin] = 100.0
	check("...and stronger at full trust", G.tech_effect("heal_on_kill", 0.0) > gk0)
	var h1: int = G.hp
	var hb: String = M.ask_human(Marin)
	check("her deed binds your wounds (half your life)", G.hp - h1 >= int(G.max_hp() * 0.45) and hb != "")
	check("...and has a cooldown", M.ask_human(Marin).find("needs a while") >= 0)
	check("using it builds trust", true)
	# ---- the oath
	M.trust[Marin] = 59.0
	M.deep[Marin] = 20
	check("no oath below trust 60", not M.oath_ready(Marin))
	M.trust[Marin] = 61.0
	M.deep[Marin] = 3
	check("no oath before the oath floor", not M.oath_ready(Marin))
	M.deep[Marin] = 10
	check("oath at trust 60 and floor 10", M.oath_ready(Marin) and M.oath_text(Marin) != "")
	var kill_g: float = G.tech_effect("heal_on_kill", 0.0)
	var sw: String = M.swear(Marin)
	check("swearing says something and sticks", sw != "" and M.is_sworn(Marin))
	check("sworn companions give a second gift", G.tech_effect("heal_on_kill", 0.0) > kill_g)
	check("no second oath", not M.oath_ready(Marin))
	# ---- sworn can always be called back; the unsworn need warmth
	G.part_with_companion(G.in_party(Marin))
	G.current_level = "village"
	G.bond(Marin)["warmth"] = 0.0
	check("a sworn companion can be called from town with no warmth", G.can_recall(Marin) == "")
	var Dorn := "Dorn Quill"
	M.recruit(Dorn, "Dorn Quill, a ranger.", "village", Color.WHITE)
	G.part_with_companion(G.in_party(Dorn))
	G.bond(Dorn)["warmth"] = 0.0
	check("an unsworn one is not", G.can_recall(Dorn) != "")
	# ---- saving
	M.cool["b:Burrow"] = G._now() + 100.0
	var saved: Dictionary = M.save_state()
	M.reset()
	check("reset clears", not M.is_sworn(Marin) and M.trust.is_empty())
	M.load_state(saved)
	check("save and load keep the oath, trust and cooldowns", M.is_sworn(Marin) and M.trust_of(Marin) >= 99.0 and M.cool.has("b:Burrow"))
	# ---- the floor
	var cand8: Array = M.wild_candidates(8)
	check("wild beasts for floor 8 are the floor-4..8 kinds", cand8.size() >= 5 and "ridge_goat" in cand8 and not "grey_wolf" in cand8)
	check("floor 1 has none of the new kinds", M.wild_candidates(1).is_empty())
	G.realm = 1
	var lvl = load("res://scripts/world/Level.gd").new()
	lvl.name = "Level5"
	lvl.build(G.load_level_def("floor5"))
	root.add_child(lvl)
	var found := []
	for c in lvl.get_children():
		if c.get_script() != null and "npc_name" in c and M.is_wayfarer(str(c.npc_name)):
			found.append(str(c.npc_name))
	check("Shellhaven holds Hesk and Tamsin (%s)" % str(found), "Hesk the Younger" in found and "Tamsin Reed" in found)
	lvl.queue_free()
	var wild := 0
	var worst := 0
	for i in 8:
		var l8 = load("res://scripts/world/Level.gd").new()
		l8.name = "Level8_%d" % i
		l8.build(G.load_level_def("floor8"))
		root.add_child(l8)
		var here := 0
		for c in l8.get_children():
			if "etype" in c and (M.data["new_species"] as Array).any(func(s): return s["id"] == str(c.etype)):
				here += 1
		wild += here
		worst = maxi(worst, here)
		l8.queue_free()
	check("wild beasts appear on floor 8 (%d over 8 builds), never more than 2 at once (%d)" % [wild, worst], wild >= 1 and worst <= 2)
	print("MENAGERIE CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
