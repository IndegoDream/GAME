extends SceneTree

func _initialize() -> void:
	await process_frame
	var file := FileAccess.open("res://data/performance_settings.json", FileAccess.READ)
	if not file:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	var data: Dictionary = json.get_data()
	if data.has("tiers") and data["tiers"].has("low") and data["tiers"].has("medium") and data["tiers"].has("high"):
		print("CHECK 1 passed, 0 failed")
	else:
		print("CHECK 0 passed, 1 failed")
	quit()
