extends SceneTree
## round 158: rebinding keys
var G
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _has(action: String, code: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and int((ev as InputEventKey).physical_keycode) == code:
			return true
	return false
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	var C = load("res://scripts/core/Controls.gd")
	if FileAccess.file_exists(C.PATH):
		DirAccess.remove_absolute(C.PATH)
	C.init()
	check("defaults snapshotted", C.defaults.has("quick1") and C.defaults["quick1"] == [KEY_R])
	check("every listed action exists", C.ROWS.all(func(r): return InputMap.has_action(str(r[0]))))
	var msg: String = C.bind("quick1", KEY_G)
	check("quick1 moved to G", _has("quick1", KEY_G) and not _has("quick1", KEY_R))
	check("G was flying sword's: it lost the key", not _has("flying_sword", KEY_G) and msg.contains("lost"))
	check("saved to disk", FileAccess.file_exists(C.PATH))
	C.init()
	check("survives a restart", _has("quick1", KEY_G) and not _has("flying_sword", KEY_G))
	check("is_default tells", not C.is_default("quick1") and C.is_default("jump"))
	C.reset_one("quick1")
	check("reset one", _has("quick1", KEY_R))
	C.reset_all()
	check("reset all brings G back to the sword", _has("flying_sword", KEY_G) and _has("quick1", KEY_R))
	check("mouse attack untouched", InputMap.action_get_events("attack").any(func(e): return e is InputEventMouseButton))
	DirAccess.remove_absolute(C.PATH)
	print("controls_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
