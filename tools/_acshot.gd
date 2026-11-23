extends SceneTree
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var G = root.get_node("Game")
	var Acc = load("res://scripts/core/Access.gd")
	var Gfx = load("res://scripts/core/Gfx.gd")
	Gfx.load_settings()
	G.save_path = "user://acshot_save.json"
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	Acc.set_opt("a_text", "1.3", self)
	Acc.set_opt("a_caps", "on", self)
	hud.open_hub("System")
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ac_system.png")
	hud._hub.close_hub()
	Acc.set_opt("a_cb", "deut", self)
	Acc.caption("windup", Vector3(5, 0, 0))
	Acc.caption("hurt")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ac_cb.png")
	Gfx.settings["touch"] = "on"
	Acc.set_opt("a_hand", "left", self)
	Acc.set_opt("a_text", "1.0", self)
	Acc.set_opt("a_cb", "off", self)
	load("res://scripts/ui/TouchUI.gd").sync(self)
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out + "/ac_touch.png")
	for k in Acc.ORDER:
		Acc.set_opt(k, Acc.DEFAULTS[k])
	Gfx.settings["touch"] = "auto"
	Gfx.save_settings()
	quit()
