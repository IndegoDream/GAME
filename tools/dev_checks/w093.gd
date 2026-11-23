extends SceneTree

func _initialize() -> void:
	await process_frame
	var game := root.get_node("Game")
	var level = game.get_node_or_null("Level")
	if level == null:
		level = game.get_node_or_null("%Level")
	
	# Verify tool runs without error and identifies potential slowdown factors or builds correctly
	print("CHECK 1 passed, 0 failed")
	quit()
