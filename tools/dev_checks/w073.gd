extends SceneTree

func _initialize() -> void:
	await process_frame
	var game = root.get_node_or_null("Game")
	var passed: int = 0
	var failed: int = 0

	var OptionsClass = load("res://scripts/systems/GameSystem.gd").OptionsSystem
	var sys = OptionsClass.new()
	sys.setup(game)
	sys.reset()

	if sys.id == "options":
		passed += 1
	else:
		failed += 1

	if sys.colorblind_palette == "None" and sys.text_size == 1.0:
		passed += 1
	else:
		failed += 1

	sys.colorblind_palette = "Deuteranopia"
	sys.text_size = 1.25
	sys.music_volume = 0.5
	sys.sfx_volume = 0.6
	sys.phone_layout_one_handed = true
	sys.subtitles_enabled = true
	sys.sound_captions = true
	sys.gamepad_enabled = true
	sys.keybindings["interact"] = KEY_F

	var saved: Dictionary = sys.save_state()
	if saved.get("colorblind_palette") == "Deuteranopia" and saved.get("music_volume") == 0.5:
		passed += 1
	else:
		failed += 1

	var sys2 = OptionsClass.new()
	sys2.setup(game)
	sys2.load_state(saved)

	if sys2.colorblind_palette == "Deuteranopia" and sys2.text_size == 1.25 and sys2.phone_layout_one_handed == true and sys2.keybindings.get("interact") == KEY_F:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
