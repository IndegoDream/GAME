extends SceneTree
## windowed: boot Main, change level, grab the loading veil mid-way and the new level after
var f := 0
var G
var out := ""
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		out = OS.get_cmdline_user_args()[0]
		G = root.get_node("Game")
		G.save_path = "user://flow_save.json"
		G.save_base = "user://flow_slots"
		G.playlog_path = "user://flow_playlog.jsonl"
		root.add_child(load("res://Main.tscn").instantiate())
	elif f == 30:
		var errs := 0
		print("level now: ", G.current_level)
		G.go_to("floor1", "<")
	elif f == 33:
		root.get_viewport().get_texture().get_image().save_png(out + "_a.png")
		print("A level: ", G.current_level)
	elif f == 150:
		root.get_viewport().get_texture().get_image().save_png(out + "_b.png")
		var m = root.get_node("Main")
		var lv = m.get_node("Level")
		print("B level: ", G.current_level, " stream left: ", lv.stream_left(), " warm: ", m._warm == null)
		quit()
	return false
