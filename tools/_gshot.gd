extends SceneTree
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	G.save_path = "user://gshot_save.json"
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	hub.show_page("Swarm")
	hub.start_lesson("nanites")
	hub._tour_go(2)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out + "/gs_swarm.png")
	hub.show_page("Guide")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/gs_guide.png")
	hub.end_lesson()
	hub.show_page("Meridians")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/gs_mer.png")
	quit()
