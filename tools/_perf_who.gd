extends SceneTree
## r187: where do the plain spheres / cylinders in a place come from (ID=valley)
var _f := 0
var _level: Node3D
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
	if _f < 4:
		return false
	var seen := {}
	for mi in _level.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or not (m is SphereMesh or m is CylinderMesh or m is BoxMesh or (m is ArrayMesh and mi.get_parent() == _level)):
			continue
		var chain := []
		var n: Node = mi
		while n and n != _level:
			chain.push_front("%s(%s%s)" % [str(n.name).rstrip("0123456789@"), n.get_class(), ("," + n.get_script().resource_path.get_file()) if n.get_script() else ""])
			n = n.get_parent()
		var k := m.get_class() + " " + "/".join(PackedStringArray(chain.map(func(s): return str(s).rstrip("0123456789@"))))
		var mat: Material = (mi as MeshInstance3D).material_override
		if mat == null and m.get_surface_count() > 0:
			mat = m.surface_get_material(0)
		k += " mat=" + (mat.get_class() + ":" + ((mat as BaseMaterial3D).albedo_texture.resource_path.get_file() if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture else "") + ":" + str(mat.get_instance_id() % 997) if mat else "-") + " aabb=" + str(m.get_aabb().size.snapped(Vector3.ONE * 0.5)) + " flick=" + str(mi.has_meta("flicker"))
		seen[k] = int(seen.get(k, 0)) + 1
	var rows := []
	for k in seen:
		rows.append([seen[k], k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 5000):
		print("W %5d  %s" % r)
	quit(0)
	return false
