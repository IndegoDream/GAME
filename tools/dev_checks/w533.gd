extends SceneTree

func _initialize() -> void:
	await process_frame
	var root: Node = get_root()
	var game: Node = root.get_node_or_null("Game")
	var passed: int = 0
	var failed: int = 0
	
	if game != null:
		passed += 1
	else:
		failed += 1
		
	if root != null:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
