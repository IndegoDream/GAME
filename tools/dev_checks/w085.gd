extends SceneTree

func _initialize() -> void:
	await process_frame
	var passed: int = 0
	var failed: int = 0

	var level_script = load("res://scripts/world/Level.gd")
	if level_script != null:
		var level = level_script.new()
		if level.has_method("check_secret_wall"):
			passed += 1
			level.spawns["S"] = [Vector2i(5, 5)]
			if level.check_secret_wall():
				passed += 1
			else:
				failed += 1
			if level.check_secret_wall(Vector2i(5, 5)):
				passed += 1
			else:
				failed += 1
			if not level.check_secret_wall(Vector2i(0, 0)):
				passed += 1
			else:
				failed += 1
			level.free()
		else:
			failed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
