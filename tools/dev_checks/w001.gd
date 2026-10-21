extends SceneTree

func _initialize() -> void:
	await process_frame
	var ws_script = load("res://scripts/objects/Waystone.gd")
	var ws = ws_script.new()
	root.add_child(ws)
	var glow = ws.get_node_or_null("GroundGlow")
	var pass_count := 0
	var fail_count := 0
	if glow != null and glow is MeshInstance3D:
		pass_count += 1
	else:
		fail_count += 1
	ws.queue_free()
	print("CHECK %d passed, %d failed" % [pass_count, fail_count])
	quit()
