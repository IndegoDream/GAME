extends SceneTree
## screenshots of the menu pages. godot --rendering-driver opengl3 --path . --script res://tools/menu_shot.gd -- <out_dir> [pages comma list]
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://shots"
	var only: Array = (a[1] as String).split(",") if a.size() > 1 else []
	var G = root.get_node("Game")
	if a.size() > 2:
		load("res://scripts/core/I18n.gd").set_language(a[2])
	G.new_game()
	for id in ["spirit_herb", "iron_ore", "healing_salve", "venom_coating", "iron_sword", "goblin_tooth", "qi_pill", "bone_shard", "silver_ore", "rough_jade", "antidote"]:
		G.add_item(id, 3, false)
	G.sys("dao").sense = 120.0
	G.sys("dao").pts["blade"] = 140.0
	G.sys("dao").focus = "blade"
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	for sec in hub.ORDER:
		if not only.is_empty() and not (sec in only):
			continue
		hub.show_page(sec)
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("%s/menu_%s.png" % [out, sec])
	quit()
