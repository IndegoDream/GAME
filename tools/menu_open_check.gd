extends SceneTree
## Round 119: open every menu page and report its tabs. godot --headless --path . --script tools/menu_open_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var hud = root.get_tree().get_first_node_in_group("hud")
	print("MENU HUD ", hud != null)
	if hud == null or hud._hub == null:
		quit(1)
		return
	var hub = hud._hub
	for sec in hub.ORDER:
		hub.show_page(sec)
		await process_frame
		var box = {"Party": hub._party, "Road": hub._road, "Quests": hub._quests, "Mind": hub._mind, "Spirit": hub._spirit, "World": hub._world, "Journal": hud._jr_body}.get(sec, null)
		var tabs := []
		if box:
			var bar = box.get_node_or_null("PageTabs")
			if bar:
				for b in bar.get_children():
					tabs.append(b.text)
		print("MENU PAGE %s tabs=%s" % [sec, tabs])
	hub.close_hub()
	print("MENU OPEN DONE")
	quit()
