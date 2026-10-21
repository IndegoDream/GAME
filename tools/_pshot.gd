extends SceneTree
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	G.save_path = "user://pshot_save.json"
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	hub.show_page("Path")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ps_choose.png")
	var P = G.sys("paths")
	G.realm = 3
	P.choose("ranger")
	P.ranks["ranger"] = 3
	P.prog["ranger"] = {"shots": 450, "kills": 130, "charged": 50}
	P.choose("duelist", true)
	hub.show_page("Path")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ps_walk.png")
	hub.start_lesson("paths")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ps_tour.png")
	quit()
