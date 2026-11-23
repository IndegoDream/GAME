extends RefCounted
## Real houses (2026-11-06, the CC0 art pack -- Quaternius' Medieval Village
## MegaKit, CC0, in assets/cc0/village/).
##
## A town's houses are blocks of "H" cells (2 m each). They used to be one toy
## block and one little gable per cell, so a 3x4 house was twelve gables in a
## row. Now each block becomes ONE house built from the kit: walls with
## windows (plaster, or brick below and plaster above), a door on the side
## that faces the street, corner posts, a tiled roof the size of the house
## with brick gable ends, and a chimney.
##
## Only the look changes: every "H" cell is still solid with the same
## collision box, so nothing about walking, paths or quests moves.
##
## Each house is one mesh (a surface per material), and the same shape of
## house is built once and shared -- a city of 150 houses is a few dozen
## meshes and a few hundred draws.

const K := "res://assets/cc0/village/"
const CELL := 2.0
const STOREY := 3.12                         # the kit's wall height
## the roof sizes the kit has: width (m, the short side) -> lengths (m)
const ROOFS := {4: [4, 6, 8], 6: [4, 6, 8, 10, 12, 14], 8: [8, 10, 12, 14]}

static var _scenes := {}
static var _meshes := {}                     # shape key -> ArrayMesh
static var built := 0                        # houses built this session (tests)


static func available() -> bool:
	return ResourceLoader.exists(K + "Wall_Plaster_Straight.gltf") and ResourceLoader.exists(K + "Roof_RoundTiles_6x8.gltf")


static func _scene(n: String) -> PackedScene:
	if not _scenes.has(n):
		var p := K + n + ".gltf"
		_scenes[n] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[n]


# ---- which houses ------------------------------------------------------------------------------

static func blocks(cells: Array) -> Array:
	## the "H" cells -> rectangles (cell coords) that each take one roof
	var set := {}
	for c in cells:
		set[c] = true
	var rects := []
	var keys := set.keys()
	keys.sort()
	for c0 in keys:
		var c: Vector2i = c0
		if not set.has(c):
			continue
		# greedy: as wide as the row runs, then as deep as every row under it does
		var w := 1
		while set.has(c + Vector2i(w, 0)):
			w += 1
		var h := 1
		while true:
			var full := true
			for x in w:
				if not set.has(c + Vector2i(x, h)):
					full = false
					break
			if not full:
				break
			h += 1
		for y in h:
			for x in w:
				set.erase(c + Vector2i(x, y))
		rects.append(Rect2i(c, Vector2i(w, h)))
	var out := []
	for r in rects:
		out.append_array(fit(r))
	return out


static func fit(r: Rect2i) -> Array:
	## split a rectangle until every piece has a roof in the kit (a 1-wide
	## strip has none: it's returned with size.x or size.y of 1, for the old block)
	var w := r.size.x
	var h := r.size.y
	var s := mini(w, h)
	var l := maxi(w, h)
	if s <= 1:
		return [r]
	if s > 4:
		var a := s / 2
		return fit(_cut(r, w <= h, a)) + fit(_cut_rest(r, w <= h, a))
	var lens: Array = ROOFS.get(s * 2, [])
	if (l * 2) in lens:
		return [r]
	if l * 2 < int(lens[0]):
		return [r]                               # (a 4x2 that can't take the 8-wide roof: shrink the short side next)
	var piece := int(lens[-1]) / 2
	var first := mini(piece, l - maxi(int(lens[0]) / 2, 2)) if l > piece else piece
	first = maxi(first, int(lens[0]) / 2)
	if first >= l:
		return [r]
	return fit(_cut(r, w > h, first)) + fit(_cut_rest(r, w > h, first))


static func _cut(r: Rect2i, along_x: bool, n: int) -> Rect2i:
	return Rect2i(r.position, Vector2i(n, r.size.y)) if along_x else Rect2i(r.position, Vector2i(r.size.x, n))


static func _cut_rest(r: Rect2i, along_x: bool, n: int) -> Rect2i:
	return Rect2i(r.position + Vector2i(n, 0), Vector2i(r.size.x - n, r.size.y)) if along_x else Rect2i(r.position + Vector2i(0, n), Vector2i(r.size.x, r.size.y - n))


