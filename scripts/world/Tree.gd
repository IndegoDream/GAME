extends RefCounted
## Tree: a realistic tree, built in code (round 47 -- Robert, 2026-10-04:
## "more visually realistic worlds and characters"). Poly Haven's scanned
## trees are hundreds of megabytes each; these are built the way game trees
## are: a bark-textured trunk and branches (Poly Haven bark, CC0) and a crown
## of photo-scanned leaf cards (cut from Poly Haven's leaf atlases --
## assets/foliage/) that sway in the wind and glow when the light is behind
## them (assets/shaders/foliage.gdshader).
##   broadleaf  a trunk that forks into a rounded crown of leaf clusters
##   conifer    a tall straight trunk with tiers of drooping fir branches
## The season shows: Harvest turns the leaves, Frost strips the broadleaf
## trees and frosts the firs. Built at the Kenney tree's own size and footing
## (Art.make), so nothing in a level moves. Same seed, same tree.

const LEAF := "res://assets/foliage/broadleaf_card.png"
const FIR := "res://assets/foliage/fir_card.png"
const SHADER := "res://assets/shaders/foliage.gdshader"

static var _tex := {}
static var _mats := {}
static var _cards := {}


static func available() -> bool:
	return _texture(LEAF) != null and _texture(FIR) != null and ResourceLoader.exists(SHADER)


static func _texture(p: String) -> Texture2D:
	if _tex.has(p):
		return _tex[p]
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	if t == null and FileAccess.file_exists(p):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_tex[p] = t
	return t


static func season_tint(conifer: bool, season: String) -> Color:
	match season:
		"fall":
			return Color(0.95, 1.0, 0.85) if conifer else Color(1.45, 0.78, 0.32)
		"dark":
			return Color(1.15, 1.2, 1.3) if conifer else Color(0.85, 0.7, 0.5)
	return Color(1, 1, 1)


static func ensure_globals() -> void:
	## the foliage shader reads where you are (so leaves between you and the
	## camera can thin out) -- a global it has to find when it compiles
	## camera can thin out). It's declared in project.godot [shader_globals]
	## (adding one at run time is editor-only); nothing to do here.
	pass


static func _leaf_mat(conifer: bool, season: String, far: bool = false) -> Material:
	var key := "%s|%s|%s" % [conifer, season, far]
	if _mats.has(key):
		return _mats[key]
	ensure_globals()
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("albedo_tex", _texture(FIR if conifer else LEAF))
	m.set_shader_parameter("tint", season_tint(conifer, season))
	m.set_shader_parameter("sway", 0.05 if conifer else 0.09)
	m.set_shader_parameter("alpha_cut", 0.45)
	m.set_shader_parameter("translucency", 0.25 if conifer else 0.4)
	m.set_shader_parameter("see_through", 0.0 if far else 2.6)
	if far:
		m.set_shader_parameter("sway", 0.03)
	_mats[key] = m
	return m


static func _bark(conifer: bool) -> Material:
	var key := "bark|%s" % conifer
	if not _mats.has(key):
		var spec := ["pine_bark", [0.75, 0.68, 0.6], 0.8] if conifer else ["bark_brown_02", [0.8, 0.74, 0.66], 0.9]
		_mats[key] = preload("res://scripts/world/Look.gd").surface(spec)
	return _mats[key]


static func _card(conifer: bool) -> QuadMesh:
	## a card whose left edge (UV.x = 0) is where it meets its branch
	var k := "card|%s" % conifer
	if not _cards.has(k):
		var q := QuadMesh.new()
		q.size = Vector2(2.0, 1.0) if conifer else Vector2(1.0, 1.0)
		q.center_offset = Vector3(1.0, 0, 0) if conifer else Vector3.ZERO
		_cards[k] = q
	return _cards[k]


static func make(conifer: bool, height: float, seed_v: int, season: String = "") -> Node3D:
	## a tree `height` tall, standing at the origin
	var root := Node3D.new()
	root.name = "Tree"
	root.set_meta("realistic_tree", true)
	var cards := []           # [Transform3D, Color]
	var limbs := []           # [from, dir, length, r0, r1]
	grow(conifer, height, seed_v, season, cards, limbs)
	for lb in limbs:
		_limb(root, lb[0], lb[1], lb[2], lb[3], lb[4], _bark(conifer))
	root.add_child(leaves(cards, conifer, season, false))
	return root


