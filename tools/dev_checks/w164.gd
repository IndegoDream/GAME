extends SceneTree

func _initialize() -> void:
	await process_frame
	var passed := 0
	var failed := 0
	var game = root.get_node_or_null("Game")
	if not game:
		print("CHECK 0 passed, 1 failed")
		quit()
		return

	var factions = game.sys("factions")
	if factions and factions.has_method("apply_faction_effects"):
		passed += 1
		var applied = factions.apply_faction_effects()
		if applied is Dictionary:
			passed += 1
		else:
			failed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
