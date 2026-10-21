extends SceneTree
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	G.save_path = "user://cmshot_save.json"
	G.new_game()
	G.current_level = "village"
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var CM = G.sys("commissions")
	var b: Array = CM.board("village")
	if b.size() > 0:
		CM.accept(str(b[0]["id"]))
	hud.open_hub("Craft")
	for i in 14:
		await process_frame
	root.get_texture().get_image().save_png(out + "/cm_craft.png")
	hud._hub.close_hub()
	var M = G.sys("menagerie")
	M.recruit("Marin Ashgrove", "Marin Ashgrove, a field medic.", "village", Color.WHITE)
	M.trust["Marin Ashgrove"] = 25.0
	hud.open_hub("Party")
	for i in 14:
		await process_frame
	root.get_texture().get_image().save_png(out + "/cm_party.png")
	quit()
