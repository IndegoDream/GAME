extends SceneTree
## Round 166: the pad's quick layer -- hold Back, the face buttons are quick arts 1-4; a bare tap of Back is still the bag.
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _btn(i: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = i
	e.pressed = down
	Input.parse_input_event(e)
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var spy: Node = load("res://tools/pad_spy.gd").new()
	root.add_child(spy)
	# before: the face buttons are the usual
	_btn(JOY_BUTTON_A, true)
	await process_frame
	check("A jumps", Input.is_action_pressed("jump") and not Input.is_action_pressed("quick1"))
	_btn(JOY_BUTTON_A, false)
	await process_frame
	# the layer
	_btn(JOY_BUTTON_BACK, true)
	await process_frame
	check("layer on", G.pad_layer)
	for pair in [[JOY_BUTTON_A, "quick1", "jump"], [JOY_BUTTON_B, "quick2", "wind_step"], [JOY_BUTTON_X, "quick3", "attack"], [JOY_BUTTON_Y, "quick4", "interact"]]:
		_btn(pair[0], true)
		await process_frame
		check("%s is %s with Back held" % [pair[0], pair[1]], Input.is_action_pressed(pair[1]) and not Input.is_action_pressed(pair[2]))
		_btn(pair[0], false)
		await process_frame
		check("and lets go", not Input.is_action_pressed(pair[1]))
	var bag0: bool = false
	_btn(JOY_BUTTON_BACK, false)
	await process_frame
	check("layer off", not G.pad_layer)
	await process_frame
	await process_frame
	check("a used layer does not open the bag", spy.got == 0)
	# back to normal
	_btn(JOY_BUTTON_X, true)
	await process_frame
	check("X attacks again", Input.is_action_pressed("attack") and not Input.is_action_pressed("quick3"))
	_btn(JOY_BUTTON_X, false)
	await process_frame
	# a bare tap of Back is the bag
	_btn(JOY_BUTTON_BACK, true)
	await process_frame
	_btn(JOY_BUTTON_BACK, false)
	for i in 4:
		await process_frame
	check("a bare tap opens the bag", spy.got == 1)
	check("the tap lets go", not Input.is_action_pressed("inventory"))
	# the mapping is whole after many layers
	for i in 5:
		_btn(JOY_BUTTON_BACK, true)
		await process_frame
		_btn(JOY_BUTTON_BACK, false)
		await process_frame
	var n := 0
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:
			n += 1
	check("jump has exactly one pad A", n == 1)
	var q := 0
	for ev in InputMap.action_get_events("quick1"):
		if ev is InputEventJoypadButton:
			q += 1
	check("quick1 has no stray pad button when the layer is off", q == 0)
	print("pad_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
