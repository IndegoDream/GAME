extends SceneTree

func _initialize() -> void:
	await process_frame
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		print("CHECK 0 passed, 1 failed")
		quit()
		return

	var json_file := FileAccess.open("res://data/factions.json", FileAccess.READ)
	if json_file == null:
		print("CHECK 0 passed, 1 failed")
		quit()
		return

	var text := json_file.get_as_text()
	json_file.close()

	var parse_result = JSON.parse_string(text)
	if typeof(parse_result) != TYPE_DICTIONARY:
		print("CHECK 0 passed, 1 failed - Invalid JSON")
		quit()
		return

	var factions: Dictionary = parse_result.get("factions", {})
	var passed: int = 0
	var total: int = 0

	for f_id in ["eliet", "deepfolk", "hollow", "heirs", "sects"]:
		total += 1
		if factions.has(f_id) and factions[f_id].has("effect") and not (factions[f_id]["effect"] as Dictionary).is_empty():
			passed += 1

	print("CHECK ", passed, " passed, ", (total - passed), " failed")
	quit()
