extends SceneTree
## Bench tab + list view at any size: every button must sit inside the tab's width. godot --path . --resolution WxH --script res://tools/bench_probe.gd -- tag
var G
func shot(tag: String) -> void:
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	img.save_png("/tmp/shots/%s.png" % tag)
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() > 0 else "x"
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	await process_frame
	var n := 0
	for id in G.items.keys():
		var ty := str(G.item_def(id).get("type", ""))
		if ty in ["consumable", "material", "weapon", "armor"]:
			G.add_item(id, 3, false); n += 1
		if n >= 90: break
	G.counters["bag_view"] = 1.0
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20: await process_frame
	for tabname in ["Pack", "Bench"]:
		hud.open_kit(tabname, "home")
		for i in 30: await process_frame
		var kit = hud._kit
		var tab: Control = null
		for c in kit.tabs.get_children():
			if c.name == tabname: tab = c
		var tr: Rect2 = kit.tabs.get_global_rect()
		var btns := 0; var out := 0
		for c in tab.find_children("*", "Button", true, false):
			var b := c as Button
			if b is OptionButton or not b.is_visible_in_tree(): continue
			btns += 1
			var r := b.get_global_rect()
			if r.end.x > tr.end.x + 2 or r.position.x < tr.position.x - 2: out += 1
		print("BENCHPROBE ", tag, " ", tabname, " viewport=", root.get_visible_rect().size, " buttons=", btns, " outside=", out)
		shot(tag + "_" + tabname)
	quit()
