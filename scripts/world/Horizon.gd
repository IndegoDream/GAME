extends Node3D
## The world past the edge of the map (round 48). Robert, 2026-10-04: "the
## whole world needs more depth -- the illusion of it continuing."
##
## UNDER THE SKY (Eliet, the valley's wilds): the land keeps going. Fields
## roll up from the village's edge into wooded hills, the hills climb to a
## ring of mountains with snow on their peaks (more in Frost); a forest of
## real trees (Tree.gd) stands on the slopes; far off, a sect's pagoda on a
## ridge (its lamp lit at night) and smoke from farms you'll never reach. The
## distance fades into the weather's haze.
## UNDERGROUND: the rock keeps going. The halls are cut out of one great mass
## of stone that runs on past every wall, cracked here and there with a
## faint glow from caverns you can't reach, and falling away at its edges
## into the dark of the deep below.
## Looks only, built once per level (round 48: assets/shaders/terrain.gdshader).
## Every number is in data/horizon.json.

var level
var _rng := RandomNumberGenerator.new()
var state := {}            # what got built (for tests)

var cfg := {}              # data/horizon.json


static var _cfg := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Game._load_json("res://data/horizon.json", {})
	return _cfg


func _f(sec: String, key: String, dflt: float) -> float:
	return float((cfg.get(sec, {}) as Dictionary).get(key, dflt))


func _a(sec: String, key: String, dflt: Array) -> Array:
	var v = (cfg.get(sec, {}) as Dictionary).get(key, dflt)
	return v if v is Array and (v as Array).size() >= dflt.size() else dflt


func setup(lvl) -> void:
	level = lvl


func _ready() -> void:
	name = "Horizon"
	add_to_group("fog_exempt")          # (FogOfWar: not a thing standing on a cell)
	cfg = config()
	_rng.seed = hash(str(level.level_id) + "horizon")
	if level.is_outdoor():
		_land()
	elif not bool(level.def.get("arena", false)) and str(level.theme) != "settlement":      # (a cavern town has its own cliffs and lake)
		_rock()


func _bounds() -> Rect2:
	return Rect2(0, 0, level.width * level.CELL, level.height * level.CELL)


# ---- under the sky -----------------------------------------------------------------------------

var _n1: FastNoiseLite
var _n2: FastNoiseLite


