extends SceneTree

func _initialize() -> void:
	await process_frame
	var game = root.get_node_or_null("Game")
	if game and game.has_method("sys"):
		var factions = game.sys("factions")
		if factions and factions.has_method("define_faction_effects"):
			var ef: Dictionary = factions.define_faction_effects()
			if ef.size() > 0:
				print("CHECK 1 passed, 0 failed")
				quit()
				return
	print("CHECK 0 passed, 1 failed")
	quit()
