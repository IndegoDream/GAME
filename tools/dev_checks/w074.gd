extends SceneTree

func _initialize() -> void:
	await process_frame
	var file := FileAccess.open("res://data/ui.json", FileAccess.READ)
	if not file:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	
	var data: Dictionary = json.data
	if not data.has("color_blind_palettes"):
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	
	var palettes: Dictionary = data["color_blind_palettes"]
	var expected := ["default", "protanopia", "deuteranopia", "tritanopia"]
	var passed := 0
	for key in expected:
		if palettes.has(key) and palettes[key].has("name") and palettes[key].has("gold"):
			passed += 1
	
	if passed == expected.size():
		print("CHECK 1 passed, 0 failed")
	else:
		print("CHECK 0 passed, 1 failed")
	quit()
