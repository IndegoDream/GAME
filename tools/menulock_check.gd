extends SceneTree
func _initialize() -> void:
	var ok := 0
	var bad := 0
	var M: Script = load("res://Main.gd")
	var m: Node3D = M.new()
	var a := Node3D.new(); var b := Node3D.new(); var pl := Node3D.new()
	m.add_child(a); m.add_child(b)
	m.player = null
	m.set_world_frozen(true)
	for n in [a, b]:
		if n.process_mode == Node.PROCESS_MODE_DISABLED: ok += 1
		else: bad += 1
	m.set_world_frozen(false)
	for n in [a, b]:
		if n.process_mode == Node.PROCESS_MODE_INHERIT and not n.has_meta("menu_frozen"): ok += 1
		else: bad += 1
	print("MENULOCK CHECK %d passed, %d failed" % [ok, bad])
	quit(bad)
