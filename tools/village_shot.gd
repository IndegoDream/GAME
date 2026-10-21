extends SceneTree
## windowed: boot Main in the village, print what stands near the centre, take a top-down picture. Args: out.png
var f := 0
var G
var out := ""
var cam: Camera3D
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		out = OS.get_cmdline_user_args()[0]
		G = root.get_node("Game")
		G.save_path = "user://vs_save.json"
		G.save_base = "user://vs_slots"
		G.playlog_path = "user://vs_playlog.jsonl"
		root.add_child(load("res://Main.tscn").instantiate())
	elif f == 200:
		var m = root.get_node("Main")
		var lv = m.level
		print("level ", G.current_level, " stream left ", lv.stream_left())
		var pl = m.player
		var c: Vector3 = pl.global_position
		print("player at ", c)
		var counts := {}
		var stack := [lv]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for ch in n.get_children():
				stack.append(ch)
				if ch is Node3D and ch.global_position.distance_to(c) < 14.0 and not (ch is Camera3D) and ch.get_child_count() >= 0:
					var key := ch.get_class() + ":" + String(ch.name).rstrip("0123456789@")
					counts[key] = int(counts.get(key, 0)) + 1
		var ks := counts.keys()
		ks.sort()
		for k in ks:
			print("  ", k, " x", counts[k])
		cam = Camera3D.new()
		root.add_child(cam)
		cam.global_position = c + Vector3(0, 34, 0.1)
		cam.look_at(c, Vector3.UP)
		cam.current = true
		pl.visible = true
	elif f == 215:
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
	return false
