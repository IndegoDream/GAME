extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var L = load("res://scripts/ui/Loading.gd").new()
		root.add_child(L)
		L.show_for("The Mossy Halls")
	elif f == 8:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
