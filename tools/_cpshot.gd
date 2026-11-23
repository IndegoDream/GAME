extends SceneTree
func _cb(s: float) -> void:
	pass
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	G.save_path = "user://cpshot_save.json"
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	for kind in ["hammer", "simmer", "pour", "facet", "trace"]:
		hud.open_craftplay(kind, "smithing", 0, _cb)
		for i in 5:
			await process_frame
		var ui = hud._play
		ui._process(1.0)
		ui._process(0.35)
		if kind == "pour":
			ui._press()
			ui._process(0.5)
		if kind == "simmer":
			ui._holding = true
			ui._process(1.5)
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + "/cp_" + kind + ".png")
		ui._do_skip()
	hud.open_hub("Craft")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out + "/cp_craft.png")
	quit()
