extends RefCounted
## Armour (round 27): what you WEAR, made here from our own shapes and our own
## textures -- no downloaded models. Robert, 2026-10-03: "We can create some
## of our own assets ... an equipment dummy or screen with armour on it".
##
## Every piece is built from meshes pinned to the person's bones (the
## realistic figure, Human.gd: T-pose, metres, +x = their left, +z =
## forward), so it moves with every animation:
##   cowl + mantle (Head, neck), choker (neck), necklace + pendant (chest),
##   cape (upper back; it sways and streams out behind you as you move --
##   CapeSway.gd), pauldrons (upper arms), robe (torso, sleeves and a
##   flared skirt over everything), chest (a cuirass over the ribs and a
##   plackart over the belly), under-armour (a close layer and sleeves),
##   vambraces (forearms), bracelets (wrists), gloves / gauntlets (hands),
##   rings (the first joint of each finger -- four a hand), pants, greaves
##   (with knee cops), boots, toe rings.
## Each look -- cloth, leather, metal, bone, jade, nanoweave, lattice,
## swarm-shell -- has its own material and a texture drawn here from noise
## (brushed metal, grain, weave, circuit lines that glow for nano pieces).
## Looks only: Game.gd decides what a piece DOES.

const LOOKS := {
	"cloth": {"metal": 0.0, "rough": 0.95, "detail": "weave"},
	"leather": {"metal": 0.0, "rough": 0.72, "detail": "grain"},
	"metal": {"metal": 0.85, "rough": 0.38, "detail": "brushed"},
	"bone": {"metal": 0.0, "rough": 0.6, "detail": "grain"},
	"jade": {"metal": 0.1, "rough": 0.22, "detail": "cloud"},
	"nanoweave": {"metal": 0.3, "rough": 0.55, "detail": "weave", "glow": "circuit"},
	"lattice": {"metal": 0.75, "rough": 0.35, "detail": "brushed", "glow": "hex"},
	"shell": {"metal": 0.6, "rough": 0.3, "detail": "cloud", "glow": "hex"},
	"jewel": {"metal": 0.95, "rough": 0.2, "detail": ""},
}
const NANO_GLOW := Color(0.3, 0.9, 1.0)
## round 47 (Robert: "can the equipment be smoother, more realistic and not so
## blocky"): cloth and leather wear real photographed surfaces (Poly Haven,
## CC0 -- rough linen, worn leather), metal is finely brushed and scratched,
## and every piece is turned like the real thing (a breastplate that swells
## over the chest and nips in at the waist, greaves shaped to the calf,
## rolled rims on every edge) instead of straight tubes and boxes.
const PHOTO := {"cloth": ["rough_linen", 3.0], "leather": ["fabric_leather_02", 2.5], "nanoweave": ["rough_linen", 4.0]}
const TAG := "Armour_"

static var _tex := {}
static var _mats := {}


# ---- textures, drawn from noise -----------------------------------------------------

