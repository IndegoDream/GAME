extends SceneTree
## 2026-10-31: is the pack's Kit alive at each step? args: big|small
func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	if a.size() > 0 and a[0] == "big":
		root.size = Vector2i(1280, 720)
	var G = root.get_node("Game")
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	print("MODE ", a, " viewport ", root.get_visible_rect().size)
	print("kit valid after add: ", is_instance_valid(hud._kit), " inv valid ", is_instance_valid(hud._inventory))
	for i in 20: await process_frame
	print("kit valid after 20 frames: ", is_instance_valid(hud._kit))
	hud._hub.show_page("Pack")
	print("kit valid right after show_page: ", is_instance_valid(hud._kit))
	for n in [1, 1, 3, 10, 20]:
		for i in n: await process_frame
		print("  +", n, " frames: kit ", is_instance_valid(hud._kit), " inventory ", is_instance_valid(hud._inventory))
	print("KIT PROBE DONE")
	quit(0)
