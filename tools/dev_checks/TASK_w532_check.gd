extends SceneTree

func _initialize() -> void:
	await root.process_frame
	var game_node: Node = root.get_node_or_null("Game")
	if game_node:
		print("CHECK 1 passed, 0 failed")
	else:
		print("CHECK 0 passed, 1 failed")
	quit()