static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func detail(kind: String) -> ImageTexture:
	if kind == "" or _headless():
		return null
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	n.seed = hash(kind)
	var img: Image
	match kind:
		"brushed":
			# round 47: finer and bigger -- long brushing streaks, a soft
			# mottling where it's been worn, and a scatter of fine scratches
			n.noise_type = FastNoiseLite.TYPE_VALUE
			n.frequency = 0.9
			var mot := FastNoiseLite.new()
			mot.seed = 7
			mot.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			mot.frequency = 0.012
			mot.fractal_octaves = 3
			var sz := 512
			img = Image.create(sz, sz, false, Image.FORMAT_RGB8)
			for y in sz:
				var row := 0.86 + 0.1 * (0.5 + 0.5 * n.get_noise_2d(0.0, float(y) * 0.5))
				for x in sz:
					var v := row * (0.96 + 0.04 * n.get_noise_2d(float(x) * 0.02, float(y) * 3.0)) * (0.92 + 0.08 * mot.get_noise_2d(float(x), float(y)))
					img.set_pixel(x, y, Color(v, v, v))
			var rs := RandomNumberGenerator.new()
			rs.seed = 11
			for i in 140:
				var x0 := rs.randf() * sz
				var y0 := rs.randf() * sz
				var a := rs.randf() * TAU
				var ln := rs.randf_range(6.0, 40.0)
				for k in int(ln):
					var px := posmod(int(x0 + cos(a) * k), sz)
					var py := posmod(int(y0 + sin(a) * k), sz)
					img.set_pixel(px, py, Color(1.0, 1.0, 1.0) if i % 3 else Color(0.6, 0.6, 0.6))
		"grain":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.06
			n.fractal_octaves = 4
			img = n.get_image(128, 128, false, false, true)
			img.convert(Image.FORMAT_RGB8)
			img.adjust_bcs(1.0, 0.45, 1.0)
			_lighten(img, 0.55)
		"cloud":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.04
			img = n.get_image(128, 128, false, false, true)
			img.convert(Image.FORMAT_RGB8)
			_lighten(img, 0.75)
		"weave":
			img = Image.create(128, 128, false, Image.FORMAT_RGB8)
			n.frequency = 0.2
			for y in 128:
				for x in 128:
					var over := ((x / 2) + (y / 2)) % 2 == 0
					var v := (0.86 if over else 0.74) + 0.08 * n.get_noise_2d(float(x), float(y))
					img.set_pixel(x, y, Color(v, v, v))
		"circuit", "hex":
			img = Image.create(128, 128, false, Image.FORMAT_RGB8)
			img.fill(Color.BLACK)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(kind)
			if kind == "circuit":
				for i in 26:
					var x := rng.randi_range(0, 127)
					var y := rng.randi_range(0, 127)
					var horiz := rng.randf() < 0.5
					for k in rng.randi_range(12, 50):
						img.set_pixel(posmod(x + (k if horiz else 0), 128), posmod(y + (0 if horiz else k), 128), Color.WHITE)
					img.fill_rect(Rect2i(posmod(x, 128), posmod(y, 128), 3, 3), Color.WHITE)
			else:
				for y in 128:
					for x in 128:
						var cx := float(x % 32) - 16.0
						var cy := float(y % 28) - 14.0
						var d := maxf(absf(cx) * 0.866 + absf(cy) * 0.5, absf(cy))
						if absf(d - 13.0) < 0.9:
							img.set_pixel(x, y, Color.WHITE)
		_:
			return null
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func _lighten(img: Image, floor_v: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			v = floor_v + (1.0 - floor_v) * v
			img.set_pixel(x, y, Color(v, v, v))


static func normal_for(kind: String) -> ImageTexture:
	if kind == "" or _headless():
		return null
	var key := "n_" + kind
	if _tex.has(key):
		return _tex[key]
	var d := detail(kind)
	if d == null:
		return null
	var img := d.get_image().duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(3.0)
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func material(look: String, c: Color, make: String = "crafted", glow_c = null) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [look, c.to_html(), make, str(glow_c)]
	if _mats.has(key):
		return _mats[key]
	var L: Dictionary = LOOKS.get(look, LOOKS["cloth"])
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if look in ["cloth", "nanoweave", "leather"] and c.get_luminance() > 0.82:
		m.albedo_color = c * (0.82 / c.get_luminance())      # (white silk under a bright sun burned out to a flat glare)
		m.albedo_color.a = 1.0
	m.metallic = float(L["metal"])
	m.roughness = float(L["rough"])
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if look in ["cloth", "nanoweave"] else BaseMaterial3D.CULL_BACK
	var det := detail(str(L.get("detail", "")))
	var photo: Array = PHOTO.get(look, [])
	var LK := preload("res://scripts/world/Look.gd")
	if not photo.is_empty() and not _headless() and LK.texture(str(photo[0]), "albedo") != null:
		det = null
		m.albedo_texture = LK.texture(str(photo[0]), "albedo")
		var pn: Texture2D = LK.texture(str(photo[0]), "normal")
		if pn:
			m.normal_enabled = true
			m.normal_texture = pn
			m.normal_scale = 1.0
		var pa: Texture2D = LK.texture(str(photo[0]), "arm")
		if pa:
			m.roughness_texture = pa
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.ao_enabled = true
			m.ao_texture = pa
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * float(photo[1])
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if det:
		m.albedo_texture = det
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * (3.0 if look in ["metal", "lattice"] else 6.0)
		if look in ["metal", "lattice"]:
			m.roughness_texture = det          # scratches and worn spots catch the light differently
			m.roughness = 0.45
		var nm := normal_for(str(L.get("detail", "")))
		if nm:
			m.normal_enabled = true
			m.normal_texture = nm
			m.normal_scale = 0.6
	var glow := str(L.get("glow", ""))
	if make in ["nano", "both"] and glow == "":
		glow = "circuit"
	if glow != "" and make in ["nano", "both"]:
		m.emission_enabled = true
		m.emission = NANO_GLOW
		m.emission_energy_multiplier = 2.2 if make == "nano" else 1.3
		var gt := detail(glow)
		if gt:
			m.emission_texture = gt
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY     # glow only along the lines
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 6.0
	if glow_c is Color:
		m.emission_enabled = true
		m.emission = glow_c
		m.emission_energy_multiplier = 0.6
	if look == "jade":
		m.rim_enabled = true
		m.rim = 0.4
	if look == "shell":
		m.rim_enabled = true
		m.rim = 0.6
		m.rim_tint = 0.8
	_mats[key] = m
	return m


# ---- shapes ----------------------------------------------------------------------------

static func _legskin(sk: Skeleton3D, mesh: Mesh, mat: Material, at: Vector3, basis: Basis, tag: String) -> Node3D:
	## r149 (Robert: "legs are bleeding through the robe"): a skirt skinned to the pelvis and
	## both thighs, so it swings with each stride instead of standing rigid while the legs
	## push through it. `at`/`basis` place the mesh in the pelvis's own body axes, as _mount does.
	var ip := sk.find_bone("pelvis")
	var il := sk.find_bone("thigh_l")
	var ir := sk.find_bone("thigh_r")
	if ip < 0 or il < 0 or ir < 0:
		return null
	var origin: Vector3 = sk.get_bone_global_rest(ip).origin
	var nb := basis.inverse().transposed()
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n := vs.size()
		var nvs := PackedVector3Array()
		nvs.resize(n)
		var bones := PackedInt32Array()
		bones.resize(n * 4)
		var wts := PackedFloat32Array()
		wts.resize(n * 4)
		for k in n:
			var lp: Vector3 = basis * vs[k] + at
			nvs[k] = origin + lp
			var d := smoothstep(0.0, 0.3, -lp.y)
			var wl := smoothstep(-0.1, 0.1, lp.x)
			bones[k * 4] = ip
			bones[k * 4 + 1] = il
			bones[k * 4 + 2] = ir
			wts[k * 4] = 1.0 - d
			wts[k * 4 + 1] = d * wl
			wts[k * 4 + 2] = d * (1.0 - wl)
		arr[Mesh.ARRAY_VERTEX] = nvs
		if arr[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for k in ns.size():
				ns[k] = (nb * ns[k]).normalized()
			arr[Mesh.ARRAY_NORMAL] = ns
		if arr[Mesh.ARRAY_TANGENT] != null:
			var ts: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for k in n:
				var tv := (basis * Vector3(ts[k * 4], ts[k * 4 + 1], ts[k * 4 + 2])).normalized()
				ts[k * 4] = tv.x
				ts[k * 4 + 1] = tv.y
				ts[k * 4 + 2] = tv.z
			arr[Mesh.ARRAY_TANGENT] = ts
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = wts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.custom_aabb = AABB(origin - Vector3(1.2, 1.6, 1.2), Vector3(2.4, 2.4, 2.4))
	var name := "Dress_" + TAG + tag
	var old := sk.get_node_or_null(NodePath(name))
	if old:
		old.free()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = out
	mi.material_override = mat
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	return mi


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, basis: Basis = Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, at)
	parent.add_child(mi)
	return mi


static func _tube(r_top: float, r_bot: float, h: float, seg: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = maxi(seg * 2, 28)        # round 47: round, not faceted
	c.rings = 4
	return c


static var _lathes := {}


static func _lathe(profile: Array, seg: int = 36, open_ends: bool = true) -> ArrayMesh:
	## a shell turned on a lathe: profile = [[y, r], ...] from top to bottom,
	## smooth all the way round (round 47: armour that swells and tapers like
	## the real thing, not a straight tube)
	var key := "%s|%d" % [str(profile), seg]
	if _lathes.has(key):
		return _lathes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for i in n - 1:
		for j in seg:
			for q in [[0, 0], [1, 1], [1, 0], [0, 0], [0, 1], [1, 1]]:
				var pr: Array = profile[i + q[0]]
				var a := TAU * float(j + q[1]) / seg
				st.set_uv(Vector2(float(j + q[1]) / seg, float(i + q[0]) / (n - 1)))
				st.add_vertex(Vector3(sin(a) * float(pr[1]), float(pr[0]), cos(a) * float(pr[1])))
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var m := st.commit()
	_lathes[key] = m
	return m


static func _shape(length: float, r_top: float, r_mid: float, r_bot: float, flare_top: float = 0.0, flare_bot: float = 0.0, steps: int = 12) -> Array:
	## a profile for a limb piece: from r_top to r_bot over `length`, swelling
	## to r_mid in the middle, each end turned out a little (a rolled edge)
	var out := []
	for i in steps + 1:
		var t := float(i) / steps
		var r := lerpf(r_top, r_bot, t) + (r_mid - lerpf(r_top, r_bot, 0.5)) * sin(PI * t)
		if t < 0.12:
			r += flare_top * (1.0 - t / 0.12)
		if t > 0.88:
			r += flare_bot * ((t - 0.88) / 0.12)
		out.append([length * (0.5 - t), r])
	return out


static func _rim(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 40
	t.ring_segments = 10
	return t


static func _dome(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r
	s.is_hemisphere = true
	s.radial_segments = 36
	s.rings = 14
	return s


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	return s


static func _ring(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 32
	t.ring_segments = 10
	return t


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _along(v: Vector3) -> Basis:
	## a basis whose y axis points along v (cylinders and tori are built on y)
	var d := v.normalized()
	if d.length() < 0.01:
		return Basis()
	if absf(d.dot(Vector3.UP)) > 0.999:
		return Basis() if d.y > 0 else Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, d))


static func _hood(r: float, open_deg: float = 62.0, brow_deg: float = 58.0, low_deg: float = 128.0) -> ArrayMesh:
	## a hood: a sphere around the head, open over the face (within open_deg
	## of straight ahead and below the brow), running down past the jaw at
	## the back and sides
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 28
	var rows := 14
	for i in rows:
		for j in cols:
			var corners := []
			var keep := true
			for q in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var phi := deg_to_rad(low_deg) * float(i + q[0]) / rows          # 0 = top of the head
				var th := TAU * float(j + q[1]) / cols                           # 0 = straight ahead
				var face_open := absf(wrapf(rad_to_deg(th), -180.0, 180.0)) < open_deg and rad_to_deg(phi) > brow_deg
				if face_open:
					keep = false
				var low := clampf((rad_to_deg(phi) - 80.0) / 70.0, 0.0, 1.0)
				var rr := r * (1.0 + 0.75 * pow(low, 1.4))                       # it falls open over the neck and shoulders
				var y := cos(phi) * r * 1.15 - 0.06 * low
				var peak := -0.035 * clampf(1.0 - rad_to_deg(phi) / 35.0, 0.0, 1.0)  # a soft point at the back of the crown
				corners.append(Vector3(sin(phi) * sin(th) * rr, y, sin(phi) * cos(th) * rr + peak))
			if keep:
				for v in corners:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _sheet(w_top: float, w_bot: float, length: float, curve: float, flare: float, cols: int = 8, rows: int = 10) -> ArrayMesh:
	## a cape: a curved sheet hanging down from its top edge (y = 0 .. -length),
	## wrapped a little round the back and flaring out behind as it falls
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		for c in cols:
			for q in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var u := float(c + q[0]) / cols
				var v := float(r + q[1]) / rows
				var w := lerpf(w_top, w_bot, v)
				var x := (u - 0.5) * w
				var z := -curve * (1.0 - pow(2.0 * u - 1.0, 2.0)) - flare * v * v
				z += 0.016 * sin(u * TAU * 4.0) * v + 0.006 * sin(u * TAU * 9.0 + v * 3.0) * v      # soft folds that deepen toward the hem
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(x, -v * length, z))
	st.generate_normals()
	return st.commit()


# ---- dressing ------------------------------------------------------------------------

static func dress_gear(model: Node, pieces: Array) -> void:
	## pieces: [{"family", "look", "color", "make", "gem_color"}] -- what's worn
	var D := preload("res://scripts/world/Dress.gd")
	var sk: Skeleton3D = D.skeleton(model)
	if sk == null:
		return
	for c in sk.get_children():
		if str(c.name).begins_with("Dress_" + TAG):
			c.free()
	var hooded := false
	for p in pieces:
		if str(p.get("family", "")) == "cowl":
			hooded = true
	for hn in model.find_children("Hair_*", "", true, false):
		if not str(hn.name).contains("Beard") and hn is Node3D:
			(hn as Node3D).visible = not hooded          # a hood covers the hair
	if sk.find_bone("pelvis") < 0:
		_dress_simple(sk, pieces)
		return
	var fingers_l := ["index_01_l", "middle_01_l", "ring_01_l", "pinky_01_l"]
	var fingers_r := ["index_01_r", "middle_01_r", "ring_01_r", "pinky_01_r"]
	for p in pieces:
		var fam := str(p.get("family", ""))
		var col := D._c(p.get("color", [0.5, 0.5, 0.5]))
		var look := str(p.get("look", "metal"))
		var make := str(p.get("make", "crafted"))
		var mat := material(look, col, make)
		match fam:
			"cowl":
				var h := _mount(sk, "Head", "cowl")
				var hm := material(look if look in ["cloth", "leather", "nanoweave"] else "cloth", col, make)
				_mi(h, _hood(0.138, 50.0, 64.0, 150.0), hm, Vector3(0, 0.1, -0.03))
				var n := _mount(sk, "neck_01", "mantle")
				_mi(n, _tube(0.1, 0.17, 0.1, 22), hm, Vector3(0, -0.07, -0.03), Basis().scaled(Vector3(1.0, 1.0, 0.8)))    # where the hood meets the shoulders
			"choker":
				var n2 := _mount(sk, "neck_01", "choker")
				_mi(n2, _ring(0.058, 0.007), material("jewel", col, make), Vector3(0, 0.045, 0.01), Basis(Vector3.RIGHT, 0.15))
			"necklace":
				var c3 := _mount(sk, "spine_03", "necklace")
				_mi(c3, _ring(0.095, 0.004), material("jewel", col, make), Vector3(0, 0.17, 0.035), Basis(Vector3.RIGHT, 0.55))
				_mi(c3, _ball(0.016), material("jade", D._c(p.get("gem_color", [0.9, 0.9, 0.9])), make, D._c(p.get("gem_color", [0.9, 0.9, 0.9]))), Vector3(0, 0.1, 0.135))
			"cape":
				var back := _mount(sk, "spine_03", "cape")
				var pivot := Node3D.new()
				pivot.name = "CapePivot"
				pivot.position = Vector3(0, 0.17, -0.11)
				pivot.set_script(preload("res://scripts/actors/CapeSway.gd"))
				back.add_child(pivot)
				var capem: StandardMaterial3D = material(look if look in ["cloth", "leather", "nanoweave"] else "cloth", col, make).duplicate()
				capem.cull_mode = BaseMaterial3D.CULL_DISABLED      # r149: a cape is seen from every side (leather was one-sided: gone from behind)
				_mi(pivot, _sheet(0.4, 0.6, 1.1, 0.07, 0.07, 16, 18), capem, Vector3.ZERO)
			"pauldrons":
				for side in [1.0, -1.0]:
					var ua := _mount(sk, "upperarm_l" if side > 0 else "upperarm_r", "pauldron_%s" % ("l" if side > 0 else "r"))
					var tilt := Basis(Vector3.FORWARD, -0.55 * side)
					# a cap over the shoulder and two overlapping lames below it, each with a rolled edge
					for k in 3:
						var rr: float = [0.095, 0.086, 0.077][k]
						var at := Vector3([0.02, 0.06, 0.1][k] * side, [0.03, -0.012, -0.045][k], 0.0)
						var sc := Vector3([1.0, 0.95, 0.9][k], [0.62, 0.5, 0.42][k], [1.12, 1.08, 1.04][k])
						_mi(ua, _dome(rr), mat, at, tilt.scaled(sc))
						_mi(ua, _rim(rr, 0.0045), mat, at, tilt.scaled(Vector3(sc.x, 1.0, sc.z)))
			"robe":
				var t2 := _mount(sk, "spine_02", "robe_torso")
				# round 47: the robe falls from the shoulders, gathers at the waist and
				# flares to the hem -- one flowing line, no step at the belt
				var rt := [[0.29, 0.13], [0.26, 0.175], [0.2, 0.19], [0.1, 0.192], [0.0, 0.186], [-0.1, 0.18], [-0.15, 0.182]]
				_mi(t2, _lathe(rt, 44), mat, Vector3(0, 0.0, 0.0), Basis().scaled(Vector3(1.0, 1.0, 0.8)))
				var pv := _mount(sk, "pelvis", "robe_skirt")
				var sk_prof := []
				for i in 15:
					var t := float(i) / 14.0
					sk_prof.append([0.08 - 0.68 * t, 0.2 + 0.17 * pow(t, 1.4) + 0.008 * sin(t * 30.0) * t])
				var skb := Basis().scaled(Vector3(1.0, 1.0, 0.92))
				if _legskin(sk, _lathe(sk_prof, 48), mat, Vector3.ZERO, skb, "robe_skirt_skin") == null:
					_mi(pv, _lathe(sk_prof, 48), mat, Vector3(0, 0.0, 0.0), skb)
				if _legskin(sk, _rim(0.372, 0.008), mat, Vector3(0, -0.6, 0.0), skb, "robe_hem_skin") == null:
					_mi(pv, _rim(0.372, 0.008), mat, Vector3(0, -0.6, 0.0), skb)    # the hem
				for side in ["l", "r"]:
					var la := _mount(sk, "lowerarm_" + side, "robe_sleeve_" + side)
					var seg := _seg(sk, "lowerarm_" + side, "hand_" + side)
					_mi(la, _lathe(_shape(seg.length() * 0.8, 0.064, 0.075, 0.1, 0.0, 0.008)), mat, seg * 0.45, _along(-seg))     # a sleeve that widens to the wrist
					var ua2 := _mount(sk, "upperarm_" + side, "robe_upper_" + side)
					var seg2 := _seg(sk, "upperarm_" + side, "lowerarm_" + side)
					_mi(ua2, _tube(0.078, 0.084, seg2.length() * 1.05, 14), mat, seg2 * 0.48, _along(seg2))
					_mi(ua2, _dome(0.085), mat, Vector3(0.0, 0.02, 0.0), Basis().scaled(Vector3(1.0, 0.7, 1.0)))      # over the shoulder
			"armor":
				var t3 := _mount(sk, "spine_02", "cuirass")
				# a breastplate turned to the body: narrow at the collar, full over the
				# chest, nipped at the waist, a rolled rim top and bottom
				var cu := [[0.21, 0.128], [0.19, 0.152], [0.15, 0.17], [0.1, 0.178], [0.05, 0.176], [0.0, 0.17], [-0.05, 0.162], [-0.1, 0.156], [-0.14, 0.158]]
				var ell := Basis().scaled(Vector3(1.0, 1.0, 0.8))
				_mi(t3, _lathe(cu, 44), mat, Vector3(0, 0.0, 0.005), ell)
				_mi(t3, _rim(0.13, 0.006), mat, Vector3(0, 0.21, 0.005), ell)
				_mi(t3, _rim(0.159, 0.007), mat, Vector3(0, -0.14, 0.005), ell)
				_mi(t3, _dome(0.15), mat, Vector3(0, 0.07, 0.06), Basis(Vector3.RIGHT, PI / 2) * Basis.from_scale(Vector3(1.0, 0.32, 1.15)))   # the breastplate's swell
				var ridge := CapsuleMesh.new()
				ridge.radius = 0.006
				ridge.height = 0.26
				_mi(t3, ridge, mat, Vector3(0, 0.05, 0.135), Basis(Vector3.RIGHT, -0.12))          # the ridge down the front
				var t4 := _mount(sk, "spine_01", "plackart")
				var pk := _shape(0.16, 0.158, 0.162, 0.17, 0.0, 0.01, 8)
				_mi(t4, _lathe(pk, 40), mat, Vector3(0, -0.03, 0.0), Basis().scaled(Vector3(1.0, 1.0, 0.8)))
				_mi(t4, _rim(0.178, 0.006), mat, Vector3(0, -0.11, 0.0), Basis().scaled(Vector3(1.0, 1.0, 0.8)))
			"underarmour":
				var t5 := _mount(sk, "spine_02", "under")
				_mi(t5, _tube(0.16, 0.152, 0.44, 20), mat, Vector3(0, 0.04, 0.0), Basis().scaled(Vector3(1.0, 1.0, 0.76)))
				for side in ["l", "r"]:
					var ua3 := _mount(sk, "upperarm_" + side, "under_sleeve_" + side)
					var seg3 := _seg(sk, "upperarm_" + side, "lowerarm_" + side)
					_mi(ua3, _tube(0.06, 0.054, seg3.length() * 0.9, 12), mat, seg3 * 0.5, _along(seg3))
			"vambraces":
				for side in ["l", "r"]:
					var la2 := _mount(sk, "lowerarm_" + side, "vambrace_" + side)
					var seg4 := _seg(sk, "lowerarm_" + side, "hand_" + side)
					var vl := seg4.length() * 0.72
					# wide at the elbow, shaped to the forearm, narrow at the wrist; rolled edges
					_mi(la2, _lathe(_shape(vl, 0.054, 0.052, 0.042, 0.006, 0.004)), mat, seg4 * 0.55, _along(-seg4))
					_mi(la2, _rim(0.06, 0.004), mat, seg4 * 0.55 - seg4.normalized() * vl * 0.5, _along(seg4))
					_mi(la2, _rim(0.046, 0.0035), mat, seg4 * 0.55 + seg4.normalized() * vl * 0.5, _along(seg4))
			"gloves", "gauntlets":
				var big := fam == "gauntlets"
				for side in ["l", "r"]:
					var hd := _mount(sk, "hand_" + side, fam + "_" + side)
					var seg5 := _seg(sk, "hand_" + side, "middle_01_" + side)
					var len5 := seg5.length() + 0.012
					var palm := CapsuleMesh.new()
					palm.radius = 0.024 if big else 0.02
					palm.height = len5 + 0.02
					palm.radial_segments = 12
					palm.rings = 4
					# the back and palm of the hand (the fingers left free to grip)
					_mi(hd, palm, mat, seg5.normalized() * len5 * 0.5, _along(seg5) * Basis.from_scale(Vector3(1.9, 1.0, 1.0)))
					if big:
						_mi(hd, _lathe(_shape(0.085, 0.066, 0.056, 0.046, 0.005, 0.0, 8)), mat, -seg5.normalized() * 0.015, _along(-seg5))    # the flared cuff
						var kn := CapsuleMesh.new()
						kn.radius = 0.014
						kn.height = 0.088
						_mi(hd, kn, mat, seg5.normalized() * (len5 * 0.92) + Vector3(0, 0.02, 0), Basis(Vector3.FORWARD, PI / 2))    # knuckles
			"bracelet":
				var side_b := "r" if str(p.get("slot", "")).ends_with("_r") else "l"
				var wr := _mount(sk, "hand_" + side_b, "bracelet_" + side_b)
				var segb := _seg(sk, "lowerarm_" + side_b, "hand_" + side_b)
				_mi(wr, _ring(0.046, 0.007), material("jewel", col, make, D._c(p.get("gem_color", [0.9, 0.9, 0.9])) if make != "crafted" else null),
					-segb.normalized() * 0.025, _along(segb))
			"ring":
				var sl := str(p.get("slot", "ring_l1"))
				var hand := "r" if sl.begins_with("ring_r") else "l"
				var k := clampi(int(sl.right(1)) - 1, 0, 3)
				var fing: String = (fingers_l if hand == "l" else fingers_r)[k]
				var nxt := fing.replace("_01_", "_02_")
				var fr := _mount(sk, fing, "ring_" + fing)
				var segr := _seg(sk, fing, nxt)
				_mi(fr, _ring(0.0115, 0.0035), material("jewel", col, make, D._c(p.get("gem_color", [0.9, 0.9, 0.9]))), segr * 0.5, _along(segr))
			"pants":
				var pv2 := _mount(sk, "pelvis", "pants_band")
				_mi(pv2, _tube(0.165, 0.17, 0.14, 20), mat, Vector3(0, -0.02, 0.01), Basis().scaled(Vector3(1.0, 1.0, 0.82)))
				for side in ["l", "r"]:
					var th := _mount(sk, "thigh_" + side, "pants_thigh_" + side)
					var segt := _seg(sk, "thigh_" + side, "calf_" + side)
					_mi(th, _tube(0.104, 0.082, segt.length() * 0.98, 14), mat, segt * 0.5, _along(-segt))
					var cf := _mount(sk, "calf_" + side, "pants_calf_" + side)
					var segc := _seg(sk, "calf_" + side, "foot_" + side)
					_mi(cf, _tube(0.074, 0.06, segc.length() * 0.95, 14), mat, segc * 0.5, _along(-segc))
			"greaves":
				for side in ["l", "r"]:
					var cf2 := _mount(sk, "calf_" + side, "greave_" + side)
					var segg := _seg(sk, "calf_" + side, "foot_" + side)
					var gl := segg.length() * 0.8
					# shaped to the calf: full below the knee, slim at the ankle, rolled at both ends
					_mi(cf2, _lathe(_shape(gl, 0.068, 0.074, 0.054, 0.006, 0.006)), mat, segg * 0.52, _along(-segg))
					_mi(cf2, _rim(0.074, 0.005), mat, segg * 0.52 - segg.normalized() * gl * 0.5, _along(segg))
					_mi(cf2, _rim(0.06, 0.0045), mat, segg * 0.52 + segg.normalized() * gl * 0.5, _along(segg))
					_mi(cf2, _dome(0.055), mat, Vector3(0, 0.0, 0.045), Basis(Vector3.RIGHT, PI / 2).scaled(Vector3(1.0, 0.7, 1.0)))     # the knee cop
					_mi(cf2, _rim(0.055, 0.004), mat, Vector3(0, 0.0, 0.045), Basis(Vector3.RIGHT, PI / 2))
			"boots":
				for side in ["l", "r"]:
					var ft := _mount(sk, "foot_" + side, "boot_" + side)
					var segf := _seg(sk, "foot_" + side, "ball_leaf_" + side)
					var flat := Vector3(segf.x, 0.0, segf.z)
					var fl := flat.length()
					# a rounded foot (heel to toe), a sole that follows it, an ankle
					var foot := SphereMesh.new()
					foot.radius = 0.5
					foot.height = 1.0
					foot.radial_segments = 32
					foot.rings = 16
					var flen := fl + 0.1
					_mi(ft, foot, mat, Vector3(0, -0.04, fl * 0.5 - 0.02), Basis().scaled(Vector3(0.115, 0.1, flen)))
					var sole := CylinderMesh.new()
					sole.top_radius = 0.5
					sole.bottom_radius = 0.5
					sole.height = 1.0
					sole.radial_segments = 32
					_mi(ft, sole, material("leather", Color(0.16, 0.12, 0.09)), Vector3(0, -0.084, fl * 0.5 - 0.02), Basis().scaled(Vector3(0.112, 0.016, flen * 0.98)))   # the sole
					var cf3 := _mount(sk, "calf_" + side, "boot_shaft_" + side)
					var segs := _seg(sk, "calf_" + side, "foot_" + side)
					# the shaft: snug at the ankle, wider at the top, the top turned down in a cuff
					_mi(cf3, _lathe(_shape(0.27, 0.084, 0.078, 0.066, 0.008, 0.0)), mat, segs * 0.8, _along(-segs))
					_mi(cf3, _rim(0.086, 0.012), mat, segs * 0.8 - segs.normalized() * 0.13, _along(segs))      # the turned-down cuff
					_mi(cf3, _ring(0.081, 0.006), material("leather", Color(0.16, 0.12, 0.09)), segs * 0.72, _along(-segs))    # the strap
			"toering":
				var side_t := "r" if str(p.get("slot", "")).ends_with("_r") else "l"
				var tb := _mount(sk, "ball_" + side_t, "toering_" + side_t)
				_mi(tb, _ring(0.016, 0.004), material("jewel", col, make, D._c(p.get("gem_color", [0.9, 0.9, 0.9]))), Vector3(0.02 if side_t == "l" else -0.02, 0.012, 0.035), Basis(Vector3.RIGHT, PI / 2))
		if p.get("design", null) is Dictionary and not (p["design"] as Dictionary).is_empty():
			_design_extras(sk, p, fam, make)


static func _design_extras(sk: Skeleton3D, p: Dictionary, fam: String, make: String) -> void:
	## a designed piece: trim in its own metal, studs / wirework / flares / glowing lines
	var D := preload("res://scripts/world/Dress.gd")
	var ds: Dictionary = p["design"]
	var look := str(ds.get("look", ""))
	var tcol := D._c(ds["trim_color"]) if ds.has("trim_color") else Color(0, 0, 0, 0)
	var has_trim := ds.has("trim_color")
	var tm: StandardMaterial3D = material("metal", tcol, make) if has_trim else null
	var gc: Color = D._c(ds["glow"]) if ds.has("glow") else Color(0.5, 0.95, 1.0)
	var em: StandardMaterial3D = material("jade", gc, make, gc) if ds.has("glow") else null
	var body := D._c(p.get("color", [0.5, 0.5, 0.5]))
	var bm := material("metal", body.lightened(0.15), make)
	match fam:
		"armor":
			var t := _mount(sk, "spine_02", "d_cuirass")
			var ell := Basis().scaled(Vector3(1.0, 1.0, 0.8))
			if has_trim:
				_mi(t, _rim(0.134, 0.009), tm, Vector3(0, 0.215, 0.005), ell)
				_mi(t, _rim(0.163, 0.01), tm, Vector3(0, -0.145, 0.005), ell)
			match look:
				"studs":
					for row in 2:
						for i in 7:
							var ang := (float(i) / 6.0 - 0.5) * 1.5
							_mi(t, _ball(0.011), bm, Vector3(sin(ang) * 0.17, 0.12 - row * 0.1, cos(ang) * 0.17 * 0.8 + 0.005))
				"filigree":
					for k in 3:
						_mi(t, _rim(0.15 - k * 0.012, 0.0028), tm if has_trim else bm, Vector3(0, 0.1 - k * 0.07, 0.005), ell)
				"flare":
					_mi(t, _rim(0.19, 0.016), bm, Vector3(0, -0.155, 0.005), ell)
					_mi(t, _rim(0.215, 0.012), bm, Vector3(0, -0.19, 0.005), ell)
				"runic":
					if em != null:
						var ridge := CapsuleMesh.new()
						ridge.radius = 0.004
						ridge.height = 0.3
						_mi(t, ridge, em, Vector3(0, 0.03, 0.138), Basis(Vector3.RIGHT, -0.12))
						_mi(t, _rim(0.168, 0.0035), em, Vector3(0, 0.0, 0.005), ell)
						_mi(t, _rim(0.15, 0.0035), em, Vector3(0, 0.12, 0.005), ell)
		"pauldrons":
			for side in [1.0, -1.0]:
				var ua := _mount(sk, "upperarm_l" if side > 0 else "upperarm_r", "d_pauldron_%s" % ("l" if side > 0 else "r"))
				var tilt := Basis(Vector3.FORWARD, -0.55 * side)
				if has_trim:
					_mi(ua, _rim(0.1, 0.006), tm, Vector3(0.1 * side, -0.05, 0.0), tilt.scaled(Vector3(0.9, 1.0, 1.04)))
				if look == "studs":
					for i in 3:
						_mi(ua, _ball(0.009), bm, Vector3((0.01 + i * 0.03) * side, 0.06 - i * 0.012, 0.07))
				elif look == "flare":
					_mi(ua, _rim(0.1, 0.012), bm, Vector3(0.11 * side, -0.07, 0.0), tilt.scaled(Vector3(1.0, 1.0, 1.15)))
				elif look == "runic" and em != null:
					_mi(ua, _rim(0.09, 0.003), em, Vector3(0.06 * side, -0.01, 0.0), tilt.scaled(Vector3(1.0, 1.0, 1.1)))
		"robe":
			var pv := _mount(sk, "pelvis", "d_robe_skirt")
			var sc := Basis().scaled(Vector3(1.0, 1.0, 0.92))
			if has_trim:
				if _legskin(sk, _rim(0.376, 0.011), tm, Vector3(0, -0.6, 0.0), sc, "d_trim_hem") == null:
					_mi(pv, _rim(0.376, 0.011), tm, Vector3(0, -0.6, 0.0), sc)
			if look == "filigree":
				if _legskin(sk, _rim(0.33, 0.003), tm if has_trim else bm, Vector3(0, -0.5, 0.0), sc, "d_trim_fil") == null:
					_mi(pv, _rim(0.33, 0.003), tm if has_trim else bm, Vector3(0, -0.5, 0.0), sc)
			elif look == "runic" and em != null:
				if _legskin(sk, _rim(0.35, 0.004), em, Vector3(0, -0.55, 0.0), sc, "d_trim_run") == null:
					_mi(pv, _rim(0.35, 0.004), em, Vector3(0, -0.55, 0.0), sc)
		"vambraces", "gloves", "gauntlets":
			for side in ["l", "r"]:
				var la := _mount(sk, "lowerarm_" + side, "d_vambrace_" + side)
				var seg := _seg(sk, "lowerarm_" + side, "hand_" + side)
				if has_trim:
					_mi(la, _rim(0.062, 0.006), tm, seg * 0.55 - seg.normalized() * seg.length() * 0.36, _along(seg))
				if look == "studs":
					_mi(la, _ball(0.009), bm, seg * 0.5 + Vector3(0, 0.05, 0.03))
				elif look == "runic" and em != null:
					_mi(la, _rim(0.052, 0.0028), em, seg * 0.55, _along(seg))


static func _mount(sk: Skeleton3D, bone: String, tag: String) -> Node3D:
	return preload("res://scripts/world/Dress.gd")._human_mount(sk, bone, TAG + tag)


static func _seg(sk: Skeleton3D, a: String, b: String) -> Vector3:
	var i := sk.find_bone(a)
	var j := sk.find_bone(b)
	if i < 0 or j < 0:
		return Vector3(0, -0.25, 0)
	return sk.get_bone_global_rest(j).origin - sk.get_bone_global_rest(i).origin


static func _dress_simple(sk: Skeleton3D, pieces: Array) -> void:
	## the Kenney figure (Low graphics -- the phone): the big pieces only, so you can still see what you're wearing.
	## Sizes are the figure's own (Dress.gd): the torso bone sits at the hips, the chest is ~0.19 tall above it, the head
	## bone is at the neck, the arms run out sideways from the shoulder, the legs hang from the hip bones.
	var D := preload("res://scripts/world/Dress.gd")
	for p in pieces:
		var fam := str(p.get("family", ""))
		var col: Color = D._c(p.get("color", [0.5, 0.5, 0.5]))
		var mat := material(str(p.get("look", "metal")), col, str(p.get("make", "crafted")))
		match fam:
			"cowl":
				var h: Node3D = D._attach(sk, D.HEAD, TAG + "cowl")
				_mi(h, _dome(0.31), mat, Vector3(0, 0.2, -0.02), Basis().scaled(Vector3(1.0, 0.95, 1.0)))     # a hood round the skull (head is ~0.41 tall)
			"cape":
				var t: Node3D = D._attach(sk, D.TORSO, TAG + "cape")
				_mi(t, _box(0.3, 0.3, 0.02), mat, Vector3(0, 0.05, -0.15))
			"pauldrons":
				for side in [1.0, -1.0]:
					var a: Node3D = D._attach(sk, D.ARM_L if side > 0 else D.ARM_R, TAG + "pauldron_%d" % int(side))
					_mi(a, _box(0.12, 0.05, 0.14), mat, Vector3(side * 0.06, 0.04, 0))
			"armor", "robe":
				var t2: Node3D = D._attach(sk, D.TORSO, TAG + fam)
				_mi(t2, _box(0.27, 0.2, 0.22), mat, Vector3(0, 0.1, 0))                  # the chest, hips to shoulders
				if fam == "robe":
					_mi(t2, _tube(0.15, 0.22, 0.19, 12), mat, Vector3(0, -0.07, 0))     # and the skirt over the legs
			"vambraces":
				for side in [1.0, -1.0]:
					var arm: Node3D = D._attach(sk, D.ARM_L if side > 0 else D.ARM_R, TAG + "vam_%d" % int(side))
					_mi(arm, _box(0.11, 0.065, 0.065), mat, Vector3(side * 0.2, 0.0, 0))
			"gloves", "gauntlets":
				for side in [1.0, -1.0]:
					var hd: Node3D = D._attach(sk, D.ARM_L if side > 0 else D.ARM_R, TAG + fam + "_%d" % int(side))
					var big := 1.0 if fam == "gloves" else 1.12
					_mi(hd, _box(0.17 * big, 0.17 * big, 0.17 * big), mat, Vector3(side * 0.33, 0.0, 0))      # over the fist
					if fam == "gauntlets":
						_mi(hd, _box(0.08, 0.09, 0.09), mat, Vector3(side * 0.24, 0.0, 0))                      # and the cuff
			"underarmour":
				var tu: Node3D = D._attach(sk, D.TORSO, TAG + "under")
				_mi(tu, _box(0.25, 0.19, 0.2), mat, Vector3(0, 0.1, 0))
				for side in [1.0, -1.0]:
					var ua: Node3D = D._attach(sk, D.ARM_L if side > 0 else D.ARM_R, TAG + "under_arm_%d" % int(side))
					_mi(ua, _box(0.16, 0.055, 0.055), mat, Vector3(side * 0.09, 0.0, 0))
			"pants":
				var tp: Node3D = D._attach(sk, D.TORSO, TAG + "pants")
				_mi(tp, _box(0.2, 0.07, 0.19), mat, Vector3(0, 0.01, 0))
				for side in ["leg-left", "leg-right"]:
					var lp: Node3D = D._attach(sk, side, TAG + "pants" + side)
					_mi(lp, _box(0.145, 0.15, 0.15), mat, Vector3(0, -0.055, 0))
			"choker":
				var nk: Node3D = D._attach(sk, D.HEAD, TAG + "choker")
				_mi(nk, _tube(0.1, 0.1, 0.03, 14), material("jewel", col, "crafted"), Vector3(0, 0.0, 0))
			"necklace":
				var tn: Node3D = D._attach(sk, D.TORSO, TAG + "necklace")
				var jm := material("jewel", col, "crafted")
				_mi(tn, _box(0.17, 0.014, 0.03), jm, Vector3(0, 0.155, 0.1))
				_mi(tn, _ball(0.03), material("jade", D._c(p.get("gem_color", [0.9, 0.9, 0.9])), "crafted", D._c(p.get("gem_color", [0.9, 0.9, 0.9]))), Vector3(0, 0.125, 0.115))
			"bracelet":
				var sd := 1.0 if str(p.get("slot", "")).ends_with("_l") else -1.0
				var br: Node3D = D._attach(sk, D.ARM_L if sd > 0 else D.ARM_R, TAG + "bracelet_%d" % int(sd))
				_mi(br, _box(0.035, 0.1, 0.1), material("jewel", col, "crafted"), Vector3(sd * 0.27, 0.0, 0))
			"ring":
				var rs := str(p.get("slot", "ring_l1"))
				var rside := 1.0 if rs.contains("_l") else -1.0
				var rg: Node3D = D._attach(sk, D.ARM_L if rside > 0 else D.ARM_R, TAG + rs)
				_mi(rg, _ball(0.022), material("jewel", col, "crafted"), Vector3(rside * 0.37, 0.045, 0.035 * (float(rs.right(1)) - 2.5)))
			"greaves", "boots":
				for side in ["leg-left", "leg-right"]:
					var lg: Node3D = D._attach(sk, side, TAG + fam + side)
					if fam == "greaves":
						_mi(lg, _box(0.16, 0.1, 0.17), mat, Vector3(0, -0.07, 0))
					else:
						_mi(lg, _box(0.17, 0.06, 0.2), mat, Vector3(0, -0.15, 0.03))
