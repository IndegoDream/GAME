extends SceneTree
## grip candidates: godot --script res://tools/grip_test.gd -- out.png [anim] [kind]
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var a := OS.get_cmdline_user_args()
		var anim: String = a[1] if a.size() > 1 else "idle"
		var kind: String = a[2] if a.size() > 2 else "sword"
		var D = load("res://scripts/world/Dress.gd")
		var ge := OS.get_environment("GRIP")
		if ge != "":
			var pp := ge.split(",")
			D.HUMAN_GRIP = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			D.HUMAN_GRIP_ROT = float(pp[3])
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.25, 0.27, 0.3)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.7, 0.7)
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 20, 0)
		root.add_child(sun)
		var cands := ["sword","bow","crossbow","ki","spear","axe"]
		var x := -3.0
		for c in cands:
			var m = preload("res://scripts/core/Art.gd").person(D.spec_for("Player", "", {"robe": [0.3,0.35,0.55], "held": c}), 1.0)
			m.scale = Vector3.ONE * 1.0
			m.rotation_degrees.y = float(a[3]) if a.size() > 3 else 0.0
			m.position = Vector3(x, 0, 0)
			root.add_child(m)
			D.dress(m, D.spec_for("Player", "", {"robe": [0.3,0.35,0.55], "held": c}))
			var g = m.find_child("Grip", true, false)
			var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
			if ap.has_animation(anim):
				ap.play(anim); ap.seek(0.3, true)
			x += 1.2
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 1.0, 3.6)
		cam.look_at(Vector3(0, 0.9, 0))
		cam.fov = 42
		print("style ", preload("res://scripts/core/Art.gd").style)
	elif f == 30:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
