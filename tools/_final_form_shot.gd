extends SceneTree
## 2026-11-06: the spirit beast (final form) across kinds and roles, for judging the look.
##   godot --path . --script res://tools/_final_form_shot.gd -- out.png [stage]
var f := 0
const SET := [
	["wolf", "striker", Color(0.45, 0.42, 0.4), Color(0.4, 0.75, 1.0)],
	["fox", "tracker", Color(0.75, 0.42, 0.2), Color(1.0, 0.55, 0.2)],
	["stag", "lantern", Color(0.55, 0.4, 0.28), Color(0.7, 1.0, 0.75)],
	["boar", "guardian", Color(0.35, 0.28, 0.24), Color(1.0, 0.8, 0.35)],
	["salamander", "ember", Color(0.5, 0.2, 0.15), Color(1.0, 0.4, 0.15)],
	["crow", "courier", Color(0.18, 0.18, 0.22), Color(0.75, 0.55, 1.0)],
]


const SET_B := [
	["cave toad", "guardian", Color(0.35, 0.45, 0.25), Color(0.6, 1.0, 0.5)],
	["stone crab", "digger", Color(0.55, 0.3, 0.25), Color(0.4, 0.9, 1.0)],
	["glow worm", "lantern", Color(0.7, 0.6, 0.45), Color(1.0, 0.85, 0.4)],
	["iron golem", "sentinel", Color(0.45, 0.45, 0.5), Color(1.0, 0.45, 0.2)],
	["tunnel boar", "fury", Color(0.4, 0.3, 0.25), Color(1.0, 0.3, 0.25)],
	["cave hare", "lucky", Color(0.75, 0.7, 0.62), Color(0.5, 1.0, 0.7)],
]


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var a := OS.get_cmdline_user_args()
		var stage: int = int(a[1]) if a.size() > 1 else 3
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.32, 0.38, 0.45)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.55, 0.58, 0.62)
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.glow_enabled = true
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, 35, 0)
		sun.shadow_enabled = true
		root.add_child(sun)
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(30, 30)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.3, 0.36, 0.24)
		ground.material_override = gm
		root.add_child(ground)
		var only: int = int(a[2]) if a.size() > 2 else -1
		var set_: Array = SET if OS.get_environment("SET") != "b" else SET_B
		for i in set_.size():
			if only >= 0 and i != only:
				continue
			var s: Array = set_[i]
			var b = load("res://scripts/actors/Beast.gd").build(str(s[0]), s[2])
			b.evolve(stage, s[3])
			b.role_form(str(s[1]), stage, s[3])
			if OS.get_environment("BARDING") != "":
				b.barding(OS.get_environment("BARDING"), stage)
			b.scale = Vector3.ONE * 2.0 * [1.0, 1.3, 1.6, 1.9][stage]
			b.position = Vector3(-3.4 + 3.4 * float(i % 3), 0, -2.6 + 3.2 * float(i / 3)) if only < 0 else Vector3.ZERO
			b.rotation_degrees.y = 120
			root.add_child(b)
			b.set_motion_stage(stage)
			for k in 30:
				b.animate(1.0 / 60.0)
			if OS.get_environment("CLOSE") != "" and only >= 0:
				set_meta("focus", b._head.global_position if b._head else b.global_position)
				set_meta("fwd", b.global_transform.basis.z.normalized())
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 5.5, 9.0) if only < 0 else (Vector3(0.4, 2.2, 3.8) if OS.get_environment("CLOSE") == "" else Vector3(1.6, 1.4, 1.6))
		cam.look_at(Vector3(0, 0.9, -0.6) if only < 0 else (Vector3(0, 1.0, 0) if OS.get_environment("CLOSE") == "" else Vector3(0.0, 1.0, 0.5)))
		cam.fov = 50
		if has_meta("focus"):
			var fc: Vector3 = get_meta("focus")
			var fw: Vector3 = get_meta("fwd")
			cam.position = fc + fw * 1.1 + fw.cross(Vector3.UP).normalized() * 0.9 + Vector3(0, 0.25, 0)
			cam.look_at(fc - fw * 0.15)
			cam.fov = 40
	elif f == 8:
		root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		quit()
	return false
