extends SceneTree

func _initialize() -> void:
	await process_frame
	var root_node := root
	var GameNode := root_node.get_node_or_null("Game")
	if not GameNode:
		print("CHECK 1 failed: Game autoload not found")
		quit(1)
		return
	
	if not GameNode.has_method("_load_item_def"):
		print("CHECK 2 failed: _load_item_def method not found on Game")
		quit(1)
		return
		
	var def: Dictionary = GameNode.call("_load_item_def", "nonexistent_item_id_12345")
	if typeof(def) != TYPE_DICTIONARY:
		print("CHECK 3 failed: _load_item_def did not return a Dictionary")
		quit(1)
		return
		
	print("CHECK 1 passed, 0 failed")
	quit(0)
