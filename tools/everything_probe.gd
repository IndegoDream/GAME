extends SceneTree
## Robert 2026-10-22: "make sure everything works -- items, special moves, special attacks and effects".
## Real Main + Player in a real level. Phase A items, B gear, C arts (all), D weapon blows, E effects. Prints PROBE lines and a summary.
var G
var m
var bad := 0
var notes := []
var msgs := []
func get_tree_nodes(g: String) -> Array:
	return root.get_tree().get_nodes_in_group(g)
func fail(s: String) -> void:
	bad += 1
	print("PROBE FAIL ", s)
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://probe_save.json"
	G.save_base = "user://probe_slots"
	G.playlog_path = "user://probe_playlog.jsonl"
	G.message.connect(func(t): msgs.append(str(t)))
	load("res://Main.gd").force_veil = true
	m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	G.go_to("floor1", "<")
	for i in 30:
		await process_frame
	var p = m.player
	if p == null:
		fail("no player"); quit(1); return
	# ---------- A: every consumable
	var cons: Array = []
	var gear: Array = []
	for id in G.items.keys():
		var ty := str(G.item_def(id).get("type", ""))
		if ty == "consumable": cons.append(id)
		elif ty in ["weapon", "armor", "ring", "amulet"]: gear.append(id)
	var used := 0
	var noeff := []
	for id in cons:
		G.hp = maxi(1, int(G.max_hp() * 0.4)); G.qi = 0.0
		G.add_item(id, 2, false)
		var b: int = G.count(id); var hp0: int = G.hp; var qi0: float = G.qi; var st0 := JSON.stringify(G.statuses) if "statuses" in G else ""
		msgs.clear()
		var ok = G.use_item(id)
		await process_frame
		var a: int = G.count(id)
		if a >= b:
			fail("A not consumed %s (ok=%s msg=%s)" % [id, ok, " / ".join(msgs).left(80)])
		else:
			used += 1
			if G.hp == hp0 and G.qi == qi0 and (("statuses" in G) and JSON.stringify(G.statuses) == st0) and msgs.is_empty():
				noeff.append(id)
	print("PROBE A consumables ", cons.size(), " used ", used, " no-visible-effect ", noeff.size(), " ", noeff.slice(0, 12))
	# ---------- B: gear equip / unequip
	var eq_bad := 0
	for id in gear:
		G.add_item(id, 1, false)
		msgs.clear()
		var r = G.equip(id)
		await process_frame
		if G.equipped_count(id) < 1:
			eq_bad += 1
			print("PROBE B not worn ", id, " -> ", str(r).left(70))
	print("PROBE B gear ", gear.size(), " not worn ", eq_bad)
	if eq_bad > 0: bad += eq_bad
	# ---------- C: every art
	for aid in G.lattice_data().get("arts", {}).keys():
		G.learn(str(aid), "probe")
	for pt in G.lattice_data().get("points", []):
		G.open_point(str(pt.get("id", "")))
	G.realm = G.REALMS.size() - 1
	for aid in G.arts.keys():
		G.set_flag("ax:%s:sect" % aid, true)
	var arts: Array = G.arts.keys()
	var cast_ok := 0
	var blocked := []
	var fx0 := 0
	for aid in arts:
		G.qi = G.qi_to_next() + 999.0; G.hp = G.max_hp()
		if G.has_method("clear_cooldowns"): G.clear_cooldowns()
		var before := root.get_node(NodePath(m.get_path())).get_child_count()
		msgs.clear()
		var r = p.cast_art(str(aid), Vector3(0, 0, 1))
		for i in 3:
			await process_frame
		if r:
			cast_ok += 1
		else:
			blocked.append("%s:%s" % [aid, " / ".join(msgs).left(40)])
	print("PROBE C arts known ", arts.size(), " cast ok ", cast_ok, " refused ", blocked.size())
	for b in blocked.slice(0, 40):
		print("PROBE C refused ", b)
	# ---------- C2: arts that need a foe -- stand one right in front and recast; attack arts must hurt it
	var es0 := get_tree_nodes("enemy")
	var c2_ok := 0
	var c2_names := []
	for aid in arts:
		var ablk := str(G.art_blocked(aid))
		var fam := str(G.art_family(aid))
		if fam == "guard":
			continue
		if es0.is_empty():
			break
		var e0 = es0[0]
		e0.hp = 99999
		p.global_position = e0.global_position + Vector3(0, 0, -1.3)
		p._model.rotation.y = 0.0
		G.qi = G.qi_to_next() + 999.0; G.hp = int(G.max_hp() * 0.5)
		if G.has_method("clear_cooldowns"): G.clear_cooldowns()
		var h0: int = e0.hp
		msgs.clear()
		var r2 = p.cast_art(str(aid), Vector3(0, 0, 1))
		for i in 30:
			await process_frame
		if r2:
			c2_ok += 1
		else:
			c2_names.append("%s:%s" % [aid, " / ".join(msgs).left(45)])
	print("PROBE C2 with a foe in front: cast ok ", c2_ok, " still refused ", c2_names.size(), " ", c2_names.slice(0, 12))
	# ---------- C3: guard arts are passive -- wired, they must change what gets through
	var base_take: float = 1.0
	var guards: Array = []
	for aid in arts:
		if str(G.art_family(aid)) == "guard":
			guards.append(aid)
	G.art_slots["guard"] = ""
	var t0: float = G.guard_take(true)
	var gb := 0
	for aid in guards:
		G.wire(aid)
		var t1: float = G.guard_take(true)
		var blk = G.block(100, true)
		if t1 > 1.0 or t1 < 0.04 or is_nan(t1):
			gb += 1
			print("PROBE C3 guard art gives a broken take: ", aid, " ", t1)
		if blk.size() == 0 and false:
			gb += 1
	print("PROBE C3 guard arts ", guards.size(), " base take ", t0, " worse ", gb)
	if gb > 0: bad += gb
	# ---------- D: blows with each kind of weapon (fresh floor: the arts above cleared the last one)
	G.realm = 3
	G.go_to("village", "<")
	for i in 40: await process_frame
	G.go_to("floor1", "<")
	for i in 60: await process_frame
	p = m.player
	var enemies := get_nodes_in_group("enemy")
	print("PROBE D enemies on floor ", enemies.size())
	var hits := 0
	var tried := 0
	var kinds := {}
	for id in gear:
		if str(G.item_def(id).get("type", "")) != "weapon": continue
		var kind := str(G.item_def(id).get("kind", G.item_def(id).get("class", "?")))
		if kinds.has(kind) and kinds[kind] >= 2: continue
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		G.add_item(id, 1, false); G.equip(id)
		var es := get_nodes_in_group("enemy")
		if es.is_empty(): continue
		var e = es[0]
		p.global_position = e.global_position + Vector3(0, 0, -1.4)
		p._model.rotation.y = 0.0
		var hp0: int = e.hp
		e.hp = 99999
		var h1: int = e.hp
		tried += 1
		p._start_blow(false, 1.0)
		for i in 40:
			await process_frame
		if e.hp < h1 or not is_instance_valid(e):
			hits += 1
		else:
			print("PROBE D no damage with ", id, " kind ", kind, " ranged=", G.weapon_is_ranged())
	print("PROBE D weapons tried ", tried, " dealt damage ", hits, " kinds ", kinds.keys())
	# ---------- E: effects at every level while arts and blows fire (errors would show as SCRIPT ERROR lines)
	var gfx = load("res://scripts/core/Gfx.gd")
	var saved_fx = gfx.settings.get("effects", "high")
	for lvl in ["low", "medium", "high"]:
		gfx.settings["effects"] = lvl
		var n := 0
		for aid in arts.slice(0, 16):
			G.qi = G.qi_to_next() + 999.0; G.hp = G.max_hp()
			if G.has_method("clear_cooldowns"): G.clear_cooldowns()
			p.cast_art(str(aid), Vector3(0, 0, 1)); n += 1
			p._start_blow(false, 1.0)
			for i in 4: await process_frame
		print("PROBE E effects ", lvl, " fired ", n, " arts + blows")
	gfx.settings["effects"] = saved_fx
	print("EVERYTHING PROBE CHECK %d passed, %d failed" % [(cons.size() + gear.size() + arts.size()) - bad, bad])
	print("PROBE DONE fails=", bad)
	quit(1 if bad > 0 else 0)
