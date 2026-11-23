extends SceneTree

func _initialize() -> void:
	await process_frame
	var file := FileAccess.open("res://data/world.json", FileAccess.READ)
	if not file:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	var text := file.get_as_text()
	file.close()
	var json: Variant = JSON.parse_string(text)
	if not json or not json is Dictionary:
		print("CHECK 0 passed, 1 failed")
		quit()
		return

	var floor6: Dictionary = json.get("floor6", {})
	var secret_wall: Dictionary = floor6.get("secret_wall", {})
	if secret_wall.get("accessible_from_arrival", false) == true:
		print("CHECK 1 passed, 0 failed")
	else:
		print("CHECK 0 passed, 1 failed")
	quit()
