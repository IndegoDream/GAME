extends SceneTree
## r186b: one place in detail (ID=valley): what the draws and triangles are
var _f := 0
var _level: Node3D
var _player: Node3D
func _tris(m: Mesh) -> int:
	var t := 0
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		t += (a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX].size() / 3)
	return t
func _key(g: Node, m: Mesh) -> String:
	var src := ""
	var mat: Material = (g as GeometryInstance3D).material_override
	if mat == null and m.get_surface_count() > 0:
		mat = m.surface_get_material(0)
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
		src = (mat as BaseMaterial3D).albedo_texture.resource_path.get_file()
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		src = (mat as ShaderMaterial).shader.resource_path.get_file()
	return "%s/%s %s %s" % [g.get_parent().name.rstrip("0123456789@"), g.name.rstrip("0123456789@"), m.get_class(), src]
func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		load("res://scripts/world/Level.gd").stream_on = false
		var game = root.get_node("Game")
		var def: Dictionary = game.load_level_def(OS.get_environment("ID"))
		_level = load("res://scripts/world/Level.gd").new()
		_level.name = "Level"
		_level.build(def)
		root.add_child(_level)
		_player = load("res://scripts/actors/Player.gd").new()
		root.add_child(_player)
		_player.global_position = _level.spawn_point("P")
	if _f == 4:
		_level.batch_trees_now()
	if _f == 6:
		_level.batch_props_now()
	if _f < 8:
		return false
	var by := {}
	for gi in _level.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var m: Mesh = null
		var inst := 1
		if g is MeshInstance3D:
			m = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			m = (g as MultiMeshInstance3D).multimesh.mesh
			inst = (g as MultiMeshInstance3D).multimesh.instance_count
		if m == null:
			continue
		var k := _key(g, m)
		var e: Array = by.get(k, [0, 0, 0])
		e[0] += 1
		e[1] += _tris(m) * inst
		e[2] += 1 if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
		by[k] = e
	var rows := []
	for k in by:
		rows.append([by[k][0], by[k][1], by[k][2], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("--- by draws")
	for r in rows.slice(0, 14):
		print("D %5d draws %8d tris %5d casters  %s" % r)
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("--- by triangles")
	for r in rows.slice(0, 14):
		print("T %5d draws %8d tris %5d casters  %s" % r)
	var lights := {}
	for l in _level.find_children("*", "Light3D", true, false):
		var k2 := "%s/%s shadow=%s" % [l.get_parent().name.rstrip("0123456789@"), l.name.rstrip("0123456789@"), (l as Light3D).shadow_enabled]
		lights[k2] = int(lights.get(k2, 0)) + 1
	for k3 in lights:
		if lights[k3] > 10:
			print("L %4d %s" % [lights[k3], k3])
	quit(0)
	return false