static func roofable(r: Rect2i) -> bool:
	var s := mini(r.size.x, r.size.y)
	var l := maxi(r.size.x, r.size.y)
	return ROOFS.has(s * 2) and (l * 2) in ROOFS[s * 2]


# ---- one house ----------------------------------------------------------------------------------

static func make(r: Rect2i, door_dir: Vector2i, seed: int, cell_to_world: Callable) -> Dictionary:
	## {"node": the house, "chimney": world point of its chimney top (or none)}
	## door_dir: the way the street lies from the house, in cells ((0,1) = +z ...)
	var long_z := r.size.y >= r.size.x                 # the ridge runs along the long side
	var W := mini(r.size.x, r.size.y) * int(CELL)
	var D := maxi(r.size.x, r.size.y) * int(CELL)
	# the door's side in the house's own frame (+z, +x, -z, -x)
	var dd := door_dir if long_z else Vector2i(door_dir.y, -door_dir.x)
	var side := 0
	if dd == Vector2i(1, 0):
		side = 1
	elif dd == Vector2i(0, -1):
		side = 2
	elif dd == Vector2i(-1, 0):
		side = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var style := rng.randi() % 3                      # 0 plaster, 1 brick, 2 brick below / plaster above
	var storeys := 2 if (W * D >= 48 and rng.randf() < 0.55) or style == 2 else 1
	if storeys == 2 and style == 0:
		style = 2
	var round_win := rng.randf() < 0.6
	var key := "%d|%d|%d|%d|%d|%d" % [W, D, side, style, storeys, int(round_win)]
	if not _meshes.has(key):
		_meshes[key] = _build(W, D, side, style, storeys, round_win)
	var mi := MeshInstance3D.new()
	mi.name = "House"
	mi.mesh = _meshes[key]
	# a town of one colour reads as a toy: each house its own (muted) tiles and plaster
	_tint_surface(mi, "MI_RoundTiles", ROOF_TINTS[rng.randi() % ROOF_TINTS.size()])
	_tint_surface(mi, "MI_Plaster", PLASTER_TINTS[rng.randi() % PLASTER_TINTS.size()])
	var a: Vector3 = cell_to_world.call(r.position)
	var b: Vector3 = cell_to_world.call(r.position + r.size - Vector2i.ONE)
	mi.position = Vector3((a.x + b.x) / 2.0, 0.0, (a.z + b.z) / 2.0)
	mi.rotation.y = 0.0 if long_z else PI / 2.0
	built += 1
	var top := STOREY * storeys
	var ch := Vector3(W / 4.0, top + 2.6, -D / 4.0)
	return {"node": mi, "chimney": mi.position + Basis(Vector3.UP, mi.rotation.y) * ch, "height": top}


