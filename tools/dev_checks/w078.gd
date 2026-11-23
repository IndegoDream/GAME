extends SceneTree

func _initialize() -> void:
	var GameSystemScript: GDScript = load("res://scripts/systems/GameSystem.gd")
	var options: Object = GameSystemScript.OptionsSystem.new()
	options.reset()
	assert(options.phone_layout_one_handed == false)
	options.set_phone_layout_one_handed(true, "left")
	assert(options.phone_layout_one_handed == true)
	assert(options.phone_layout_hand == "left")
	var offsets: Dictionary = options.get_one_handed_offsets()
	assert(offsets.get("align_side") == "left")
	options.toggle_one_handed_layout()
	assert(options.phone_layout_one_handed == false)
	print("CHECK 1 passed, 0 failed")
	quit()
