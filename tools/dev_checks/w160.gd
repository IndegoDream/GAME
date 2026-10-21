extends SceneTree

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var mind = G.sys("mind")

	var passed := 0
	var failed := 0

	# Test 1: Initial state
	if mind.mental_state == "focused" and mind.clarity == 100.0:
		passed += 1
	else:
		failed += 1

	# Test 2: State transition down
	mind.update_mental_state(-30.0, "Combat stress")
	if mind.mental_state == "focused" and mind.clarity == 70.0:
		passed += 1
	else:
		failed += 1

	mind.update_mental_state(-30.0, "Heavy damage")
	if mind.mental_state == "agitated" and mind.clarity == 40.0:
		passed += 1
	else:
		failed += 1

	# Test 3: Decision modifier
	if absf(mind.get_decision_modifier() - 0.85) < 0.01:
		passed += 1
	else:
		failed += 1

	# Test 4: Save and Load
	var saved = mind.save_state()
	mind.reset()
	mind.load_state(saved)
	if mind.mental_state == "agitated" and mind.clarity == 40.0 and mind.state_history.size() == 2:
		passed += 1
	else:
		failed += 1

	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
