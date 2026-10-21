extends SceneTree
## screenshots of the menu pages. godot --rendering-driver opengl3 --path . --script res://tools/menu_shot.gd -- <out_dir> [pages comma list]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://shots"
	var only: Array = (a[1] as String).split(",") if a.size() > 1 else []
	var G = root.get_node("Game")
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	for sec in hub.ORDER:
		if not only.is_empty() and not (sec in only):
			continue
		hub.show_page(sec)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/menu_%s.png" % [out, sec])
	quit()
