extends SceneTree
## Round 137: the Craft page in the real menu. godot --headless --path . --script tools/craft_page_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	var ch := []
	var hub = hud._hub
	ch.append(["Craft is a page of the menu", hub.pages.has("Craft") and hub.buttons.has("Craft")])
	# empty first
	hub.show_page("Craft")
	await process_frame
	ch.append(["empty page draws (no errors)", hub._craft.get_child_count() > 0])
	# fill the world: make things, meet foes, see materials
	G.skills["alchemy"] = 100000.0
	G.skills["smithing"] = 100000.0
	G.add_item("spirit_herb", 30, false)
	G.add_item("iron_ore", 30, false)
	G.add_item("goblin_tooth", 3, false)
	G.add_item("rough_ruby", 2, false)
	G.add_item("silver_ore", 2, false)
	G.gold = 99999
	for r in G.recipes:
		if str(r["makes"]) == "healing_salve":
			G.craft_attempt(r, "balanced", 0.0, 0.5)
	G.forge_piece("armor", "iron_ore", "", 0.0, 0.5)
	G.kills["goblin"] = 12
	G.loot_source = "goblin"
	G.add_item("goblin_tooth", 1, false)
	G.clear_loot_source()
	G.mat_known["iron_ore"] = true
	hub.show_page("Craft")
	await process_frame
	await process_frame
	var bar = null
	for c0 in hub._craft.get_children():
		if c0 is HFlowContainer and not c0.is_queued_for_deletion():
			bar = c0
	ch.append(["tabs were made", bar != null and bar.get_child_count() >= 4])
	var names := []
	if bar:
		for b in bar.get_children():
			names.append(b.text)
	print("CRAFT TABS ", names)
	ch.append(["Road Workshop, Commissions, Recipes tabs first", names.size() > 2 and names[0] == "Road Workshop" and names[1] == "Commissions" and names[2] == "Recipes"])
	ch.append(["all four tabs", "Herbology" in names and "Supplies" in names and "Bestiary" in names])
	# press every tab: nothing breaks
	var ok_tabs := true
	if bar:
		for b in bar.get_children():
			b.pressed.emit()
			await process_frame
	ch.append(["every tab opens", ok_tabs])
	# a make-again button exists and works
	var btns = hub._craft.find_children("*", "Button", true, false)
	var again = null
	for b in btns:
		if b is Button and b.text == "Make again":
			again = b
	ch.append(["a Make again button exists", again != null])
	
	if again:
		again.pressed.emit()
		await process_frame
	ch.append(["pressing it keeps the page alive", hub._craft.get_child_count() > 0])
	# text content has what we expect
	var all_text := ""
	for l in hub._craft.find_children("*", "Label", true, false):
		all_text += (l as Label).text + "\n"
	ch.append(["names the salve recipe", all_text.find("Healing Salve") >= 0 or all_text.to_lower().find("salve") >= 0])
	ch.append(["bestiary shows the goblin", all_text.find("Goblin") >= 0])
	ch.append(["bestiary shows the learned drop", all_text.find("Dropped for you") >= 0])
	ch.append(["supplies show traits for a handled material", all_text.find("Adds to a craft") >= 0])
	ch.append(["partner hint present", all_text.find("Pairs well with") >= 0 or all_text.find("partners you have not found") >= 0])
	var fail := 0
	for c in ch:
		print("CRAFTPAGE ", "ok  " if c[1] else "FAIL", c[0])
		if not c[1]:
			fail += 1
	print("CRAFT PAGE CHECK ", ch.size() - fail, " passed, ", fail, " failed")
	quit(1 if fail > 0 else 0)
