extends SceneTree
## stage preview: godot ... --script res://tools/beast_probe.gd -- out.png name r,g,b accentR,G,B
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var a := OS.get_cmdline_user_args()
		var nm: String = a[1] if a.size() > 1 else "fox"
		var tc := (a[2] if a.size() > 2 else "0.6,0.5,0.4").split(",")
		var ac := (a[3] if a.size() > 3 else "1,0.5,0.2").split(",")
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.18, 0.2, 0.24)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.6, 0.6)
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		root.add_child(sun)
		var scales := [1.0, 1.3, 1.6, 1.9]
		for i in 4:
			var b = load("res://scripts/actors/Beast.gd").build(nm, Color(float(tc[0]), float(tc[1]), float(tc[2])))
			b.evolve(i, Color(float(ac[0]), float(ac[1]), float(ac[2])))
			var rl := OS.get_environment("ROLE")                   # 2026-11-06: preview a role's own body
			if rl != "":
				b.role_form(rl, i, Color(float(ac[0]), float(ac[1]), float(ac[2])))
			var bard := OS.get_environment("BARDING")              # 2026-11-06: preview the armour too
			if bard != "":
				b.barding(bard, i)
			b.scale = Vector3.ONE * 2.0 * float(scales[i])
			b.position = Vector3(-3.6 + 2.4 * float(i), 0, 0)
			b.rotation_degrees.y = 125
			root.add_child(b)
			b.set_motion_stage(i)
			var pose := OS.get_environment("POSE")                 # 2026-11-06: down / bite / deed / walk (item 5)
			if pose in ["down", "bite", "deed"]:
				b.act(pose)
			for k in (75 if pose == "down" else (int(b.act_seconds() * 60.0 * 0.45) if pose in ["bite", "deed"] else (20 if pose == "walk" else 0))):
				if pose == "walk":
					b.global_position += Vector3(0, 0, 0.05)
				b.animate(1.0 / 60.0)
			if pose == "walk":
				b.position = Vector3(-3.6 + 2.4 * float(i), 0, 0)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 1.5, 6.8)
		cam.look_at(Vector3(0, 0.7, 0))
		cam.fov = 45
	elif f == 6:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
