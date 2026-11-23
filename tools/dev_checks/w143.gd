extends SceneTree

func _initialize() -> void:
	await process_frame
	var gs_script = load("res://scripts/systems/GameSystem.gd")
	if gs_script == null:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	var gs = gs_script.new()
	var game = root.get_node_or_null("Game")
	if game != null:
		gs.setup(game)
	if gs.has_method("load_texture_and_music_settings"):
		var res: Dictionary = gs.load_texture_and_music_settings()
		if res is Dictionary and res.has("texture_settings") and res.has("music_settings"):
			print("CHECK 1 passed, 0 failed")
			quit()
			return
	print("CHECK 0 passed, 1 failed")
	quit()
