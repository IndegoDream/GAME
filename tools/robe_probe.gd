extends SceneTree
## robe/cape/sword probe: godot ... --script res://tools/robe_probe.gd -- out.png anim seek look
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var a := OS.get_cmdline_user_args()
		var anim: String = a[1] if a.size() > 1 else "idle"
		var seek: float = float(a[2]) if a.size() > 2 else 0.3
		var look: String = a[3] if a.size() > 3 else "cloth"
		var D = load("res://scripts/world/Dress.gd")
		var ge := OS.get_environment("GRIP")
		if ge != "":
			var pp := ge.split(",")
			D.HUMAN_GRIP = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
			D.HUMAN_GRIP_ROT = float(pp[3])
			D.BLADE_Z = float(pp[4])
		var AR = load("res://scripts/actors/Armour.gd")
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
		var x := -3.0
		for yaw in [float(OS.get_environment("YAW1"))]:
			var sp: Dictionary = D.spec_for("Player", "", {"robe": [0.3,0.35,0.55], "held": "sword"})
			var m = preload("res://scripts/core/Art.gd").person(sp, 1.0)
			m.rotation_degrees.y = yaw
			m.position = Vector3(x, 0, 0)
			root.add_child(m)
			D.dress(m, sp)
			AR.dress_gear(m, [{"family": "robe", "look": look, "color": [0.3,0.35,0.6]}, {"family": "cape", "look": look, "color": [0.7,0.15,0.15]}])
			var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
			if ap.has_animation(anim):
				ap.play(anim); ap.seek(seek, true)
			x += 2.0
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(-3.0, 1.1, 3.2)
		cam.look_at(Vector3(-3.0, 0.9, 0))
		cam.fov = 40
	elif f == 6:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