static func _build(W: int, D: int, side: int, style: int, storeys: int, round_win: bool) -> ArrayMesh:
	var parts := []                                   # [Mesh, Transform3D]
	var nx := W / 2                                   # wall pieces along x (short sides)
	var nz := D / 2                                   # along z (long sides)
	for f in storeys:
		var y := STOREY * f
		var brick := style == 1 or (style == 2 and f == 0)
		var mat := "UnevenBrick" if brick else "Plaster"
		# the four sides: side index, how many pieces, where each piece stands, its turn
		for s in 4:
			var n := nx if s % 2 == 0 else nz
			for i in n:
				var t := -float(n) + 1.0 + 2.0 * i          # piece centre along the side
				var pos: Vector3
				var yaw := 0.0
				match s:
					0:
						pos = Vector3(t, y, D / 2.0)
						yaw = 0.0
					1:
						pos = Vector3(W / 2.0, y, -t)
						yaw = PI / 2.0
					2:
						pos = Vector3(-t, y, -D / 2.0)
						yaw = PI
					_:
						pos = Vector3(-W / 2.0, y, t)
						yaw = -PI / 2.0
				var piece := "Wall_%s_Straight" % mat
				var extra := ""
				var mid := n / 2
				if f == 0 and s == side and i == mid:
					piece = "Wall_%s_Door_%s" % [mat, "Round" if round_win else "Flat"]
					extra = "Door_1_" + ("Round" if round_win else "Flat")
				elif (i + s + f) % 2 == 0 or n == 1:
					var wide := s % 2 == 1 or n > 2
					piece = "Wall_%s_Window_%s_%s" % [mat, "Wide" if wide else "Thin", "Round" if (round_win or not wide) else "Flat"]
					extra = "Window_%s_%s1" % ["Wide" if wide else "Thin", "Round" if (round_win or not wide) else "Flat"]
				elif not brick and f > 0:
					piece = "Wall_Plaster_WoodGrid"
				var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
				_add(parts, piece, xf)
				if extra != "":
					_add(parts, extra, xf)
		# corner posts
		for c in [Vector3(W / 2.0, y, D / 2.0), Vector3(W / 2.0, y, -D / 2.0), Vector3(-W / 2.0, y, -D / 2.0), Vector3(-W / 2.0, y, D / 2.0)]:
			_add(parts, "Corner_Exterior_Brick" if brick else "Corner_Exterior_Wood", Transform3D(Basis.IDENTITY, c))
		if f > 0:
			for s2 in 4:
				var n2 := nx if s2 % 2 == 0 else nz
				for i2 in n2:
					var t2 := -float(n2) + 1.0 + 2.0 * i2
					var p2: Vector3 = [Vector3(t2, y, D / 2.0), Vector3(W / 2.0, y, -t2), Vector3(-t2, y, -D / 2.0), Vector3(-W / 2.0, y, t2)][s2]
					_add(parts, "Wall_BottomCover", Transform3D(Basis(Vector3.UP, [0.0, PI / 2.0, PI, -PI / 2.0][s2]), p2))
	var top := STOREY * storeys
	_add(parts, "Roof_RoundTiles_%dx%d" % [W, D], Transform3D(Basis.IDENTITY, Vector3(0, top, 0)))
	_add(parts, "Roof_Front_Brick%d" % W, Transform3D(Basis.IDENTITY, Vector3(0, top, D / 2.0)))
	_add(parts, "Roof_Front_Brick%d" % W, Transform3D(Basis(Vector3.UP, PI), Vector3(0, top, -D / 2.0)))
	_add(parts, "Prop_Chimney", Transform3D(Basis.IDENTITY, Vector3(W / 4.0, top - 0.6, -D / 4.0)))
	return _merge(parts)


static func _add(parts: Array, piece: String, xf: Transform3D) -> void:
	var ps := _scene(piece)
	if ps == null:
		return
	var n := ps.instantiate()
	_collect(n, xf, parts)
	n.free()


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_collect(c, here, out)


static var _mats := {}                         # material name -> the one material every house shares
## weathered terracotta, old slate-brown, sun-faded clay, mossy dark tile
const ROOF_TINTS := [Color(0.78, 0.6, 0.52), Color(0.55, 0.47, 0.44), Color(0.85, 0.72, 0.62), Color(0.62, 0.6, 0.55)]
const PLASTER_TINTS := [Color(1, 1, 1), Color(0.95, 0.9, 0.8), Color(0.9, 0.86, 0.78), Color(0.98, 0.95, 0.9)]
static var _tinted := {}                       # "name|tint" -> material


static func _tint_surface(mi: MeshInstance3D, mat_name: String, c: Color) -> void:
	var m := mi.mesh
	for i in m.get_surface_count():
		var base: Material = m.surface_get_material(i)
		if base == null or str(base.resource_name) != mat_name or not (base is StandardMaterial3D):
			continue
		var k := "%s|%s" % [mat_name, c]
		if not _tinted.has(k):
			var t: StandardMaterial3D = (base as StandardMaterial3D).duplicate()
			t.albedo_color = c
			_tinted[k] = t
		mi.set_surface_override_material(i, _tinted[k])


static func _merge(parts: Array) -> ArrayMesh:
	## one mesh, a surface per material (the kit's pieces each carry their own
	## copy of "MI_Plaster" and the rest -- folded together by name)
	var tools := {}
	var order := []
	for p in parts:
		var m: Mesh = p[0]
		for i in m.get_surface_count():
			if m.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = m.surface_get_material(i)
			var nm := str(mat.resource_name) if mat else "none"
			if not _mats.has(nm):
				_mats[nm] = mat
			if not tools.has(nm):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[nm] = st
				order.append(nm)
			(tools[nm] as SurfaceTool).append_from(m, i, p[1])
	var am := ArrayMesh.new()
	for nm in order:
		(tools[nm] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, _mats[nm])
	return am
