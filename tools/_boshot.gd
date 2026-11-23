extends SceneTree
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	G.save_path = "user://boshot_save.json"
	G.new_game()
	G.current_level = "village"
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var BO = G.sys("boons")
	BO.pick("boon", str(BO.boon_offers()[0]))
	hud.open_hub("Road")
	for i in 14:
		await process_frame
	root.get_texture().get_image().save_png(out + "/bo_road.png")
	hud._hub._scroll_to_heading("Today") if hud._hub.has_method("_scroll_to_heading") else null
	quit()
