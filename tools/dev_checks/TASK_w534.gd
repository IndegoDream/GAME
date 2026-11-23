extends SceneTree

func _initialize() -> void:
	await process_frame
	var root: Window = get_root()
	var game: Node = root.get_node_or_null("Game")
	var passed: int = 0
	var failed: int = 0
	
	if game != null:
		var reaches: Node = game.get_node_or_null("Reaches")
		if reaches != null and reaches.has_method("fix_floor_reach"):
			passed += 1
		else:
			failed += 1
	else:
		failed += 1
		
	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
