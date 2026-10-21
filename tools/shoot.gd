extends SceneTree
## Screenshots of a level, for checking it with your own eyes.
##   godot --path . --script res://tools/shoot.gd -- <level_id> <out_dir> [spawn_tag] [yaw_degrees] [sense]
## "sense" = shoot it as a player with Spirit Sense (hidden things showing).
## Saves <out_dir>/<level_id>_overhead.png and <level_id>_player.png.

var _frames := 0
var _level
var _player
var _id := "village"
var _out := "user://shots"
var _tag := "P"
var _yaw := 0.0
var _over: Camera3D
var _sense := false


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _id = a[0]
	if a.size() > 1: _out = a[1]
	if a.size() > 2: _tag = a[2]
	if a.size() > 3: _yaw = deg_to_rad(float(a[3]))
	if a.size() > 4: _sense = a[4] == "sense"
	DirAccess.make_dir_recursive_absolute(_out)


func _setup() -> void:
	var game = root.get_node("Game")
	game.playlog_path = "user://tool_playlog.jsonl"
	game.save_path = "user://screenshot_save.json"   # never the real save
	game.new_game()
	var _w := OS.get_environment("SHOOT_WEAPON")
	if _w != "":
		game.add_item(_w, 1)
		game.equip(_w)
	if OS.get_environment("DCE_HOUR") != "":
		game.hour_override = float(OS.get_environment("DCE_HOUR"))
	if _sense:
		game.techniques["spirit_sense"] = true
	var fake := OS.get_environment("DCE_ONLINE_FAKE")
	if fake == "hub":
		game.online.state = "char"
		game.online.char = {"id": "me", "name": "Me", "realm": 0}
		game.online.players = {"p1": {"id": "p1", "name": "Wen", "x": 4.0, "z": 12.0, "yaw": 1.0}, "p2": {"id": "p2", "name": "Ruo", "x": -5.0, "z": 14.0, "yaw": 2.0}}
	elif fake == "arena":
		game.online.state = "instance"
		game.online.inst = {"kind": "run", "radius": 16.0, "me": "a", "hpmax": 1000.0, "hp": 640.0, "alive": true, "phase": "room", "text": "Room 2 of 4",
			"members": {"a": "Me", "b": "Friend"}, "pl": {"a": ["a", 0.0, 9.0, 0.0, 640, 1], "b": ["b", 3.0, 8.0, 0.0, 400, 1]},
			"foes": {1: {"id": 1, "type": "goblin", "name": "Goblin", "hp": 50, "max": 80, "x": 0.0, "z": 0.0, "scale": 1.0, "boss": false},
				2: {"id": 2, "type": "goblin", "name": "Goblin", "hp": 80, "max": 80, "x": 3.0, "z": -2.0, "scale": 1.0, "boss": false}},
			"haz": {7: {"id": 7, "kind": "circle", "x": -4.0, "z": 3.0, "r": 3.0, "t": 1.0, "t0": Time.get_ticks_msec() / 1000.0 - 0.5, "total": 1.0}}, "orbs": {}}
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	_level = load("res://scripts/world/Level.gd").new()
	_level.name = "Level"
	_level.build(game.load_level_def(_id))
	root.add_child(_level)
	_player = load("res://scripts/actors/Player.gd").new()
	root.add_child(_player)
	_player.global_position = _level.spawn_point(_tag)
	_player.face_camera_toward(_yaw)
	hud.set_level_name(_level.display_name())
	if OS.get_environment("DCE_TOUCH") != "":
		load("res://scripts/ui/TouchUI.gd").fit_screen(self)       # what a phone/tablet does at start
		var tu = load("res://scripts/ui/TouchUI.gd").new()
		root.add_child(tu)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup()
		return false
	if _frames == 39 and OS.get_environment("DCE_ONLINE_FAKE") != "":
		for e in root.get_tree().get_nodes_in_group("enemy"):
			var cam := root.get_viewport().get_camera_3d()
			print("FOE ", e.name, " at ", e.global_position, " vis ", e.visible, " player ", _player.global_position, " cam ", cam.global_position, " fwd ", -cam.global_transform.basis.z, " onscreen ", cam.unproject_position(e.global_position), " behind ", cam.is_position_behind(e.global_position))
			for ch in e.get_children():
				if ch is Node3D:
					print("   child ", ch.name, " ", ch.visible, " ", ch.get_class())
	if _frames == 40:
		root.get_texture().get_image().save_png(_out + "/" + _id + "_player.png")
		_over = Camera3D.new()
		var w: float = _level.width * 2.0
		var h: float = _level.height * 2.0
		_over.position = Vector3(w / 2.0, max(w, h) * 0.95, h / 2.0 + max(w, h) * 0.32)
		root.add_child(_over)
		_over.look_at(Vector3(w / 2.0, 0, h / 2.0 + 1.0))
		_over.fov = 55
		_over.current = true
		for n in root.get_children():
			if n is CanvasLayer:
				n.visible = false
	if _frames == 46:
		root.get_texture().get_image().save_png(_out + "/" + _id + "_overhead.png")
		quit()
	return false
