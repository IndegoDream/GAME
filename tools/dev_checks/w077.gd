extends SceneTree

func _initialize() -> void:
	await process_frame
	var passed := 0
	var failed := 0

	var GameSystemScript = load("res://scripts/systems/GameSystem.gd")
	var options = GameSystemScript.OptionsSystem.new()
	options.reset()
	options.apply_gamepad_mappings()

	if InputMap.has_action("interact") and InputMap.has_action("attack"):
		passed += 1
	else:
		failed += 1

	var has_joy_event := false
	for ev in InputMap.action_get_events("interact"):
		if ev is InputEventJoypadButton:
			has_joy_event = true
			break

	if has_joy_event:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
