extends SceneTree

func _initialize() -> void:
	await process_frame
	var passed: int = 0
	var failed: int = 0

	var chest_script = load("res://scripts/objects/Chest.gd")
	if chest_script != null:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
