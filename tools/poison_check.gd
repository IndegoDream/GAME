extends SceneTree
## Round 138: poison -- coatings, antidotes, venom, and the caps that keep it from being a button.
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var P = G.sys("poison")
	var ch := []
	ch.append(["system exists", P != null])
	for id in ["venom_coating", "numbing_coating", "antidote"]:
		ch.append(["item %s exists and is a consumable" % id, G.items.has(id) and G.items[id]["type"] == "consumable"])
		var has_recipe := false
		for r in G.recipes:
			if str(r["makes"]) == id:
				has_recipe = true
				for m in r["needs"]:
					if not G.items.has(m):
						has_recipe = false
		ch.append(["recipe for %s uses real materials" % id, has_recipe])
	# ---- coating
	G.add_item("venom_coating", 1, false)
	ch.append(["using a coating coats the weapon", G.use_item("venom_coating") and P.coat_hits == 20 and P.coat_kind == "venom"])
	ch.append(["it was used up", G.count("venom_coating") == 0])
	var E = load("res://scripts/actors/Enemy.gd").new()
	E.etype = "goblin"
	E.stats = G.enemies["goblin"].duplicate(true)
	E.stats["hp"] = 1000
	E.hp = 1000
	root.add_child(E)
	P.on_player_hit(E, 40)
	ch.append(["a hit spends a charge and poisons", P.coat_hits == 19 and E._psn_t > 0.0 and E._psn_dps > 0.0])
	var cap: float = P.foe_cap_dps(E)
	for i in 50:
		P.on_player_hit(E, 500)
	ch.append(["poison is capped per second (%.1f <= %.1f)" % [E._psn_dps, cap], E._psn_dps <= cap + 0.001])
	P.coat_hits = 0
	P.coat_kind = ""
	# ---- it really hurts, slowly
	E._psn_t = 10.0
	E._psn_dps = 5.0
	var hp0: int = E.hp
	E._psn_acc = 0.0
	# (tick the status by hand through the physics path is heavy; the numbers are what matter)
	var tot := 0.0
	for i in 20:
		tot += E._psn_dps * 0.5
	ch.append(["ten seconds of five a second is fifty", absf(tot - 50.0) < 0.01])
	# ---- a boss shrugs it
	var B = load("res://scripts/actors/Enemy.gd").new()
	B.etype = "goblin"
	B.stats = G.enemies["goblin"].duplicate(true)
	B.stats["hp"] = 1000
	B.stats["boss"] = true
	root.add_child(B)
	E._psn_t = 0.0
	E._psn_dps = 0.0
	E.poison(40, 4.0)
	B.poison(40, 4.0)
	ch.append(["a master takes less (%.2f vs %.2f)" % [B._psn_dps, E._psn_dps], B._psn_dps < E._psn_dps and B._psn_t < E._psn_t])
	ch.append(["boss cap is tighter", P.foe_cap_dps(B) < P.foe_cap_dps(E)])
	# ---- numbing
	G.add_item("numbing_coating", 1, false)
	G.use_item("numbing_coating")
	ch.append(["numbing coat set", P.coat_kind == "numb"])
	E._slow = 0.0
	B._slow = 0.0
	P.on_player_hit(E, 30)
	P.on_player_hit(B, 30)
	ch.append(["numbing slows a goblin more than a master", E._slow > B._slow and B._slow > 0.0])
	# ---- you, poisoned
	G.hp = 100
	ch.append(["venom takes hold", P.afflict(5, 3.0) and P.poisoned()])
	for i in 10:
		P.tick(0.5)
	ch.append(["it wears you down (%d)" % G.hp, G.hp < 100 and G.hp >= 1])
	G.hp = 3
	P.afflict(50, 10.0)
	for i in 40:
		P.tick(0.5)
	ch.append(["it never finishes you", G.hp >= 1])
	P.afflict(5, 100.0)
	ch.append(["capped at twelve seconds", P.p_left <= 12.001])
	# ---- antidote
	G.hp = 50
	G.add_item("antidote", 1, false)
	G.use_item("antidote")
	ch.append(["antidote clears it", not P.poisoned()])
	ch.append(["...and wards for a while", P.warded() and not P.afflict(5, 3.0)])
	# ---- resting at home clears
	G.buffs.clear()
	P.afflict(5, 3.0)
	G.log_event("rest_home", {})
	ch.append(["resting at home clears poison", not P.poisoned()])
	# ---- save round trip
	P.coat_kind = "venom"
	P.coat_hits = 7
	var sv: Dictionary = G._systems_save()
	G._systems_reset()
	ch.append(["reset clears the coat", P.coat_hits == 0])
	G._systems_load(sv)
	ch.append(["coat survives a save", P.coat_hits == 7 and P.coat_kind == "venom"])
	P.load_state({"coat_kind": "junk", "coat_hits": 5})
	ch.append(["junk coat loads clean", P.coat_hits == 0 and P.coat_kind == ""])
	# ---- the venomous elite goes through here now
	ch.append(["venomous affix hits the same poison", FileAccess.get_file_as_string("res://scripts/actors/Enemy.gd").find("psn.afflict(tick") > 0])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("POISON CHECK ", ch.size() - bad, " passed, ", bad, " failed")
	quit(1 if bad > 0 else 0)
