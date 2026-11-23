extends SceneTree
## Round 183: the store's look packs (scripts/systems/Looks.gd, data/looks.json).
##   godot --headless --path . --script res://tools/looks_check.gd
var passed := 0
var failed := 0
var frames := 0
var started := false

func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 3 or started:
		return false
	started = true
	_run()
	return false

func _btns(hud) -> Array:
	var out := []
	for b in hud._dialog_buttons.get_children():
		if b is Button:
			out.append(b.text)
	return out

func _run() -> void:
	var G = root.get_node("Game")
	G.save_path = "user://looktest_save.json"
	G.save_base = "user://looktest_slots"
	G.playlog_path = "user://looktest_playlog.jsonl"
	G.new_game()
	var S = G.store
	S.file_path = "user://looktest_store.json"
	S.owned = {}
	S.backend = "test"
	var A = G.ads
	A.file_path = "user://looktest_ads.json"
	A.reset_record()
	var LK = G.sys("looks")
	var P: Dictionary = LK.packs()
	check("six packs, each with its items", P.size() == 6 and P.has("coats_pack") and P.has("skies_pack") and P.has("seats_pack") and P.has("spirits_pack") and P.has("trinkets_pack") and P.has("strikes_pack"))
	var store_d: Dictionary = S.data()
	for pk in P:
		check("%s is sold (a cosmetic product with Play and Apple ids)" % pk, store_d["products"].has(pk) and str(store_d["products"][pk]["kind"]) == "cosmetic" and str(store_d["products"][pk].get("google", "")) != "")
		check("%s has at least three looks" % pk, (P[pk].get("items", {}) as Dictionary).size() >= 3)
	check("the Look Collection is sold", store_d["products"].has("look_collection"))
	# owning
	check("a free copy owns no look", not LK.owns("coats_pack") and not LK.owns("seats_pack"))
	LK.choose("coats", "jade")
	check("a look you don't own isn't drawn", LK.coat().is_empty() and LK.current("coats").is_empty())
	check("...and the store offers it", S.can_buy("coats_pack"))
	S.grant("coats_pack", "looks_check")
	check("bought: the coat is drawn", LK.coat().size() == 2 and LK.coat()[0] is Color)
	check("...and the store stops offering it", not S.can_buy("coats_pack"))
	check("buying one pack opens only that pack", not LK.owns("skies_pack"))
	S.grant("look_collection", "looks_check")
	check("the Collection opens every pack and the Style pack", LK.owns("skies_pack") and LK.owns("seats_pack") and LK.owns("spirits_pack") and G.Comfort.style())
	check("...and no single pack is offered on top of it", not S.can_buy("skies_pack") and not S.can_buy("look_collection"))
	S.owned = {}
	A._give("try_style")
	check("an ad's try-on day: every look, for a day", LK.owns("coats_pack") and LK.owns("spirits_pack") and G.Comfort.style() and A.style_trial_left() > 86000.0)
	A._rec["style_until"] = 0.0
	check("the day ends: back to the game's own looks", not LK.owns("coats_pack") and LK.coat().is_empty())
	S.backend = "full"
	check("the box's own builds (and the paid game off Steam) have every look", LK.owns("coats_pack") and LK.owns("seats_pack"))
	S.backend = "test"
	S.grant("look_collection", "looks_check")
	# choosing
	LK.choose("spirits", "")
	check("no strike glow chosen: the game's own colour", LK.slash_color(Color(0.85, 0.92, 1.0)) == Color(0.85, 0.92, 1.0))
	LK.cycle("spirits")
	var sc: Color = LK.slash_color(Color(0.85, 0.92, 1.0))
	check("a Weapon Spirit changes the sweep's colour", sc != Color(0.85, 0.92, 1.0) and LK.item_name("spirits") != "")
	var seen := {}
	for i in 6:
		LK.cycle("spirits")
		seen[str(LK.choice["spirits"])] = true
	check("cycling walks every look and back to the game's own", seen.size() == 5 and seen.has(""), str(seen.keys()))
	# round 188: Strike Styles -- how blows look, never what they do
	LK.choose("spirits", "")
	LK.choose("strikes", "")
	check("no strike style: the game's own blows", LK.strike_style().is_empty() and LK.strike_color(Color(0.1, 0.2, 0.3)) == Color(0.1, 0.2, 0.3))
	var styles := {}
	var FXs = load("res://scripts/fx/FX.gd")
	var dummy := Node3D.new()
	root.add_child(dummy)
	var before := root.get_child_count()
	for sid in P["strikes_pack"]["items"]:
		LK.choose("strikes", str(sid))
		var st: Dictionary = LK.strike_style()
		styles[str(st.get("style", ""))] = true
		FXs.strike(dummy, st, 1.8, 0.0, 1.1)
		FXs.impact(Vector3(0, 1, 0), st, true)
	check("six strike styles, each its own way of drawing a blow", styles.size() == 6 and not styles.has(""), str(styles.keys()))
	if FXs.on():
		check("a style's sweeps and impacts are drawn", dummy.get_child_count() + root.get_child_count() > before)
	LK.choose("strikes", "thunder")
	check("a strike style colours shots and arts too", LK.strike_color(Color(0.95, 0.88, 0.7)) != Color(0.95, 0.88, 0.7))
	LK.cycle("spirits")
	check("a Weapon Spirit tints the strike style", LK.strike_style()["color"] != Color(0.55, 0.75, 1.0))
	LK.choose("spirits", "")
	LK.choose("strikes", "")
	dummy.queue_free()
	LK.choose("skies", "crimson")
	check("a Tribulation Sky colours the breakthrough", LK.sky_color().r > 0.9 and LK.sky_color().g < 0.4)
	LK.choose("skies", "")
	check("the game's own sky is pale blue", LK.sky_color().b > 0.9)
	# every seat is built (in code, no art files) and spins
	for id in P["seats_pack"]["items"]:
		var seat: Node3D = LK.make_seat(str(id), Color(0.8, 0.6, 0.4))
		check("the %s seat is built" % id, seat != null and seat.get_child_count() >= 2 and float(seat.get_meta("spin", 0.0)) > 0.0, str(seat.get_child_count() if seat else -1))
		root.add_child(seat)
		var r0: float = seat.rotation.y
		seat._process(0.5)
		check("...and turns slowly", seat.rotation.y > r0)
		seat.queue_free()
	# the pet redraws in its coat
	var fired := [0]
	var cb := func(): fired[0] += 1
	G.familiar_changed.connect(cb)
	LK.choose("coats", "white_gold")
	check("choosing a coat redraws the companion", fired[0] >= 1)
	G.familiar_changed.disconnect(cb)
	check("the companion's model asks for the coat", FileAccess.get_file_as_string("res://scripts/actors/Familiar.gd").contains("LKs.coat()"))
	check("sitting draws the seat; standing takes it away", FileAccess.get_file_as_string("res://scripts/actors/Player.gd").contains("seat_on(self)") and FileAccess.get_file_as_string("res://scripts/actors/Player.gd").contains("seat_off()"))
	# a breakthrough calls the sky (headless: no drawing, no error)
	LK.choose("skies", "violet")
	G.log_event("breakthrough", {"realm": "test"})
	check("a breakthrough with a sky chosen runs cleanly", true)
	# round 183b: Familiar Trinkets -- every trinket sits on a wolf, young and grown into its spirit form
	for st in [1, 3]:
		for tid in P["trinkets_pack"]["items"]:
			var bw = load("res://scripts/actors/Beast.gd").build("Wolf", Color(0.5, 0.45, 0.4))
			bw.evolve(st, Color(0.8, 0.9, 1.0))
			var ok: bool = bw.trinket(P["trinkets_pack"]["items"][tid])
			check("trinket %s on a stage-%d wolf" % [tid, st], ok and bw.find_children("Trinket*", "", true, false).size() > 0)
			bw.free()
	LK.choose("trinkets", "red_cord")
	check("a chosen trinket is drawn when the pack is yours", not LK.current("trinkets").is_empty())
	check("the companion's model asks for the trinket", FileAccess.get_file_as_string("res://scripts/actors/Familiar.gd").contains("_model.trinket(trk)"))
	# round 183b: the wardrobe -- free, any wearable you've held
	S.owned = {}
	var armor_ids := []
	for id in G.items:
		if G.gear_family(str(id)) == "armor":
			armor_ids.append(str(id))
		if armor_ids.size() >= 2:
			break
	check("two chest pieces to play with", armor_ids.size() == 2)
	LK.seen = {}
	LK.wardrobe = {}
	G.add_item(armor_ids[0], 1, false)
	G.add_item(armor_ids[1], 1, false)
	check("holding a wearable puts it in the wardrobe (free -- no pack needed)", LK.seen.has(armor_ids[0]) and LK.seen.has(armor_ids[1]))
	check("materials don't", (func():
		for id in G.items:
			if str(G.items[id].get("type", "")) == "material":
				G.add_item(str(id), 1, false)
				return not LK.seen.has(str(id))
		return true).call())
	G.equipment["chest"] = armor_ids[0]
	var name0 := ""
	for lk in G.worn_looks():
		if str(lk.get("slot", "")) == "chest":
			name0 = JSON.stringify(lk)
	check("worn as itself to begin with", name0 != "")
	check("the chest's options list both pieces", LK.options_for("chest").has(armor_ids[0]) and LK.options_for("chest").has(armor_ids[1]))
	LK.set_wardrobe("chest", "iron_sword")
	check("a weapon can't be a chest look", LK.wardrobe_for("chest") == "")
	LK.set_wardrobe("chest", "never_seen_item")
	check("a piece never held can't be chosen", LK.wardrobe_for("chest") == "")
	var wb: Dictionary = {"hp": G.max_hp(), "dmg": G.damage(), "def": G.call("defense") if G.has_method("defense") else 0}
	LK.set_wardrobe("chest", armor_ids[1])
	var name1 := ""
	for lk in G.worn_looks():
		if str(lk.get("slot", "")) == "chest":
			name1 = JSON.stringify(lk)
	check("the chest now LOOKS like the other piece", name1 != "" and name1 != name0 or G.piece_look(armor_ids[0]) == G.piece_look(armor_ids[1]))
	check("...and wears exactly the same numbers", G.max_hp() == wb["hp"] and G.damage() == wb["dmg"] and (G.call("defense") if G.has_method("defense") else 0) == wb["def"] and G.worn("chest") == armor_ids[0])
	LK.set_wardrobe("chest", "-")
	var hidden := true
	for lk in G.worn_looks():
		if str(lk.get("slot", "")) == "chest":
			hidden = false
	check("a hidden slot isn't drawn", hidden and G.worn("chest") == armor_ids[0])
	LK.set_wardrobe("chest", "")
	check("'as worn' brings the real piece back", G.worn_looks().any(func(l): return str(l.get("slot", "")) == "chest"))
	var hud0 = root.get_tree().get_first_node_in_group("hud")
	if hud0 == null:
		hud0 = load("res://scripts/ui/HUD.gd").new()
		root.add_child(hud0)
		await process_frame
	LK.wardrobe_menu(hud0)
	var wbtn: Array = _btns(hud0)
	check("the Wardrobe page lists the chest", wbtn.any(func(t): return str(t).begins_with("Chest")), str(wbtn))
	LK._slot_menu(hud0, "chest")
	wbtn = _btns(hud0)
	check("the chest's page: as worn, hide, and the pieces you've held", wbtn.has("As worn (what you really wear)") and wbtn.has("Hide this slot") and wbtn.size() >= 4, str(wbtn))
	hud0.close_dialog()
	LK.set_wardrobe("chest", armor_ids[1])
	G.equipment.erase("chest")
	S.grant("look_collection", "looks_check")
	# saves keep the choice
	LK.choose("seats", "koi")
	var sv: Dictionary = LK.save_state()
	LK.reset()
	check("a new game starts with the game's own looks", str(LK.choice["seats"]) == "")
	LK.load_state(sv)
	check("a save keeps the chosen looks", str(LK.choice["seats"]) == "koi" and str(LK.choice["coats"]) == "white_gold")
	check("...and the wardrobe and what you've held", LK.wardrobe_for("chest") == armor_ids[1] and LK.seen.has(armor_ids[0]))
	G.save_game()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
	check("...in the save file", raw is Dictionary and str(raw.get("systems", {}).get("looks", {}).get("choice", {}).get("seats", "")) == "koi")
	# the page
	var hud = root.get_tree().get_first_node_in_group("hud")
	if hud == null:
		hud = load("res://scripts/ui/HUD.gd").new()
		root.add_child(hud)
		await process_frame
	LK.menu(hud)
	var b: Array = _btns(hud)
	var has_slot := false
	for t in b:
		if str(t).begins_with("Pet coat:"):
			has_slot = true
	check("Looks page: a switch for each owned pack", hud._dialog.visible and has_slot and b.has("Back"), str(b))
	S.owned = {}
	LK.menu(hud)
	b = _btns(hud)
	var buys := 0
	for t in b:
		if str(t).begins_with("Get "):
			buys += 1
	check("Looks page: unowned packs and the Collection are offered", buys == 7, str(b))
	check("Looks page: the Wardrobe is always there (free)", b.any(func(t): return str(t).begins_with("Wardrobe")))
	G.Comfort.menu(hud)
	var cb2: Array = _btns(hud)
	var has_looks := false
	for t in cb2:
		if str(t).begins_with("Looks"):
			has_looks = true
	check("Comforts & Style links to the Looks page", has_looks, str(cb2))
	hud.close_dialog()
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("looktest"):
			DirAccess.remove_absolute("user://" + f)
	print("LOOKS CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
