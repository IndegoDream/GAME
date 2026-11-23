extends SceneTree
## with a big bag, is the Use/Wear button for a tapped item on screen? godot --path . --resolution 1280x720 --script res://tools/pack_action_probe.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var n := 0
	for id in G.items.keys():
		G.add_item(id, 3, false)
		n += 1
		if n >= 120:
			break
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	hub.show_page("Pack")
	for i in 30:
		await process_frame
	var kit = hud._kit
	var pg: Control = hub.pages["Pack"]
	var slots: Array = pg.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and (b as Button).icon != null and b.size.x > 40)
	print("slots visible: ", slots.size())
	var last = slots[slots.size() - 1] as Button
	kit._pick_slot("healing_salve" if G.count("healing_salve") > 0 else str(G.items.keys()[0]))
	for i in 20:
		await process_frame
	var vis: Rect2 = root.get_visible_rect()
	for b in pg.find_children("*", "Button", true, false):
		var bb := b as Button
		if bb.is_visible_in_tree() and bb.text in ["Use", "Wear", "Take off", "Bench", "Absorb", "Study"]:
			print("action button '", bb.text, "' rect=", bb.get_global_rect(), " on screen=", vis.encloses(bb.get_global_rect()))
	print("done")
	quit()
