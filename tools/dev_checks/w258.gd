extends SceneTree

func _initialize() -> void:
	var passed := 0
	var failed := 0

	var FloorRunScript = load("res://scripts/systems/FloorRun.gd")
	if FloorRunScript == null:
		print("CHECK 0 passed, 1 failed (FloorRun.gd not found)")
		quit()
		return

	var floor_run = FloorRunScript.new()
	if floor_run == null:
		print("CHECK 0 passed, 1 failed (FloorRun instance failed)")
		quit()
		return

	if floor_run.has_method("preload_assets"):
		passed += 1
	else:
		failed += 1

	var count: int = floor_run.preload_assets()
	if count >= 0:
		passed += 1
	else:
		failed += 1

	if "_preloaded_assets" in floor_run and floor_run._preloaded_assets is Array:
		passed += 1
	else:
		failed += 1

	floor_run.free()

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
