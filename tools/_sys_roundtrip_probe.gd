extends SceneTree
## Which system's state changes across save + load?  (a copy of a real save, or a fresh game)
##   godot --headless --path . --script res://tools/_sys_roundtrip_probe.gd [-- /abs/save.json]
func _diff(a, b, path: String, out: Array) -> void:
	if typeof(a) != typeof(b):
		out.append("%s: %s -> %s" % [path, str(a).left(80), str(b).left(80)])
		return
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s.%s: lost (was %s)" % [path, k, str(a[k]).left(80)])
			else:
				_diff(a[k], b[k], path + "." + str(k), out)
		for k in b:
			if not a.has(k):
				out.append("%s.%s: appeared (%s)" % [path, k, str(b[k]).left(80)])
	elif a is Array:
		if a.size() != b.size():
			out.append("%s: %d items -> %d" % [path, a.size(), b.size()])
		else:
			for i in a.size():
				_diff(a[i], b[i], "%s[%d]" % [path, i], out)
	elif a is float and b is float:
		if absf(a - b) > 1e-6 * maxf(1.0, absf(a)):
			out.append("%s: %s -> %s" % [path, str(a), str(b)])
	elif a != b:
		out.append("%s: %s -> %s" % [path, str(a).left(80), str(b).left(80)])


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var args := OS.get_cmdline_user_args()
	G.playlog_path = "user://tool_playlog.jsonl"
	if args.size() > 0:
		G.save_path = args[0]
		G.save_base = "user://rt_probe_slots"
		G.load_game()
	else:
		G.save_path = "user://rt_probe_save.json"
		G.save_base = "user://rt_probe_slots"
		G.new_game()
		G.realm = 3
		G.sys("research").researched["second_thread"] = true
		G.sys("mind").set_share("research", 0.5)
	G.save_game()
	var st0 = JSON.parse_string(JSON.stringify(G._systems_save()))
	G._systems_reset()
	G.load_game()
	var st1 = JSON.parse_string(JSON.stringify(G._systems_save()))
	var out := []
	_diff(st0, st1, "systems", out)
	print("ROUNDTRIP differences: ", out.size())
	for l in out.slice(0, 40):
		print("  ", l)
	quit()
