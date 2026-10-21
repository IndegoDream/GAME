extends SceneTree
## Round 139: the bag as slots with pictures. Run: godot --headless --path . --script tools/bag_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	var kit = hud._kit
	var ch := []
	G.add_item("spirit_herb", 7, false)
	G.add_item("healing_salve", 3, false)
	G.add_item("iron_ore", 12, false)
	G.add_item("venom_coating", 1, false)
	G.add_item("iron_sword", 1, false)
	kit.bag_view = "grid"
	G.counters["bag_view"] = 0.0
	kit.fill_pack()
	await process_frame
	var slots = kit.pack_body.find_children("*", "HFlowContainer", true, false)
	ch.append(["a slot grid is drawn", slots.size() >= 1])
	var grid = null
	for sl in slots:
		if sl.get_child_count() >= 20:
			grid = sl
	var btns := []
	for c in grid.get_children():
		if c is Button and not c.is_queued_for_deletion():
			btns.append(c)
	ch.append(["one slot per item kind (%d)" % btns.size(), btns.size() == 5])
	ch.append(["empty slots fill the bag out", grid.get_child_count() >= 20])
	var with_icon := 0
	for b in btns:
		if b.icon != null:
			with_icon += 1
	ch.append(["every item slot has a picture", with_icon == btns.size()])
	var real := 0
	for id in ["spirit_herb", "healing_salve", "iron_ore", "venom_coating", "iron_sword"]:
		if Icons.has_item(id):
			real += 1
	ch.append(["all five have their own icon file", real == 5])
	# count badge
	var badge := 0
	for b in btns:
		for c in b.get_children():
			if c is Label and c.text.is_valid_int():
				badge += 1
	ch.append(["stacks show a count", badge >= 3])
	# every item in the game has an icon
	var missing := []
	for id in G.items:
		if not Icons.has_item(str(id)):
			missing.append(id)
	ch.append(["every item in the game has an icon (%s)" % str(missing.slice(0, 5)), missing.is_empty()])
	# tap a slot -> its card and actions
	btns[0].pressed.emit()
	await process_frame
	await process_frame
	ch.append(["tapping selects", kit.bag_sel != ""]) 
	var acts = kit.pack_body.find_children("*", "Button", true, false)
	var names := []
	for b in acts:
		if not b.is_queued_for_deletion():
			names.append(b.text)
	ch.append(["actions appear (%s)" % str(names.slice(-4)), names.has("Bench") or names.has("Use") or names.has("Wear")])
	# use the salve through the card
	kit.bag_sel = "healing_salve"
	kit.fill_pack()
	await process_frame
	var use = null
	for b in kit.pack_body.find_children("*", "Button", true, false):
		if b.text == "Use" and not b.is_queued_for_deletion():
			use = b
	ch.append(["Use is on the card for a consumable", use != null])
	G.hp = 10
	var before: int = G.count("healing_salve")
	use.pressed.emit()
	ch.append(["using it works", G.count("healing_salve") == before - 1 and G.hp > 10])
	# filters
	kit.bag_filter = "Materials"
	kit.fill_pack()
	await process_frame
	var g2 = null
	for sl in kit.pack_body.find_children("*", "HFlowContainer", true, false):
		if sl.get_child_count() >= 20:
			g2 = sl
	var n2 := 0
	for c in g2.get_children():
		if c is Button and not c.is_queued_for_deletion():
			n2 += 1
	ch.append(["the Materials filter shows two kinds (%d)" % n2, n2 == 2])
	kit.bag_filter = "All"
	# list view still there
	kit._set_view("list")
	await process_frame
	await process_frame
	ch.append(["the list view is one tap away", kit.bag_view == "list" and kit.pack_body.find_children("*", "HFlowContainer", true, false).all(func(n): return n.get_child_count() < 20)])
	ch.append(["...and remembered", float(G.counters.get("bag_view", 0.0)) > 0.0])
	kit._set_view("grid")
	await process_frame
	# a phone-width pack draws too
	kit._short_screen = true
	kit.fill_pack()
	await process_frame
	var g3 = null
	for sl in kit.pack_body.find_children("*", "HFlowContainer", true, false):
		if sl.get_child_count() >= 20:
			g3 = sl
	ch.append(["phone view draws", g3.get_child_count() >= 20])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("BAG CHECK ", ch.size() - bad, " passed, ", bad, " failed")
	quit(1 if bad > 0 else 0)
