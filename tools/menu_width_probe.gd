extends SceneTree
## which controls force a menu page wider than the screen? godot --path . --resolution 844x390 --script res://tools/menu_width_probe.gd -- [pages]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var only: Array = (a[0] as String).split(",") if a.size() > 0 else []
	var G = root.get_node("Game")
	G.new_game()
	for id in ["spirit_herb", "iron_ore", "healing_salve", "iron_sword", "qi_pill"]:
		G.add_item(id, 3, false)
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	var vw: float = root.get_visible_rect().size.x
	print("viewport ", root.get_visible_rect().size, " holder ", hub.holder.size)
	for sec in hub.ORDER:
		if not only.is_empty() and not (sec in only):
			continue
		hub.show_page(sec)
		for i in 14:
			await process_frame
		var pg: Control = hub.pages[sec]
		var lim: float = hub.holder.size.x
		var bad: Array = []
		for n in pg.find_children("*", "Control", true, false):
			var c := n as Control
			if c.is_visible_in_tree() and c.get_combined_minimum_size().x > lim + 2.0:
				var kids: Array = c.get_children().map(func(k): return k.get_class() + ((":" + (k as Button).text.left(10)) if k is Button else ""))
				bad.append("%s min=%d parent=%s kids=%s" % [c.get_class(), int(c.get_combined_minimum_size().x), c.get_parent().get_class(), str(kids).left(160)])
		var right: float = 0.0
		for n in pg.find_children("*", "Control", true, false):
			var c := n as Control
			if c.is_visible_in_tree():
				right = maxf(right, c.global_position.x + c.size.x)
		print("PAGE ", sec, " bad=", bad.size(), " rightmost=", int(right), " of ", int(vw))
		for i in mini(bad.size(), 14):
			print("   ", bad[i])
	quit()
