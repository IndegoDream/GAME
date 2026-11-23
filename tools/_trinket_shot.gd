extends SceneTree
## round 183b: the four Familiar Trinkets on a wolf (env STAGE=0..3)
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.12, 0.13, 0.16)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.55, 0.55, 0.6)
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, 35, 0)
		root.add_child(sun)
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/looks.json"))
		var items: Dictionary = d["packs"]["trinkets_pack"]["items"]
		var stage := int(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else 1
		var i := 0
		for k in items:
			var b = load("res://scripts/actors/Beast.gd").build("Wolf", Color(0.55, 0.5, 0.45))
			b.evolve(stage, Color(0.8, 0.9, 1.0))
			var ok: bool = b.trinket(items[k])
			print(k, " trinket ", ok)
			b.scale = Vector3.ONE * 2.0 * [1.0, 1.3, 1.6, 1.9][stage]
			b.position = Vector3(-4.5 + 3.0 * i, 0, 0)
			b.rotation_degrees.y = 120
			root.add_child(b)
			i += 1
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 3.0, 7.5) if OS.get_environment("CLOSE") == "" else Vector3(-1.5, 1.6, 2.6)
		if OS.get_environment("CLOSE") != "":
			cam.position = Vector3(-4.5 + 3.0 * int(OS.get_environment("CLOSE")) + 1.2, 1.5, 2.2)
		cam.look_at(Vector3(0, 0.9, 0) if OS.get_environment("CLOSE") == "" else Vector3(-4.5 + 3.0 * int(OS.get_environment("CLOSE")) + 0.4, 0.9, 0))
		cam.fov = 55
	if f == 8:
		var img := root.get_viewport().get_texture().get_image()
		var out := "/tmp/trinkets.png"
		for a in OS.get_cmdline_user_args():
			out = a
		img.save_png(out)
		quit()
	return false
