extends SceneTree

func _initialize() -> void:
	await process_frame
	var file := FileAccess.open("res://data/skills.json", FileAccess.READ)
	if not file:
		print("CHECK 1 failed: Could not open skills.json")
		quit(1)
		return
	
	var json_text := file.get_as_text()
	var json = JSON.parse_string(json_text)
	if json == null:
		print("CHECK 1 failed: Failed to parse skills.json")
		quit(1)
		return
		
	if not json.has("tailored_paths"):
		print("CHECK 1 failed: Missing tailored_paths in skills.json")
		quit(1)
		return
		
	print("CHECK 1 passed, 0 failed")
	quit(0)
