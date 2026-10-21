extends SceneTree

func _initialize() -> void:
	await process_frame
	var level_script = load("res://scripts/world/Level.gd")
	if level_script == null:
		print("CHECK 0 passed, 1 failed")
		quit()
		return
	print("CHECK 1 passed, 0 failed")
	quit()