static func leaves(cards: Array, conifer: bool, season: String, far: bool) -> MultiMeshInstance3D:
	## all the cards: one MultiMesh, one draw
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _card(conifer)
	mm.instance_count = cards.size()
	for i in cards.size():
		mm.set_instance_transform(i, cards[i][0])
		mm.set_instance_color(i, cards[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Leaves"
	mmi.multimesh = mm
	mmi.material_override = _leaf_mat(conifer, season, far)
	return mmi


static func grow(conifer: bool, height: float, seed_v: int, season: String, cards: Array, limbs: Array, at: Vector3 = Vector3.ZERO, sparse: float = 1.0) -> void:
	## the tree's shape as data: leaf cards [Transform3D, Color] and limbs
	## [from, dir, length, r0, r1], standing at `at` (round 48: a whole forest
	## on the horizon is many of these in one draw)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var h := maxf(height, 1.0)
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
	var trunk_h := h * (0.95 if conifer else 0.55)
	var trunk_r := h * (0.035 if conifer else 0.05)
	limbs.append([at, Vector3.UP + lean, trunk_h, trunk_r, trunk_r * 0.35 if conifer else trunk_r * 0.6])
	var top := (Vector3.UP + lean).normalized() * trunk_h
	if conifer:
		# tiers of drooping branches, wide at the bottom, narrow at the top
		var tiers := int(clampf(h * 1.6, 6, 14))
		var start := h * 0.22
		for i in tiers:
			var f := float(i) / float(tiers - 1)
			var y := lerpf(start, h * 0.97, f)
			var reach := lerpf(h * 0.3, h * 0.05, f) * rng.randf_range(0.85, 1.1)
			var n := int(lerpf(8, 4, f))
			var off := rng.randf() * TAU
			for j in n:
				if sparse < 1.0 and rng.randf() > sparse:
					continue
				var a := off + TAU * j / n + rng.randf_range(-0.2, 0.2)
				var droop := lerpf(0.35, 0.15, f) + rng.randf_range(-0.08, 0.08)
				var b := Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, -droop)
				var roll := Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
				var pos := Vector3(0, y, 0) + lean * y
				var s := reach / 2.0
				cards.append([Transform3D((b * roll).scaled(Vector3(s, s * 0.9, s)), at + pos), _vary(rng, 0.12)])
				if f < 0.7 and rng.randf() < 0.5 * sparse:
					# a second, flatter layer: needles seen from above, not just edge-on
					var b2 := Basis(Vector3.UP, a + 0.3) * Basis(Vector3.FORWARD, -droop * 0.7) * Basis(Vector3.RIGHT, PI / 2)
					cards.append([Transform3D(b2.scaled(Vector3(s * 0.8, s * 0.8, s * 0.8)), at + pos + Vector3(0, 0.05, 0)), _vary(rng, 0.12)])
	else:
		# a few limbs up from the fork, and a round crown of leaf clusters around their ends
		var ends := [top]
		var nl := rng.randi_range(3, 5)
		for i in nl:
			var a := TAU * i / nl + rng.randf_range(-0.3, 0.3)
			var d := (Vector3(cos(a), rng.randf_range(0.9, 1.4), sin(a))).normalized()
			var ln := h * rng.randf_range(0.25, 0.35)
			limbs.append([at + top - Vector3(0, h * 0.05, 0), d, ln, trunk_r * 0.5, trunk_r * 0.2])
			ends.append(top - Vector3(0, h * 0.05, 0) + d * ln)
		var crown := top + Vector3(0, h * 0.18, 0)
		var rad := Vector3(h * 0.34, h * 0.26, h * 0.34)
		var count := int(clampf(h * 9.0, 30, 90) * sparse)
		if season == "dark":
			count = int(count * 0.25)           # winter: a few dry leaves hang on
		for i in count:
			var c: Vector3 = ends[rng.randi() % ends.size()].lerp(crown, rng.randf_range(0.2, 0.7))
			var p := c + Vector3(rng.randf_range(-1, 1) * rad.x, rng.randf_range(-0.7, 1) * rad.y, rng.randf_range(-1, 1) * rad.z) * 0.75
			var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var b := Basis(axis, rng.randf() * TAU)
			var s := h * rng.randf_range(0.17, 0.26)
			cards.append([Transform3D(b.scaled(Vector3(s, s, s)), at + p), _vary(rng, 0.18)])


static func _vary(rng: RandomNumberGenerator, amt: float) -> Color:
	## leaves aren't all one green
	var v := rng.randf_range(1.0 - amt, 1.0 + amt * 0.5)
	return Color(v * rng.randf_range(0.95, 1.05), v, v * rng.randf_range(0.9, 1.0))


static func _limb(parent: Node3D, from: Vector3, dir: Vector3, length: float, r0: float, r1: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = length
	cm.radial_segments = 10
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = mat
	var d := dir.normalized()
	var b := Basis(Quaternion(Vector3.UP, d)) if d.cross(Vector3.UP).length() > 0.001 else Basis()
	mi.transform = Transform3D(b, from + d * length * 0.5)
	parent.add_child(mi)


static func bark(conifer: bool) -> Material:
	return _bark(conifer)
