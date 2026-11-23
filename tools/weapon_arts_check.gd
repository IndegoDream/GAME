extends SceneTree
## Round 188: three arts for every kind of weapon -- learned by fighting with it, used only with it in hand, and each
## one really does what it says (cast in a real place, against real foes).
##   godot --headless --path . --script res://tools/weapon_arts_check.gd
var _pass := 0
var _fail := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _weapon_of_kind(G, skill: String) -> String:
	for id in G.items:
		var d: Dictionary = G.items[id]
		if str(d.get("type", "")) == "weapon" and str(G.WEAPON_SKILL.get(str(d.get("kind", "sword")), "")) == skill:
			return str(id)
	return ""


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://weapon_arts_check"
	G.save_path = "user://weapon_arts_check.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.go_to("floor1", "<")
	var lv = null
	for i in 600:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == "floor1" and lv.stream_left() == 0 and i > 10:
			break
	var pl = root.get_tree().get_first_node_in_group("player")
	var AX = G.sys("arts")
	check("the place and the player are up", lv != null and pl != null and AX != null)
	if pl == null or AX == null:
		_end()
		return
	for e in root.get_tree().get_nodes_in_group("enemy"):
		e.queue_free()                                         # (only the foes this check puts down)
	await process_frame
	var all: Array = AX.weapon_arts()
	check("36 weapon arts (%d)" % all.size(), all.size() == 36)
	var skills := ["sword", "dagger", "saber", "spear", "axe", "hammer", "halberd", "staff", "unarmed", "bow", "crossbow", "ki"]
	var tpls := {}
	for s in skills:
		var mine: Array = AX.weapon_arts(s)
		var lv_ok := mine.size() == 3 and int(AX.def_of(mine[0])["req"]["level"]) == 5 and int(AX.def_of(mine[2])["req"]["level"]) == 30
		check("%s: three arts, at skill 5, 15 and 30" % s, lv_ok, mine)
		for aid in mine:
			tpls[G.art_template(aid)] = true
	check("at least twelve different ways of fighting among them (%d)" % tpls.size(), tpls.size() >= 12, tpls.keys())
	var named := true
	for aid in all:
		if str(G.technique_defs.get(aid, {}).get("name", "")) == "" or str(G.technique_defs[aid].get("desc", "")) == "":
			named = false
	check("every one has a name and says what it does", named)
	# ---- learning by fighting -----------------------------------------------------------------------------------
	G.skills["spear"] = 2250.0                               # (skill level = sqrt(xp / 10): 15)
	check("(spear at skill 15)", G.skill_level("spear") == 15, G.skills.get("spear"))
	var sp_w = _weapon_of_kind(G, "spear")
	G.inventory[sp_w] = 1
	G.weapon = sp_w
	AX.sync()
	check("skill 15 with the spear: the first two spear arts are yours", G.has_tech("w_dragon_thrust") and G.has_tech("w_vaulting_spear"))
	check("...not the third (skill 30)", not G.has_tech("w_hundred_points"))
	check("...and the new one for the spear in hand is on a quick key", G.quick_slots.has("w_dragon_thrust"), G.quick_slots)
	var sw = _weapon_of_kind(G, "sword")
	G.inventory[sw] = 1
	G.weapon = sw
	check("a spear art with a sword in hand: no", G.art_blocked("w_dragon_thrust") != "", G.art_blocked("w_dragon_thrust"))
	G.weapon = sp_w
	check("...with a spear: yes", G.art_blocked("w_dragon_thrust") == "", G.art_blocked("w_dragon_thrust"))
	# ---- every art, cast for real ---------------------------------------------------------------------------------
	G.hp = 999999
	var EN := load("res://scripts/actors/Enemy.gd")
	var fails := []
	for aid in all:
		var w = AX.weapon_of(aid)
		var wid = _weapon_of_kind(G, w) if w != "unarmed" else ""
		if w != "unarmed" and wid == "":
			fails.append([aid, "no weapon of that kind"])
			continue
		if wid != "":
			G.inventory[wid] = 1
		G.weapon = wid
		G.techniques[aid] = true
		G.heat = 0.0
		G.qi = 1e9
		pl._cool.clear()
		pl._counter_t = 0.0
		pl._hurt_cool = 0.0
		# two foes just in front, one a little behind them
		var fwd := Vector3(sin(pl._model.rotation.y), 0, cos(pl._model.rotation.y))
		var foes := []
		for k in 3:
			var at: Vector3 = pl.global_position + fwd * (2.0 + 1.2 * k) + Vector3(fwd.z, 0, -fwd.x) * (0.5 if k == 1 else 0.0)
			var e = lv._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": "goblin", "cell": lv.world_to_cell(at)})
			foes.append(e)
		await process_frame
		await process_frame
		for e in foes:
			e.stats["hp"] = 999999
			e.hp = 999999
			e.set_physics_process(false)
			e.global_position = pl.global_position + fwd * (2.0 + 1.2 * foes.find(e)) + Vector3(0, e.global_position.y - pl.global_position.y, 0)
		var hp0 := 0
		for e in foes:
			hp0 += int(e.hp)
		var ok: bool = pl.cast_art(aid, fwd)
		if G.art_template(aid) == "counter_stance":
			check("%s: the stance holds" % aid, ok and pl._counter_t > 0.0)
			var php: int = G.hp
			pl._hurt_cool = 0.0
			pl.take_damage(50, "test", foes[0])
			await process_frame
			check("%s: a blow in the stance is turned (no harm) and answered" % aid, G.hp == php and int(foes[0].hp) < 999999, [G.hp, php, foes[0].hp])
		else:
			for f in 90:
				await process_frame
			var hp1 := 0
			for e in foes:
				if is_instance_valid(e):
					hp1 += int(e.hp)
			var moved_ok: bool = G.art_template(aid) in ["blink", "pull"]
			if not ok or (hp1 >= hp0 and not moved_ok):
				fails.append([aid, ok, hp0 - hp1, G.art_template(aid)])
		for e in foes:
			if is_instance_valid(e):
				e.queue_free()
		await process_frame
	check("every weapon art, cast in a real place, reaches its foes", fails.is_empty(), fails)
	_end()


func _end() -> void:
	print("WEAPON ARTS CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
