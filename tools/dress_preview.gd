extends SceneTree
## A lineup of dressed characters, for checking Dress.gd with your own eyes:
##   godot --path . --script res://tools/dress_preview.gd -- <out.png> [animation]
var f := 0
var out := ""
var anim := "idle"
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		out = OS.get_cmdline_user_args()[0]
		if OS.get_cmdline_user_args().size() > 1:
			anim = OS.get_cmdline_user_args()[1]
		var D = load("res://scripts/world/Dress.gd")
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
		var specs := [["Player", "", {"robe": [0.3, 0.35, 0.55], "sash": [0.8, 0.7, 0.3], "hair": "topknot", "hair_color": [0.1,0.08,0.07], "held": "sword"}],
			["Elder Mo", "elder", {}], ["Trader Wen", "merchant", {}], ["Smith Hale", "smith", {"held": "hammer"}],
			["Apothecary Lin", "alchemist", {}], ["Examiner Sun", "academy", {"held": "staff"}], ["orc", "", {}], ["boss", "", {}]]
		var x := -7.0
		for sp in specs:
			var file: String = "character-orc.glb" if sp[0] in ["orc", "boss"] else "character-human.glb"
			var m = load("res://assets/kenney/mini-dungeon/" + file).instantiate()
			m.scale = Vector3.ONE * 2.0 * (1.3 if sp[0] == "boss" else 1.0)
			m.position = Vector3(x, 0, 0)
			root.add_child(m)
			root.get_node("Game").shrink_head(m) if file.contains("human") else null
			if sp[0] == "orc":
				D.dress_monster(m, {"name": "Goblin", "tint": [0.6, 1.0, 0.5], "scale": 1.0})
			elif sp[0] == "boss":
				D.dress_monster(m, {"name": "Boss", "tint": [1, 0.5, 0.4], "scale": 1.4, "boss": true})
			else:
				D.dress(m, D.spec_for(sp[0], sp[1], sp[2]))
			var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
			if ap.has_animation(anim):
				ap.play(anim)
				ap.seek(0.3, true)
			x += 2.0
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 2.6, 7.0)
		cam.look_at(Vector3(0, 0.9, 0))
		cam.fov = 60
	elif f == 30:
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
	return false