func height_at(x: float, z: float) -> float:
	## the land: flat at the map's edge, hills, then mountains
	var b := _bounds()
	var dx := maxf(maxf(b.position.x - x, x - b.end.x), 0.0)
	var dz := maxf(maxf(b.position.y - z, z - b.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	if d <= 0.0:
		return -0.15
	var hl: Array = _hills
	var mt: Array = _mounts
	var hills := smoothstep(float(hl[0]), float(hl[1]), d) * (float(hl[2]) + float(hl[3]) * (0.5 + 0.5 * _n1.get_noise_2d(x, z)))
	var mount := smoothstep(float(mt[0]), float(mt[1]), d) * (float(mt[2]) + float(mt[3]) * (0.5 + 0.5 * _n2.get_noise_2d(x, z)))
	# round 63: the mountains aren't a wall all round -- passes open between
	# them, and through a pass you see the far ranges, miles off
	var cpt := b.get_center()
	var ang := atan2(z - cpt.y, x - cpt.x)
	var gap := 1.0
	if _passes > 0:
		var g := 0.5 + 0.5 * sin(ang * float(_passes) + _pass_phase) + 0.35 * _n1.get_noise_1d(ang * 40.0)
		gap = lerpf(float(_pass_depth), 1.0, smoothstep(0.25, 0.75, g))
	return hills * lerpf(0.55, 1.0, gap) + mount * gap - 0.15


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.75
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


var _hills: Array = [4, 45, 6, 10]
var _mounts: Array = [70, 190, 55, 55]
var _passes := 0
var _pass_phase := 0.0
var _pass_depth := 0.15


func _land() -> void:
	_hills = _a("land", "hills", [4, 45, 6, 10])
	_mounts = _a("land", "mountains", [70, 190, 55, 55])
	_passes = int(_f("land", "passes", 3))
	_pass_depth = _f("land", "pass_depth", 0.15)
	_pass_phase = _rng.randf() * TAU
	if level.get("roads_out") != null and not level.roads_out.is_empty():
		# a pass where the first road leaves, so the road goes THROUGH the mountains
		var rd: Array = level.roads_out[0]
		var cpt := _bounds().get_center()
		var a0 := atan2((rd[1] as Vector2).y - cpt.y, (rd[1] as Vector2).x - cpt.x)
		_pass_phase = PI / 2.0 - a0 * float(_passes)
	var MARGIN := _f("land", "margin", 230.0)
	var STEP := _f("land", "step", 6.0)
	_n1 = FastNoiseLite.new()
	_n1.seed = _rng.randi()
	_n1.frequency = 0.02
	_n1.fractal_octaves = 3
	_n2 = FastNoiseLite.new()
	_n2.seed = _rng.randi()
	_n2.frequency = 0.008
	_n2.fractal_octaves = 4
	var b := _bounds()
	var x0 := b.position.x - MARGIN
	var z0 := b.position.y - MARGIN
	var nx := int((b.size.x + MARGIN * 2.0) / STEP) + 1
	var nz := int((b.size.y + MARGIN * 2.0) / STEP) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := b.grow(-1.0)
	var quads := 0
	var nv := nx + 1
	var have := PackedByteArray()
	have.resize(nv * (nz + 1))
	var hts := PackedFloat32Array()
	hts.resize(nv * (nz + 1))
	var nrm := PackedVector3Array()
	nrm.resize(nv * (nz + 1))
	for iz in nz:
		for ix in nx:
			var xa := x0 + ix * STEP
			var za := z0 + iz * STEP
			if inner.has_point(Vector2(xa, za)) and inner.has_point(Vector2(xa + STEP, za + STEP)):
				continue          # the map itself
			# (w010: each grid corner's height and normal is worked out once and shared by the quads that touch it)
			var ks := [iz * nv + ix, iz * nv + ix + 1, (iz + 1) * nv + ix + 1, (iz + 1) * nv + ix]
			for k in 4:
				var ci: int = ks[k]
				if not have[ci]:
					var gx := x0 + (ci % nv) * STEP
					var gz := z0 + (ci / nv) * STEP
					hts[ci] = height_at(gx, gz)
					nrm[ci] = normal_at(gx, gz)
					have[ci] = 1
			for i in [0, 1, 2, 0, 2, 3]:
				var ci2: int = ks[i]
				st.set_normal(nrm[ci2])
				st.add_vertex(Vector3(x0 + (ci2 % nv) * STEP, hts[ci2], z0 + (ci2 / nv) * STEP))
			quads += 1
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = "Land"
	mi.mesh = st.commit()
	mi.material_override = _land_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	state["land_quads"] = quads
	_forest()
	_far_things()
	_far_ranges()                  # round 63: the world goes on for miles


func _land_mat() -> Material:
	return land_material(level)


static var _land_mats := {}


static func land_material(lvl) -> Material:
	## round 63: ONE ground for the map and the land around it -- the same
	## world-space grass, rock and snow, and the same roads (lvl.road_mask)
	## running out of the village into the hills. Shared, so there's no seam.
	var key := str(lvl.level_id) if lvl else ""
	if _land_mats.has(key) and is_instance_valid(_land_mats[key]) and _land_mats[key].get_meta("for", null) == lvl:
		return _land_mats[key]
	var c := config()
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/terrain.gdshader")
	m.set_meta("for", lvl)
	var L := preload("res://scripts/world/Look.gd")
	var frontier: bool = lvl != null and lvl.def.has("frontier")          # round 123: a tech region's ground is its own surface, not grass
	if DisplayServer.get_name() != "headless":
		var gf := "grass_ground"
		var rf := "rock_face"
		if frontier:
			gf = str((lvl.look.get("floor", ["grass_ground"]) as Array)[0])
			rf = str((lvl.look.get("wall", ["rock_face"]) as Array)[0])
		m.set_shader_parameter("grass_tex", L.texture(gf, "albedo"))
		m.set_shader_parameter("rock_tex", L.texture(rf, "albedo"))
	var W = Game.sys("world")
	var sid: String = W.season_id() if W and not W.calm else ""
	var land: Dictionary = c.get("land", {})
	m.set_shader_parameter("snow_line", float(land.get("snow_line_frost", 30.0)) if sid == "frost" else float(land.get("snow_line", 70.0)))
	var gt := {"thaw": Color(0.8, 0.95, 0.7), "blaze": Color(0.95, 0.92, 0.65), "harvest": Color(1.0, 0.85, 0.55), "frost": Color(0.85, 0.88, 0.9)}
	m.set_shader_parameter("grass_tint", gt.get(sid, Color(0.85, 0.9, 0.75)))
	if frontier:
		m.set_shader_parameter("grass_tint", L.color3(lvl.def.get("ground_tint", []), Color(0.8, 0.8, 0.8)))
		m.set_shader_parameter("snow_line", 9999.0)
	if lvl and lvl.get("road_mask") != null:
		m.set_shader_parameter("use_roads", 1.0)
		m.set_shader_parameter("road_mask", lvl.road_mask)
		var r: Rect2 = lvl.road_mask_rect
		m.set_shader_parameter("mask_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		if DisplayServer.get_name() != "headless":
			var rs: Array = lvl.look.get("road", ["mossy_cobblestone", [0.8, 0.78, 0.74], 2.5])
			m.set_shader_parameter("road_tex", L.texture(str(rs[0]), "albedo"))
			var rt: Array = rs[1] if rs.size() > 1 and rs[1] is Array else [0.8, 0.78, 0.74]
			m.set_shader_parameter("road_tint", Color(float(rt[0]), float(rt[1]), float(rt[2])))
			m.set_shader_parameter("road_scale", 1.0 / maxf(float(rs[2]) if rs.size() > 2 else 2.5, 0.5) * 0.5)
	_land_mats[key] = m
	return m


func _forest() -> void:
	## a forest on the slopes: many trees, a handful of draws
	if level.def.has("frontier"):
		return          # (round 123: no trees on the moon)
	var T := preload("res://scripts/world/Tree.gd")
	if preload("res://scripts/core/Art.gd").style == "kenney" or not T.available():
		return
	var W = Game.sys("world")
	var look: Dictionary = W.season().get("look", {}) if W and not W.calm else {}
	var season := str(look.get("trees", ""))
	var b := _bounds()
	var cards := {true: [], false: []}
	var limbs := []
	var n := 0
	var tries := 0
	var want := int(_f("forest", "trees", 170))
	var outr := _a("forest", "out", [6, 95])
	var hr := _a("forest", "height", [7, 13])
	var maxy := _f("forest", "max_y", 40.0)
	var sparse := _f("forest", "sparse", 0.9)
	while n < want and tries < want * 12:
		tries += 1
		var side := _rng.randi() % 4
		var t := _rng.randf()
		var out := _rng.randf_range(float(outr[0]), float(outr[1]))
		var x := 0.0
		var z := 0.0
		match side:
			0:
				x = lerpf(b.position.x - out, b.end.x + out, t)
				z = b.position.y - out
			1:
				x = lerpf(b.position.x - out, b.end.x + out, t)
				z = b.end.y + out
			2:
				x = b.position.x - out
				z = lerpf(b.position.y - out, b.end.y + out, t)
			_:
				x = b.end.x + out
				z = lerpf(b.position.y - out, b.end.y + out, t)
		var y := height_at(x, z)
		if y > maxy:
			continue
		var conifer := _rng.randf() < (0.4 + clampf(y / maxy, 0.0, 0.5))      # pines higher up
		var h := _rng.randf_range(float(hr[0]), float(hr[1])) * (1.0 if out > 12.0 else 0.75)
		T.grow(conifer, h, _rng.randi(), season, cards[conifer], limbs, Vector3(x, y - 0.3, z), sparse)
		n += 1
	for c in [true, false]:
		if not (cards[c] as Array).is_empty():
			var mmi: MultiMeshInstance3D = T.leaves(cards[c], c, season, true)
			mmi.name = "Forest_" + ("pines" if c else "broadleaf")
			add_child(mmi)
	# the trunks (and limbs): one draw of bark
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	mm.mesh = cyl
	mm.instance_count = limbs.size()
	for i in limbs.size():
		var lb: Array = limbs[i]
		var d: Vector3 = (lb[1] as Vector3).normalized()
		var bas := Basis(Quaternion(Vector3.UP, d)) if d.cross(Vector3.UP).length() > 0.001 else Basis()
		bas = bas.scaled(Vector3(float(lb[3]), float(lb[2]), float(lb[3])))
		mm.set_instance_transform(i, Transform3D(bas, (lb[0] as Vector3) + d * float(lb[2]) * 0.5))
	var tr := MultiMeshInstance3D.new()
	tr.name = "Forest_trunks"
	tr.multimesh = mm
	tr.material_override = T.bark(true)
	add_child(tr)
	state["forest"] = n


func _far_things() -> void:
	## a sect's pagoda on a ridge to the north, smoke from far farms
	if level.def.has("frontier"):
		return
	var b := _bounds()
	var sc := _f("tower", "scale", 9.0)
	var px := b.position.x + b.size.x * _f("tower", "across", 0.65)
	var pz := b.position.y - _f("tower", "ahead", 120.0)
	var py := height_at(px, pz)
	var pag := Node3D.new()
	pag.name = "FarPagoda"
	pag.position = Vector3(px, py - 0.5, pz)
	add_child(pag)
	var y := 0.0
	for piece in ["castle-kit/tower-hexagon-base.glb", "castle-kit/tower-hexagon-mid.glb", "castle-kit/tower-hexagon-mid.glb", "castle-kit/tower-hexagon-roof.glb"]:
		if not ResourceLoader.exists("res://assets/kenney/" + piece):
			continue
		var m: Node3D = load("res://assets/kenney/" + piece).instantiate()
		m.scale = Vector3.ONE * sc
		var bb := _aabb(m)
		m.position = Vector3(0, y - bb.position.y * sc, 0)
		_dress_tower(m, piece.contains("roof"))
		pag.add_child(m)
		y += maxf(bb.size.y, 0.2) * sc * (0.98 if piece.ends_with("mid.glb") or piece.ends_with("base.glb") else 1.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.4)
	lamp.omni_range = 30.0
	lamp.light_energy = _f("tower", "lamp", 3.0) * (1.0 - Game.daylight())
	lamp.position = Vector3(0, y * 0.75, 0)
	pag.add_child(lamp)
	state["pagoda"] = true
	if DisplayServer.get_name() == "headless":
		return
	var sr := _a("smoke", "range", [70, 130])
	for i in int(_f("smoke", "count", 3)):
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(float(sr[0]), float(sr[1]))
		var sx := b.get_center().x + cos(a) * r
		var sz := b.get_center().y + sin(a) * r
		var sm = preload("res://scripts/fx/Motes.gd").new()
		sm.kind = "smoke"
		sm.position = Vector3(sx, height_at(sx, sz) + 2.0, sz)
		sm.scale = Vector3.ONE * 4.0
		add_child(sm)


func _touches(open: Dictionary, q: Vector2) -> bool:
	## does this corner of the grid touch an open cell? (then the rock sits
	## flush with the wall top there -- no lip hanging over the hall)
	var x := int(q.x)
	var y := int(q.y)
	return open.has(Vector2i(x, y)) or open.has(Vector2i(x - 1, y)) or open.has(Vector2i(x, y - 1)) or open.has(Vector2i(x - 1, y - 1))


func _dress_tower(n: Node, roof: bool) -> void:
	## a sect's tower: grey dressed stone, a dark slate roof (not the kit's toy colours)
	if DisplayServer.get_name() == "headless":
		return
	var mat: Material
	if roof:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.16, 0.18, 0.21)
		sm.roughness = 0.7
		mat = sm
	else:
		mat = preload("res://scripts/world/Look.gd").surface(["old_stone_wall", [0.78, 0.75, 0.7], 0.6], 1.0)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = mat


func _aabb(n: Node) -> AABB:
	## the size of a model as built (unscaled), all its meshes together
	var out := AABB()
	var first := true
	var stack: Array = [[n, Transform3D()]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var xf: Transform3D = it[1]
		if node is Node3D and node != n:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			out = a if first else out.merge(a)
			first = false
		for c in node.get_children():
			stack.append([c, xf])
	return out


# ---- underground ------------------------------------------------------------------------------

func _rock() -> void:
	## the stone the halls are cut from, running on past every wall and
	## falling away into the dark at its edges
	var margin := int(_f("rock", "margin", 34))
	var drop_to := _f("rock", "drop", 26.0)
	var drop_from := _f("rock", "drop_from", 8.0)
	var lift_h := _f("rock", "lift", 0.35)
	var n := FastNoiseLite.new()
	n.seed = _rng.randi()
	n.frequency = 0.08
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var C: float = level.CELL
	var top: float = level.WALL_H + 0.03
	var cells := 0
	var near := {}
	for y in level.height:
		for x in str(level.grid[y]).length():
			var ch: String = level.char_at(Vector2i(x, y))
			if ch != " " and ch != "#":
				near[Vector2i(x, y)] = true      # (the walls' tops are under the rock too: one mass, the halls cut into it)
	var w: int = level.width
	var h: int = level.height
	var rw: int = w + margin * 2 + 2
	var vcache := PackedFloat32Array()
	vcache.resize(rw * (h + margin * 2 + 2))
	var vhave := PackedByteArray()
	vhave.resize(rw * (h + margin * 2 + 2))
	for cy in range(-margin, h + margin):
		for cx in range(-margin, w + margin):
			var c := Vector2i(cx, cy)
			if near.has(c):
				continue           # the halls and their walls
			var p := [Vector2(cx, cy), Vector2(cx + 1, cy), Vector2(cx + 1, cy + 1), Vector2(cx, cy + 1)]
			var v := []
			for q in p:
				# (w010: every corner's height is worked out once -- four cells share it)
				var qk: int = (int(q.y) + margin) * rw + int(q.x) + margin
				if not vhave[qk]:
					var out := maxf(maxf(-q.x, q.x - w), maxf(-q.y, q.y - h))
					var ragged := out + 7.0 * n.get_noise_2d(q.x * 0.35 + 50.0, q.y * 0.35)     # (an edge that isn't a ruler line)
					var drop := smoothstep(drop_from, float(margin), ragged) * drop_to          # the edge of the mass, falling away
					var lift := lift_h * (0.5 + 0.5 * n.get_noise_2d(q.x, q.y)) * (0.0 if _touches(near, q) else 1.0)
					vcache[qk] = top + lift - drop
					vhave[qk] = 1
				v.append(Vector3(q.x * C, vcache[qk], q.y * C))
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(v[i])
			cells += 1
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Rock"
	mi.mesh = st.commit()
	var wspec: Array = level.look.get("wall", ["rock_face", [0.6, 0.58, 0.56], 3.0])
	mi.material_override = preload("res://scripts/world/Look.gd").surface(["rock_face", wspec[1], 4.0], _f("rock", "dark", 0.42))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a faint cold light that reaches only this stone (its own render
	# layer): enough that the mass reads as rock running on, not a void
	var layer := clampi(int(_f("rock", "layer", 20)), 2, 20)
	mi.layers = 1 << (layer - 1)
	add_child(mi)
	var dl := DirectionalLight3D.new()
	dl.name = "RockLight"
	dl.light_cull_mask = 1 << (layer - 1)
	dl.light_color = preload("res://scripts/world/Look.gd").color3(_a("rock", "light_color", [0.62, 0.7, 0.85]), Color(0.62, 0.7, 0.85))
	dl.light_energy = _f("rock", "light", 0.45)
	dl.shadow_enabled = false
	dl.rotation_degrees = Vector3(-55, 30, 0)
	add_child(dl)
	state["rock_cells"] = cells
	_far_cavern()                  # round 63: and down here, the deep goes on
	# cracks with a glow far below: other caverns, out of reach
	var glow := Color(0.45, 0.8, 1.0)
	var lc: Array = level.look.get("light", [])
	if lc.size() >= 3:
		glow = Color(float(lc[0]), float(lc[1]), float(lc[2]))
	var made := 0
	for i in 40:
		if made >= int(_f("rock", "cracks", 7)):
			break
		var cx2 := _rng.randi_range(-margin + 4, w + margin - 4)
		var cy2 := _rng.randi_range(-margin + 4, h + margin - 4)
		if _touches(near, Vector2(cx2, cy2)) or _touches(near, Vector2(cx2 + 1, cy2 + 1)) or (cx2 >= -2 and cx2 <= w + 2 and cy2 >= -2 and cy2 <= h + 2 and _rng.randf() < 0.5):
			continue
		var at := Vector3(cx2 * C, top + 0.05, cy2 * C)
		var out2 := maxf(maxf(-cx2, cx2 - w), maxf(-cy2, cy2 - h))
		var rag2 := out2 + 7.0 * n.get_noise_2d(cx2 * 0.35 + 50.0, cy2 * 0.35)
		at.y += lift_h * (0.5 + 0.5 * n.get_noise_2d(cx2, cy2)) - smoothstep(drop_from, float(margin), rag2) * drop_to
		var crack := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(3.0, 7.0), 0.05, 0.18)
		crack.mesh = bm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = glow
		cm.emission_enabled = true
		cm.emission = glow
		cm.emission_energy_multiplier = 1.6
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		crack.material_override = cm
		crack.position = at
		crack.rotation.y = _rng.randf() * TAU
		add_child(crack)
		var l := OmniLight3D.new()
		l.light_color = glow
		l.light_energy = _f("rock", "crack_energy", 0.8)
		l.omni_range = 6.0
		l.position = at + Vector3(0, 0.6, 0)
		add_child(l)
		made += 1
	state["cracks"] = made


# ---- round 63: great distances ----------------------------------------------------------------
# Robert, 2026-10-05: "the sense of distance, smooth lines and curves -- I want
# the world to fit together like it belongs; we want the illusion of great
# distances even if the world game-wise is small."
# Under the sky: rings of far ranges, a kilometre and more out, each layer
# paler with the air between (far_ridge.gdshader), behind the hills that are
# really there. Underground: past the rock's broken edge, the dark opens into
# a cavern too big to see across -- columns going down into mist, and lights
# a long way off where others live.

var _ranges: Array = []
var _haze_t := 0.0


func _far_ranges() -> void:
	var F: Dictionary = cfg.get("far", {})
	var layers: Array = F.get("layers", [[520, 95, 0.32, 11.0], [900, 175, 0.58, 8.0], [1500, 300, 0.8, 6.0]])
	var b := _bounds()
	var center := b.get_center()
	var sh = load("res://assets/shaders/far_ridge.gdshader")
	var W = Game.sys("world")
	var frost: bool = W != null and not W.calm and W.season_id() == "frost"
	for i in layers.size():
		var L: Array = layers[i]
		var mi := MeshInstance3D.new()
		mi.name = "FarRange_%d" % i
		var cm := CylinderMesh.new()
		cm.top_radius = float(L[0])
		cm.bottom_radius = float(L[0])
		cm.height = float(L[1])
		cm.radial_segments = 128
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("far_k", float(L[2]))
		m.set_shader_parameter("freq", float(L[3]))
		m.set_shader_parameter("seed", float(i) * 3.7 + float(hash(level.level_id) % 97))
		m.set_shader_parameter("snow", (0.8 if frost else 0.45) * float(i) / maxf(1.0, float(layers.size() - 1)))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4000.0
		mi.position = Vector3(center.x, float(L[1]) / 2.0 + float(F.get("foot", -6.0)), center.y)
		add_child(mi)
		_ranges.append(m)
	state["far_ranges"] = layers.size()
	_update_haze()


func _update_haze() -> void:
	## the far ranges take the sky's air: day, dusk, night (WorldFX moves the fog colour)
	if _ranges.is_empty():
		return
	var env: Environment = level.get("_env")
	var hz: Color = env.fog_light_color if env else Color(0.74, 0.8, 0.88)
	var dl: float = Game.daylight()
	var base := Color(0.2, 0.25, 0.33).lerp(Color(0.04, 0.05, 0.09), 1.0 - dl)
	for m in _ranges:
		(m as ShaderMaterial).set_shader_parameter("haze", hz)
		(m as ShaderMaterial).set_shader_parameter("base", base)


func _process(delta: float) -> void:
	_haze_t -= delta
	if _haze_t <= 0.0:
		_haze_t = 2.0
		_update_haze()


func _far_cavern() -> void:
	if DisplayServer.get_name() == "headless" and not bool(cfg.get("far", {}).get("headless", false)):
		state["far_cavern"] = 0
		return
	var F: Dictionary = cfg.get("cavern", {})
	var b := _bounds()
	var center := b.get_center()
	var C: float = level.CELL
	var r0: float = maxf(b.size.x, b.size.y) * 0.5 + float(_f("rock", "margin", 34)) * C + float(F.get("gap", 18.0))
	var r1: float = r0 + float(F.get("depth", 260.0))
	var glow := Color(0.45, 0.8, 1.0)
	var lc: Array = level.look.get("light", [])
	if lc.size() >= 3:
		glow = Color(float(lc[0]), float(lc[1]), float(lc[2]))
	var top: float = level.WALL_H
	# columns: a few shapes, many copies (one draw each)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.03, 0.035, 0.05)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var col := CylinderMesh.new()
	col.top_radius = 0.6
	col.bottom_radius = 1.0
	col.height = 1.0
	col.radial_segments = 7
	col.rings = 1
	mm.mesh = col
	var n := int(F.get("columns", 70))
	mm.instance_count = n
	var mist := Color(0.08, 0.1, 0.14).lerp(glow * 0.25, 0.3)
	for i in n:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r0, r1)
		var k := (r - r0) / maxf(r1 - r0, 1.0)
		var hgt := _rng.randf_range(40.0, 120.0)
		var wid := _rng.randf_range(4.0, 14.0) * (1.0 + k)
		var t := Transform3D(Basis().scaled(Vector3(wid, hgt, wid)), Vector3(center.x + cos(a) * r, top - hgt * 0.5 + _rng.randf_range(-10.0, 25.0), center.y + sin(a) * r))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(0.03, 0.035, 0.05).lerp(mist, k * 0.85))
	dark.vertex_color_use_as_albedo = true
	var cols := MultiMeshInstance3D.new()
	cols.name = "FarColumns"
	cols.multimesh = mm
	cols.material_override = dark
	cols.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cols)
	# lights a long way off: others' fires, glowing pools -- points, no real light
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_3D
	lm.use_colors = true
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 6
	sp.rings = 3
	lm.mesh = sp
	var nl := int(F.get("lights", 26))
	lm.instance_count = nl
	for i in nl:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(r0 + 20.0, r1 + 80.0)
		var warm := _rng.randf() < 0.35
		var c := Color(1.0, 0.62, 0.3) if warm else glow
		var s := _rng.randf_range(0.8, 2.4)
		lm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(center.x + cos(a) * r, top - _rng.randf_range(10.0, 70.0), center.y + sin(a) * r)))
		lm.set_instance_color(i, c * _rng.randf_range(1.2, 2.6))
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.vertex_color_use_as_albedo = true
	var lights := MultiMeshInstance3D.new()
	lights.name = "FarLights"
	lights.multimesh = lm
	lights.material_override = lmat
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)
	# mist lying in the chasm below the rock's edge, paler the farther it goes
	var mp := MeshInstance3D.new()
	mp.name = "ChasmMist"
	var pm := PlaneMesh.new()
	pm.size = Vector2(r1 * 2.6, r1 * 2.6)
	mp.mesh = pm
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.albedo_color = Color(mist.r, mist.g, mist.b, float(F.get("mist", 0.55)))
	mp.material_override = mmat
	mp.position = Vector3(center.x, top - float(_f("rock", "drop", 26.0)) - 6.0, center.y)
	mp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mp)
	state["far_cavern"] = n
