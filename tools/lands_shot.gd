extends SceneTree
## Build a Land and screenshot it from the ground. godot --path . --resolution 1280x720 --script res://tools/lands_shot.gd -- whisperwood
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var rid: String = args[0] if args.size() > 0 else "whisperwood"
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	await process_frame
	var def: Dictionary = G.load_level_def("frontier:" + rid)
	var lv = load("res://scripts/world/Level.gd").new()
	lv.name = "Level"
	lv.build(def)
	root.add_child(lv)
	var pl = load("res://scripts/actors/Player.gd").new()
	root.add_child(pl)
	pl.global_position = lv.cell_to_world(lv.spawns["P"][0]) + Vector3(0, 1, 0)
	for i in 90: await process_frame
	print("LANDSHOT ", rid, " counts=", lv.counts)
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	root.get_texture().get_image().save_png("/tmp/shots/land_%s.png" % rid)
	quit()
