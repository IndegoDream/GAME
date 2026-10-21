extends SceneTree
## Distance weapons (round 119): equip a bow / crossbow / qi focus, shoot a real foe.
##   godot --headless --path . --script res://tools/ranged_check.gd
var G
var level
var player
var step := 0
var wait := 0.0
var passed := 0
var failed := 0
var foe

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passed += 1; print("  PASS  " + name)
	else: failed += 1; print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))

func _equip(id: String) -> void:
	G.add_item(id, 1)
	G.weapon = id

func _foe_at(dist: float):
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead:
			var f: Vector3 = player.global_position + Vector3(0, 0, dist)
			e.global_position = Vector3(f.x, player.global_position.y, f.z)
			e.set_physics_process(false)
			return e
	return null

func _process(d: float) -> bool:
	if wait > 0.0:
		wait -= d
		return false
	match step:
		0:
			G = root.get_node("Game")
			G.playlog_path = "user://tool_playlog.jsonl"
			G.save_path = "user://ranged_save.json"
			G.save_base = "user://ranged_slots"
			G.sys("quests").quiet = true
			G.new_game()
			load("res://scripts/systems/LegacyLines.gd").skip = true
			var hud = load("res://scripts/ui/HUD.gd").new()
			root.add_child(hud)
			level = load("res://scripts/world/Level.gd").new()
			level.name = "Level"
			level.build(G.load_level_def("floor1"))
			root.add_child(level)
			G.current_level = "floor1"
			player = load("res://scripts/actors/Player.gd").new()
			root.add_child(player)
			player.global_position = level.spawn_point("P")
			print("== the kinds ==")
			for k in ["bow", "crossbow", "ki"]:
				check("kind %s exists, is ranged, has a skill and combat data" % k, G.WEAPON_KINDS.has(k) and G.WEAPON_KINDS[k].get("ranged", false) and G.skill_defs.has(G.WEAPON_SKILL[k]) and G.combat_data()["ranged"].has(k))
			var mins := 99
			for id in G.items:
				if str(G.items[id].get("kind", "")) in ["bow", "crossbow", "ki"]:
					mins = mini(mins, int(G.items[id].get("tier", 0)))
					check("%s is a drop with a tier >= RANGED_MIN_TIER" % id, bool(G.items[id].get("drop", false)) and int(G.items[id].get("tier", 0)) >= G.RANGED_MIN_TIER)
			check("no distance weapon can drop on floors 1-3", G.gear_pool(1, ["weapon"]).filter(func(i): return G.weapon_is_ranged(i)).is_empty() and G.gear_pool(3, ["weapon"]).filter(func(i): return G.weapon_is_ranged(i)).is_empty())
			check("...but some can by floor 8", not G.gear_pool(8, ["weapon"]).filter(func(i): return G.weapon_is_ranged(i)).is_empty())
			check("a made-for-you bow on floor 2 becomes a sword", str(G.make_custom_gear_kind_for_test("bow", 2)) == "sword" if G.has_method("make_custom_gear_kind_for_test") else true)
			print("== a bow ==")
			_equip("hunter_shortbow")
			check("the bow is ranged", G.weapon_is_ranged())
			foe = _foe_at(8.0)
			check("a foe to shoot", foe != null)
			player._model.rotation.y = 0.0
			wait = 0.2
		1:
			player._fire_ranged(G.ranged_data(), 0.0, false)
			check("firing puts an arrow in the world", root.get_tree().get_nodes_in_group("shot").size() == 1)
			wait = 0.8
			step = 2
			return false
		2:
			check("the arrow hit the foe", foe.hp < foe.stats.get("hp", 9999) or foe._dead, "hp %s" % str(foe.hp))
			check("the arrow is gone after hitting", root.get_tree().get_nodes_in_group("shot").size() == 0)
			print("== charged bow pierces ==")
			player._shot_cool = 0.0
			var a = _foe_at(5.0)
			var b = null
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if e != a and is_instance_valid(e) and not e._dead:
					b = e
					break
			if b:
				b.global_position = player.global_position + Vector3(0, 0, 9.0)
				b.set_physics_process(false)
			var ha: int = a.hp
			var hb: int = b.hp if b else 0
			foe = a
			set_meta("ha", ha); set_meta("hb", hb); set_meta("b", b)
			player._fire_ranged(G.ranged_data(), 1.0, true)
			wait = 1.0
			step = 3
			return false
		3:
			var b = get_meta("b")
			check("a full draw hurts the first foe", foe.hp < int(get_meta("ha")) or foe._dead)
			if b:
				check("a full draw pierces to a second foe behind", (is_instance_valid(b) and (b.hp < int(get_meta("hb")) or b._dead)) or not is_instance_valid(b))
			print("== cooldown ==")
			player._shot_cool = 5.0
			var n0: int = root.get_tree().get_nodes_in_group("shot").size()
			player._fire_ranged(G.ranged_data(), 0.0, false)
			check("you can't shoot while it's cooling", root.get_tree().get_nodes_in_group("shot").size() == n0)
			print("== qi focus ==")
			_equip("jade_bead_wraps")
			player._shot_cool = 0.0
			player.ki_shots = 6.0
			player._fire_ranged(G.ranged_data(), 0.0, false)
			check("a ki bolt costs one burst", absf(player.ki_shots - 5.0) < 0.01, str(player.ki_shots))
			player._shot_cool = 0.0
			player._fire_ranged(G.ranged_data(), 1.0, true)
			check("a held burst costs three", absf(player.ki_shots - 2.0) < 0.01, str(player.ki_shots))
			player._shot_cool = 0.0
			player.ki_shots = 0.5
			var n1: int = root.get_tree().get_nodes_in_group("shot").size()
			player._fire_ranged(G.ranged_data(), 0.0, false)
			check("with no breath left it doesn't fire", root.get_tree().get_nodes_in_group("shot").size() == n1)
			player._ki_regen(2.0)
			check("the pool refills as you breathe", player.ki_shots > 2.0, str(player.ki_shots))
			print("== crossbow ==")
			_equip("garrison_crossbow")
			player._shot_cool = 0.0
			var n2: int = root.get_tree().get_nodes_in_group("shot").size()
			player._fire_ranged(G.ranged_data(), 0.0, false)
			check("the crossbow fires", root.get_tree().get_nodes_in_group("shot").size() == n2 + 1)
			check("its reload is slower than a bow's", player._shot_cool > 1.0, str(player._shot_cool))
			print("== melee patterns ==")
			_equip("iron_sword")
			player._combo = 0
			player._combo_t = 0.0
			var f2 = _foe_at(3.0)
			player._model.rotation.y = 0.0
			player._start_blow(false, 1.0)
			check("a blow steps toward a foe in front", player._lunge_t > 0.0 and player._lunge_v > 0.0, "%s %s" % [player._lunge_t, player._lunge_v])
			check("the sword's chain is slash, thrust, slash", G.weapon_trait().get("anims", []) == ["attack-melee-right", "jab", "attack-melee-right"])
			check("a spear fights in thrusts", G.combat_data()["weapon_traits"]["spear"]["anims"] == ["jab", "jab", "jab"])
			print("== held weapons ==")
			for k in ["bow", "crossbow", "ki", "sword", "staff"]:
				check("%s has a held model" % k, load("res://scripts/world/Dress.gd").HELD.has(k))
			print("RANGED %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
	step += 1
	return false
