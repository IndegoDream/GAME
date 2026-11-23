extends SceneTree
## Round 186: Eliet must stay light enough to draw. Robert's own play log showed 3-4 frames a second on an
## RTX 5060 Ti: 10,782 shadow-casting pieces (every tree limb its own draw) and 20 million triangles a frame
## (the grass tufts were full photo scans, 24,730 triangles each). This holds the line:
##   godot --headless --path . --script res://tools/perf_check.gd
var _pass := 0
var _fail := 0
var _f := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _tris(m: Mesh) -> int:
	var t := 0
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		t += (a[Mesh.ARRAY_INDEX].size() / 3) if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX].size() / 3)
	return t


func _process(_d: float) -> bool:
	if _phase == 1:
		return _valley()
	_f += 1
	if _f == 2:
		var game = root.get_node("Game")
		game.playlog_path = "user://tool_playlog.jsonl"
		game.save_path = "user://perf_check_save.json"
		load("res://Main.gd").force_veil = true
		root.add_child(load("res://Main.tscn").instantiate())
		return false
	if _f == 6:
		var game2 = root.get_node("Game")
		game2.new_game()
		game2.go_to("village", "<")
		return false
	if _f < 7:
		return false
	var lv = root.get_tree().get_first_node_in_group("level")
	if (lv == null or str(lv.level_id) != "village" or lv.stream_left() > 0) and _f < 3000:
		return false
	check("the village is up", lv != null)
	if lv == null:
		quit(1)
		return true
	if not lv.has_meta("perf_batched"):
		lv.batch_trees_now()
		lv.batch_props_now()
		lv.set_meta("perf_batched", true)
		return false              # (the old meshes go at the end of the frame)
	var limbs := 0
	var trees := 0
	for n in lv.find_children("*", "Node3D", true, false):
		if (n as Node).has_meta("realistic_tree"):
			trees += 1
			if (n as Node3D).get_node_or_null("Bark") != null:
				limbs += 1
	check("trees are drawn in patches (%d trees, %d batches)" % [lv.trees_in_batches, lv.tree_batches], lv.trees_in_batches >= trees - 5 and lv.tree_batches > 0 and lv.tree_batches < trees / 4, [trees, lv.trees_in_batches, lv.tree_batches])
	check("no tree keeps its own bark mesh (%d)" % limbs, limbs <= 5)
	var casters := 0
	var tris := 0
	var draws := 0
	for gi in lv.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			draws += 1
			tris += _tris((g as MeshInstance3D).mesh)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			draws += 1
			tris += _tris((g as MultiMeshInstance3D).multimesh.mesh) * (g as MultiMeshInstance3D).multimesh.instance_count
		else:
			continue
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
	print("village: draws %d, shadow casters %d, triangles %.1f M" % [draws, casters, tris / 1000000.0])
	check("Eliet: under 1,200 shadow casters (%d)" % casters, casters < 1200)
	check("Eliet: under 1,500 draws (%d)" % draws, draws < 1500)
	check("Eliet: under 8 million triangles if all of it were in view (%.1f M)" % (tris / 1000000.0), tris < 8000000)
	check("still props are drawn in patches (%d props, %d batches)" % [lv.props_in_batches, lv.prop_batches], lv.props_in_batches > 50 and lv.prop_batches > 0 and lv.prop_batches < lv.props_in_batches)
	_props_unit(lv)
	var A = load("res://scripts/core/Art.gd")
	A.full_detail = false
	check("the grass uses its low-poly copy", A.real_path("grass_medium_01").ends_with("_lo.gltf"))
	A.full_detail = true
	A._lo.clear()
	check("...and Ultra the full scan", not A.real_path("grass_medium_01").ends_with("_lo.gltf"))
	A.full_detail = false
	A._lo.clear()
	check("a model with no copy keeps its own", A.real_path("moss_01").ends_with("moss_01.gltf"))
	var T = load("res://scripts/world/Tree.gd")
	var t1: Node3D = T.make(false, 6.0, 12345, "")
	var t2: Node3D = T.make(false, 6.0, 12345 + T.VARIANTS, "")
	check("a tree is one bark mesh and one crown", t1.get_child_count() == 2 and t1.get_node("Bark") is MeshInstance3D and t1.get_node("Leaves") is MultiMeshInstance3D)
	check("trees of the same variant share their shapes", (t1.get_node("Bark") as MeshInstance3D).mesh == (t2.get_node("Bark") as MeshInstance3D).mesh)
	t1.free()
	t2.free()
	_phase = 1
	root.get_node("Game").go_to("valley", "<")
	return false


var _phase := 0
var _vf := 0


