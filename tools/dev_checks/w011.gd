extends SceneTree

func _initialize() -> void:
	await process_frame
	var game = root.get_node("Game")
	var pass_count := 0
	var fail_count := 0

	var has_mask := false
	for s in game.gear_slots():
		if s is Array and s.size() > 0 and s[0] == "mask":
			has_mask = true
			break

	if has_mask:
		pass_count += 1
	else:
		fail_count += 1

	if game.slot_family("mask") == "mask":
		pass_count += 1
	else:
		fail_count += 1

	if game.slots_for("mask") == ["mask"]:
		pass_count += 1
	else:
		fail_count += 1

	print("CHECK %d passed, %d failed" % [pass_count, fail_count])
	quit()
