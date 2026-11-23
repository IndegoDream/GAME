extends SceneTree

func _initialize() -> void:
	var passed := 0
	var failed := 0

	var game_system_script = load("res://scripts/systems/GameSystem.gd")
	var opts = game_system_script.OptionsSystem.new()
	opts.reset()
	if abs(opts.text_size - 1.0) < 0.001:
		passed += 1
	else:
		failed += 1

	opts.set_text_size(1.5)
	if abs(opts.text_size - 1.5) < 0.001:
		passed += 1
	else:
		failed += 1

	opts.adjust_text_size(0.2)
	if abs(opts.text_size - 1.7) < 0.001:
		passed += 1
	else:
		failed += 1

	var state = opts.save_state()
	if abs(float(state.get("text_size", 0.0)) - 1.7) < 0.001:
		passed += 1
	else:
		failed += 1

	opts.reset()
	opts.load_state(state)
	if abs(opts.text_size - 1.7) < 0.001:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
