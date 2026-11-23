extends SceneTree
## r186b: every place, how heavy it is to draw (draws, shadow casters, triangles, lights) -- the worst first
var _ids: Array = []
var _i := 0
var _frames := 0
var _level: Node3D
var _player: Node3D
var rows := []


func _initialize() -> void:
	var smoke = load("res://tools/smoke.gd")
	var d := DirAccess.open("res://levels")
	for f in d.get_files():
		if f.ends_with(".json"):
			_ids.append(f.get_basename())
	_ids.append("valley")
	var fj = JSON.parse_string(FileAccess.get_file_as_string("res://data/frontier.json"))
	for rid in fj.get("regions", {}):
		_ids.append("frontier:%s" % rid)
	var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/valley.json"))
	for t in v.get("towers", []):
		_ids.append("tower:%s:%d" % [t.get("id", ""), 5])
	load("res://scripts/world/Level.gd").stream_on = false


func _tris(m: Mesh) -> int:
	var t := 0
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		t += (a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX].size() / 3)
	return t


func _process(_delta: float) -> bool:
	if _i >= _ids.size():
		rows.sort_custom(func(a, b): return a[2] > b[2])
		for r in rows:
			print("PERF %-34s draws %5d  casters %5d  tris %6.2fM  lights %4d" % r)
		quit(0)
		return true
	var id: String = _ids[_i]
	var game = root.get_node_or_null("Game")
	if _frames == 0:
		var def: Dictionary = game.load_level_def(id)
		if def.is_empty():
			_i += 1
			return false
		_level = load("res://scripts/world/Level.gd").new()
		_level.name = "Level"
		_level.build(def)
		root.add_child(_level)
		_player = load("res://scripts/actors/Player.gd").new()
		root.add_child(_player)
		_player.global_position = _level.spawn_point("P")
	_frames += 1
	if _frames == 4:
		_level.batch_trees_now()
		_level.batch_props_now()
	if _frames < 8:
		return false
	var draws := 0
	var casters := 0
	var tris := 0
	for gi in _level.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			tris += _tris((g as MeshInstance3D).mesh)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			tris += _tris((g as MultiMeshInstance3D).multimesh.mesh) * (g as MultiMeshInstance3D).multimesh.instance_count
		else:
			continue
		draws += 1
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
	var lights := _level.find_children("*", "Light3D", true, false).size()
	rows.append([id, draws, casters, tris / 1000000.0, lights])
	_player.queue_free()
	_level.queue_free()
	_frames = 0
	_i += 1
	return false
