extends SceneTree
## one wall torch on a wall, for looking at. godot --path . --script res://tools/torch_shot.gd -- out.png
var _f := 0
var _out := "user://torch.png"
func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: _out = a[0]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_color = Color(0.25, 0.25, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = e
	root.add_child(env)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8, 4, 0.5)
	wall.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.38, 0.3)
	wall.material_override = wm
	wall.position = Vector3(0, 2, 0.25)
	root.add_child(wall)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_.mesh = pm
	floor_.material_override = wm
	root.add_child(floor_)
	var T = load("res://scripts/objects/Torch.gd")
	var t = T.new()
	t.setup(null, {"wall": true, "dir": Vector2(0, 1), "color": [1.0, 0.68, 0.35]})
	root.add_child(t)
	t.position = Vector3(0, 0, -0.22)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.2, 1.6, -2.4)
	cam.look_at(Vector3(0, 1.6, 0), Vector3.UP)
	cam.current = true
func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_setup()
	if _f == 40:
		root.get_texture().get_image().save_png(_out)
		quit()
	return false