func _valley() -> bool:
	_vf += 1
	var lv = root.get_tree().get_first_node_in_group("level")
	if (lv == null or str(lv.level_id) != "valley" or lv.stream_left() > 0) and _vf < 4000:
		return false
	check("the valley is up", lv != null and str(lv.level_id) == "valley")
	if lv == null:
		return _end()
	if not lv.has_meta("perf_batched"):
		lv.batch_trees_now()
		lv.batch_props_now()
		lv.set_meta("perf_batched", true)
		return false
	var c := _count(lv)
	print("valley: draws %d, shadow casters %d, triangles %.1f M, ponds batched %d" % [c[0], c[1], c[2] / 1000000.0, lv.water_in_batches])
	check("the valley: under 2,500 shadow casters (%d)" % c[1], c[1] < 2500)
	check("the valley: under 3,500 draws (%d)" % c[0], c[0] < 3500)
	var og := lv.get_node_or_null("OutdoorGround") as GeometryInstance3D
	check("the open ground casts no shadow (its edge drew a black line on the land past the map)", og != null and og.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	check("the valley's small lamps fade with distance (%d)" % lv.lights_faded, lv.lights_faded > 20)
	var near_lamps := 0
	for l in lv.find_children("*", "OmniLight3D", true, false):
		if not (l as Light3D).distance_fade_enabled and (l as OmniLight3D).omni_range <= 16.0:
			near_lamps += 1
	check("...every one of them (%d don't)" % near_lamps, near_lamps == 0)
	check("the valley's ponds are drawn in patches (%d cells)" % lv.water_in_batches, lv.water_in_batches > 100)
	var lone := 0
	for n in lv.get_children():
		if n is MeshInstance3D and n.has_meta("batch_water"):
			lone += 1
	check("...few pond cells left on their own (%d)" % lone, lone < lv.water_in_batches / 4)
	return _end()


func _end() -> bool:
	print("PERF CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true


func _count(lv) -> Array:
	var casters := 0
	var tris := 0
	var draws := 0
	for gi in lv.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if not g.is_visible_in_tree() or g.is_queued_for_deletion():
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			draws += 1
			tris += _tris((g as MeshInstance3D).mesh)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh and (g as MultiMeshInstance3D).multimesh.mesh:
			draws += 1
			tris += _tris((g as MultiMeshInstance3D).multimesh.mesh) * (g as MultiMeshInstance3D).multimesh.instance_count
		else:
			continue
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
	return [draws, casters, tris]


func _props_unit(lv) -> void:
	## which props may go into a batch
	var mk := func(nm: String) -> Node3D:
		var h := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		h.add_child(mi)
		lv.add_child(h)
		if nm != "":
			h.name = nm
		h.set_meta("pp", str(h.name))
		return h
	var plain: Node3D = mk.call("")
	check("a plain prop may be batched", lv.prop_batchable(plain))
	var renamed: Node3D = mk.call("")
	renamed.name = "LanternStoneTest"
	check("...not one renamed after it was made (something looks it up)", not lv.prop_batchable(renamed))
	var grouped: Node3D = mk.call("")
	grouped.add_to_group("perf_test_group")
	check("...not one in a group", not lv.prop_batchable(grouped))
	var lit: Node3D = mk.call("")
	lit.add_child(OmniLight3D.new())
	check("...not one with a light in it", not lv.prop_batchable(lit))
	var body: Node3D = mk.call("")
	body.add_child(StaticBody3D.new())
	check("...not one with a body in it", not lv.prop_batchable(body))
	var hidden: Node3D = mk.call("")
	hidden.visible = false
	check("...not a hidden one", not lv.prop_batchable(hidden))
	var scripted: Node3D = mk.call("")
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\n"
	gs.reload()
	scripted.set_script(gs)
	check("...not one with a script", not lv.prop_batchable(scripted))
	var loose := Node3D.new()
	loose.add_child(MeshInstance3D.new())
	(loose.get_child(0) as MeshInstance3D).mesh = BoxMesh.new()
	lv.add_child(loose)
	check("...not something _prop didn't make", not lv.prop_batchable(loose))
	for n in [plain, renamed, grouped, lit, body, hidden, scripted, loose]:
		(n as Node).free()
	var m1 := MeshInstance3D.new()
	m1.mesh = BoxMesh.new()
	var m2 := MeshInstance3D.new()
	m2.mesh = m1.mesh
	lv.add_child(m1)
	lv.add_child(m2)
	var mat := StandardMaterial3D.new()
	m1.set_surface_override_material(0, mat)
	m2.set_surface_override_material(0, mat)
	lv._tint(m1, Color(0.5, 0.5, 0.5))
	lv._tint(m2, Color(0.5, 0.5, 0.5))
	check("the same tint on the same material is one material, not two", m1.get_surface_override_material(0) == m2.get_surface_override_material(0) and m1.get_surface_override_material(0) != mat)
	m1.free()
	m2.free()
