extends SceneTree
## Robert: "i cant use any of the items in the pc version". Real Main, a BIG bag, the Pack page; click a slot, click Use/Wear with real mouse events.
var G
func click(pos: Vector2, dbl: bool = false, right: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = pos; ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	ev.pressed = true; ev.double_click = dbl
	root.push_input(ev)
	var up := ev.duplicate(); up.pressed = false
	root.push_input(up)
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	await process_frame
	var n := 0
	for id in G.items.keys():
		if str(G.item_def(id).get("type", "")) in ["consumable", "weapon", "armor", "material"]:
			G.add_item(id, 3, false); n += 1
		if n >= 150: break
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20: await process_frame
	var bad := 0
	hud._hub.show_page("Pack")
	for i in 30: await process_frame
	var kit = hud._kit
	var vis: Rect2 = root.get_visible_rect()
	var pg: Control = hud._hub.pages["Pack"]
	# 1. every slot is clickable and selects; the action card is on screen
	var slots: Array = pg.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and (b as Button).icon != null and b.size.x > 40)
	print("PACK slots visible: ", slots.size(), " window ", vis.size)
	if slots.size() == 0: bad += 1; print("PACK FAIL no slots")
	var tested := 0
	var used := 0
	var picks := []
	for id in G.inventory.keys():
		var ty := str(G.item_def(id).get("type", ""))
		if int(G.inventory[id]) > 0 and ty in ["consumable", "weapon", "armor", "ring", "amulet"] and picks.size() < 3 and (ty == "consumable" or picks.filter(func(x): return str(G.item_def(x).get("type", "")) == ty).size() < 1):
			picks.append(id)
	print("PACK picks ", picks)
	for id in picks:
		pg = hud._hub.pages["Pack"]
		print("PACK t=", Time.get_ticks_msec(), " pick ", id)
		kit = hud._kit
		kit._pick_slot(str(id))
		for i in 2: await process_frame
		pg = hud._hub.pages["Pack"]
		var btn: Button = null
		for c in pg.find_children("*", "Button", true, false):
			var cb := c as Button
			if cb.is_visible_in_tree() and cb.text in ["Use", "Wear"]:
				btn = cb; break
		if btn == null:
			bad += 1; print("PACK FAIL no Use/Wear button for ", id); continue
		tested += 1
		print("PACK t=", Time.get_ticks_msec(), " found ", btn.text)
		var lbl := btn.text
		if not vis.encloses(btn.get_global_rect()):
			bad += 1; print("PACK FAIL action button off screen: ", id, " ", btn.get_global_rect()); continue
		G.hp = maxi(1, int(G.max_hp() * 0.3))
		var hp0: int = G.hp
		var before := JSON.stringify(G.inventory) + JSON.stringify(G.equipment) + str(G.qi) + str(G.weapon)
		click(btn.get_global_rect().get_center())
		for i in 3: await process_frame
		var after := JSON.stringify(G.inventory) + JSON.stringify(G.equipment) + str(G.qi) + str(G.weapon)
		print("PACK result ", id, " ", lbl, " changed=", after != before or G.hp != hp0)
		if after != before or G.hp != hp0:
			used += 1
		else:
			bad += 1; print("PACK FAIL clicking '", lbl, "' did nothing for ", id)
	print("PACK clicked actions ", tested, " effective ", used)
	if tested > 0 and used == 0: bad += 1; print("PACK FAIL no action button had any effect")
	# 2. quick-use by double click on a potion slot
	var salve := ""
	for id in G.inventory.keys():
		if str(G.item_def(id).get("type", "")) == "consumable" and int(G.inventory[id]) > 0:
			salve = str(id); break
	if salve != "":
		kit.refresh()
		for i in 2: await process_frame
		var c0: int = G.count(salve)
		kit._quick(salve)
		for i in 3: await process_frame
		print("PACK quick-use ", salve, " ", c0, " -> ", G.count(salve))
		if G.count(salve) >= c0: bad += 1; print("PACK FAIL quick use")
	print("UI USE PROBE CHECK %d passed, %d failed" % [tested + (1 if salve != "" else 0) - bad, bad])
	quit(1 if bad > 0 else 0)
