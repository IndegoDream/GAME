extends SceneTree
## Pack page at ANY window size: real mouse/touch clicks on slots and Use/Wear, buttons on screen, a screenshot. godot --path . --resolution WxH --script res://tools/pack_shot_probe.gd -- tag [touch]
var G
func click(pos: Vector2, touch: bool) -> void:
	if touch:
		var t := InputEventScreenTouch.new(); t.position = pos; t.index = 0; t.pressed = true
		root.push_input(t)
		var u := InputEventScreenTouch.new(); u.position = pos; u.index = 0; u.pressed = false
		root.push_input(u)
	else:
		var ev := InputEventMouseButton.new(); ev.position = pos; ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
		root.push_input(ev)
		var up := ev.duplicate(); up.pressed = false
		root.push_input(up)
func shot(tag: String) -> void:
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	img.save_png("/tmp/shots/%s.png" % tag)
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() > 0 else "x"
	var touch := args.has("touch")
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	await process_frame
	var want := ["healing_salve", "iron_sword"]
	var n := 0
	for id in G.items.keys():
		var ty := str(G.item_def(id).get("type", ""))
		if ty in ["consumable", "weapon", "ring", "amulet", "material", "armor"]:
			G.add_item(id, 3, false); n += 1
		if n >= 150: break
	for w in want: G.add_item(w, 3, false)
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20: await process_frame
	hud._hub.show_page("Pack")
	for i in 40: await process_frame
	var vis: Rect2 = root.get_visible_rect()
	var bad := 0
	print("SIZE ", tag, " viewport ", vis.size, " window ", DisplayServer.window_get_size())
	var kit = hud._kit
	var anc: Node = kit
	while anc != null and anc != root:
		if anc is Control: print("MIN ", anc.get_class(), " ", anc.name, " min=", (anc as Control).get_combined_minimum_size(), " size=", (anc as Control).size)
		anc = anc.get_parent()
	for c in kit.get_children(): print("KIDMIN ", c.get_class(), " ", (c as Control).get_combined_minimum_size())
	for c in kit.tabs.get_children(): print("TABMIN ", c.name, " ", (c as Control).get_combined_minimum_size())
	shot(tag + "_pack")
	var pg: Control = hud._hub.pages["Pack"]
	# every visible Control must sit inside the screen
	var off := 0
	for c in pg.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and ctl.size.x > 4 and ctl.size.y > 4 and not vis.grow(2).encloses(ctl.get_global_rect()):
			var clipped := false
			var p := ctl.get_parent()
			while p != null and p != pg:
				if p is ScrollContainer: clipped = true; break
				p = p.get_parent()
			if not clipped:
				off += 1
				if off <= 6: print("LAYOUT off-screen: ", ctl.get_class(), " ", ctl.name, " ", ctl.get_global_rect())
	if off > 0: bad += 1; print("LAYOUT FAIL ", off, " controls off screen")
	for id in want:
		hud._hub.show_page("Pack")
		for i in 6: await process_frame
		pg = hud._hub.pages["Pack"]
		# find the slot for the item by clicking real slot buttons until the selection is this item
		var slot: Button = null
		for c in pg.find_children("*", "Button", true, false):
			var b := c as Button
			if b.is_visible_in_tree() and b.icon != null and b.size.x > 30 and (b.tooltip_text.findn(G.item_name(id)) >= 0 or b.name == id or str(b.get_meta("id", "")) == id):
				slot = b; break
		if slot == null:
			hud._kit._pick_slot(id)
			print("PACK note: no slot button found by name for ", id, " (selected through the kit)")
		else:
			var sc := slot.get_parent()
			while sc != null and not (sc is ScrollContainer): sc = sc.get_parent()
			if sc != null: (sc as ScrollContainer).ensure_control_visible(slot)
			for i in 3: await process_frame
			var r := slot.get_global_rect()
			if not vis.encloses(r): bad += 1; print("PACK FAIL slot not on screen ", id, " ", r)
			click(r.get_center(), touch)
		for i in 4: await process_frame
		pg = hud._hub.pages["Pack"]
		var btn: Button = null
		for c in pg.find_children("*", "Button", true, false):
			var cb := c as Button
			if cb.is_visible_in_tree() and cb.text in ["Use", "Wear", "Wield", "Equip"]:
				btn = cb; break
		if btn == null: bad += 1; print("PACK FAIL no Use/Wear button for ", id); shot(tag + "_nobtn_" + id); continue
		if not vis.encloses(btn.get_global_rect()): bad += 1; print("PACK FAIL button off screen ", id, " ", btn.get_global_rect()); continue
		if btn.size.x < 24 or btn.size.y < 24: bad += 1; print("PACK FAIL button too small to hit ", id, " ", btn.size)
		var btxt := btn.text
		shot(tag + "_sel_" + id)
		G.hp = maxi(1, int(G.max_hp() * 0.3))
		var before := JSON.stringify(G.inventory) + JSON.stringify(G.equipment) + str(G.qi) + str(G.weapon) + str(G.hp)
		click(btn.get_global_rect().get_center(), touch)
		for i in 4: await process_frame
		var after := JSON.stringify(G.inventory) + JSON.stringify(G.equipment) + str(G.qi) + str(G.weapon) + str(G.hp)
		var ok := after != before
		print("PACK ", id, " ", btxt, " ", "OK" if ok else "FAIL did nothing")
		if not ok: bad += 1; shot(tag + "_dead_" + id)
	print("PACK SHOT PROBE ", tag, " bad=", bad)
	quit(1 if bad > 0 else 0)
