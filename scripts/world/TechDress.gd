extends RefCounted
## What the frontier's big things look like (round 123) -- all drawn in code, no model files: hull plates, pylons,
## tanks, gantries, consoles, furnaces, moon boulders, glass spires; and the lamps that replace the village lantern.
## Level.gd calls giant() for the 'x' and 'c' cells and lamp() for 'L' when the level's def says which kind
## (def.giants {"x": kind, "c": kind}, def.lamp). Blockers and counts always happen (the engine check needs them);
## meshes and lights are skipped on the headless renderer.

const Look := preload("res://scripts/world/Look.gd")


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _mat(c: Color, metal: float = 0.7, rough: float = 0.45, emit: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if alpha < 1.0 else BaseMaterial3D.CULL_BACK
	return m


static func _mi(L, mesh: Mesh, mat: Material, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	L.add_child(mi)
	return mi


static func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func _cyl(r_top: float, r_bot: float, h: float, segs: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _surf(L, key: String) -> Material:
	## the level's own wall surface, so a plate or a tank shares its region's metal
	var spec: Array = L.look.get(key, ["rock_face", [0.6, 0.6, 0.62], 3.0])
	return Look.surface(spec)


static func giant(L, cell: Vector2i, kind: String) -> void:
	var at: Vector3 = L.cell_to_world(cell)
	var rng: RandomNumberGenerator = L._rng
	L._blocker(cell, 1.0)
	L._count("tech_giants")
	if _headless():
		return
	var glow := Look.color3(L.look.get("glow", []), Color(0.4, 0.8, 1.0))
	var metal := _surf(L, "wall")
	match kind:
		"plate":            # torn hull plating standing on edge, a few of them leaning together
			for i in rng.randi_range(2, 4):
				var hh := rng.randf_range(1.6, 3.4)
				_mi(L, _box(rng.randf_range(1.0, 1.8), hh, 0.12), metal, at + Vector3(rng.randf_range(-0.6, 0.6), hh / 2.0 - 0.1, rng.randf_range(-0.6, 0.6)),
					Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
		"pylon":            # a tall mast with a lit head
			var hh2 := rng.randf_range(4.0, 6.0)
			_mi(L, _cyl(0.1, 0.28, hh2, 8), metal, at + Vector3(0, hh2 / 2.0, 0))
			_mi(L, _box(1.0, 0.08, 0.08), metal, at + Vector3(0, hh2 * 0.78, 0), Vector3(0, rng.randf() * PI, 0))
			var head := SphereMesh.new()
			head.radius = 0.14
			head.height = 0.28
			var hm := _mat(glow, 0.0, 0.2, 3.0)
			_mi(L, head, hm, at + Vector3(0, hh2 + 0.1, 0)).set_meta("flicker", rng.randf() < 0.4)
			if rng.randf() < 0.4:
				L._feature_light(at + Vector3(0, hh2, 0), glow, 0.9, 7.0)
		"tank":             # a squat storage tank with bands
			var tr := rng.randf_range(0.8, 1.1)
			var th := rng.randf_range(1.8, 2.8)
			_mi(L, _cyl(tr, tr, th, 14), metal, at + Vector3(0, th / 2.0, 0))
			for b in 2:
				_mi(L, _cyl(tr * 1.04, tr * 1.04, 0.1, 14), _mat(Color(0.9, 0.7, 0.2), 0.3, 0.6), at + Vector3(0, th * (0.3 + 0.4 * b), 0))
			_mi(L, _cyl(tr * 0.3, tr * 0.3, 0.3, 8), metal, at + Vector3(0, th + 0.15, 0))
		"gantry":           # an open frame of girders
			var gh := rng.randf_range(4.0, 5.5)
			for dx in [-0.8, 0.8]:
				for dz in [-0.8, 0.8]:
					_mi(L, _box(0.16, gh, 0.16), metal, at + Vector3(dx, gh / 2.0, dz))
			for k in 3:
				var y := gh * (0.25 + 0.35 * k)
				_mi(L, _box(1.8, 0.1, 0.1), metal, at + Vector3(0, y, 0.8))
				_mi(L, _box(0.1, 0.1, 1.8), metal, at + Vector3(0.8, y, 0))
			if rng.randf() < 0.3:
				L._feature_light(at + Vector3(0, gh * 0.9, 0), Color(1.0, 0.92, 0.8), 1.0, 8.0)
		"console":          # a bank of screens
			_mi(L, _box(1.4, 0.9, 0.6), metal, at + Vector3(0, 0.45, 0), Vector3(0, (rng.randi() % 4) * PI / 2.0, 0))
			var scr := _mi(L, _box(1.1, 0.5, 0.05), _mat(glow, 0.0, 0.3, 2.2), at + Vector3(0, 1.0, 0.16), Vector3(-0.3, 0, 0))
			scr.set_meta("flicker", true)
		"pillar":           # a load-bearing column with a light strip
			var ph := 3.4
			_mi(L, _cyl(0.38, 0.45, ph, 10), metal, at + Vector3(0, ph / 2.0, 0))
			_mi(L, _box(0.08, ph * 0.7, 0.08), _mat(glow, 0.0, 0.3, 2.0), at + Vector3(0.4, ph * 0.45, 0))
		"boulder":          # moon rock: dark, angular, half-buried
			var rockm := _mat(Color(0.32, 0.33, 0.38), 0.0, 0.95)
			for i in rng.randi_range(2, 4):
				var s := rng.randf_range(0.5, 1.1)
				_mi(L, _box(s * 1.3, s * 0.9, s), rockm, at + Vector3(rng.randf_range(-0.5, 0.5), s * 0.35, rng.randf_range(-0.5, 0.5)),
					Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		"rimstone":         # a standing spire of crater rim
			var rh := rng.randf_range(2.4, 4.4)
			_mi(L, _cyl(0.0, rng.randf_range(0.7, 1.1), rh, 6), _mat(Color(0.4, 0.4, 0.46), 0.0, 0.9), at + Vector3(0, rh / 2.0, 0))
		"glassspire":       # clear gold crystals grown out of the sand
			var gm := _mat(Color(1.0, 0.82, 0.45), 0.0, 0.05, 0.6, 0.78)
			for i in rng.randi_range(3, 5):
				var gh2 := rng.randf_range(1.2, 3.2)
				_mi(L, _cyl(0.02, rng.randf_range(0.16, 0.3), gh2, 6), gm, at + Vector3(rng.randf_range(-0.5, 0.5), gh2 * 0.45, rng.randf_range(-0.5, 0.5)),
					Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
			if rng.randf() < 0.3:
				L._feature_light(at + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.45), 0.8, 5.0)
		"obelisk":          # a dark old stone with a glowing band
			var oh := rng.randf_range(2.6, 4.0)
			_mi(L, _cyl(0.2, 0.42, oh, 4), _mat(Color(0.22, 0.2, 0.26), 0.2, 0.5), at + Vector3(0, oh / 2.0, 0), Vector3(0, PI / 4.0, 0))
			_mi(L, _cyl(0.23, 0.23, 0.08, 4), _mat(Color(0.9, 0.55, 0.95), 0.0, 0.3, 2.4), at + Vector3(0, oh * 0.62, 0), Vector3(0, PI / 4.0, 0))
		"furnace":          # a squat furnace with a glowing mouth
			_mi(L, _box(1.6, 1.5, 1.2), metal, at + Vector3(0, 0.75, 0), Vector3(0, (rng.randi() % 4) * PI / 2.0, 0))
			_mi(L, _box(0.7, 0.5, 0.05), _mat(Color(1.0, 0.5, 0.15), 0.0, 0.5, 3.0), at + Vector3(0, 0.7, 0.62))
			_mi(L, _cyl(0.2, 0.28, 1.8, 8), metal, at + Vector3(0.4, 2.2, -0.3))
			if rng.randf() < 0.5:
				L._feature_light(at + Vector3(0, 1.0, 0.8), Color(1.0, 0.5, 0.2), 1.1, 6.0)
		_:
			_mi(L, _box(1.2, 1.2, 1.2), metal, at + Vector3(0, 0.6, 0))


static func lamp(L, cell: Vector2i, kind: String) -> void:
	var at: Vector3 = L.cell_to_world(cell)
	L._count("lights")
	var col := Color(0.7, 0.85, 1.0)
	var energy := 1.2
	var rng_ := 9.0
	var hgt := 2.6
	match kind:
		"arc":     col = Color(0.55, 0.8, 1.0)
		"flood":   col = Color(1.0, 0.97, 0.9); energy = 1.5; rng_ = 13.0; hgt = 3.6
		"panel":   col = Color(0.8, 0.95, 1.0); energy = 1.1; rng_ = 10.0; hgt = 3.0
		"beacon":  col = Color(1.0, 0.35, 0.3); energy = 1.0; rng_ = 8.0
		"mirror":  col = Color(1.0, 0.85, 0.55); energy = 1.3; rng_ = 11.0
		"furnace": col = Color(1.0, 0.5, 0.2); energy = 1.5; rng_ = 9.0; hgt = 1.4
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_
	l.position = at + Vector3(0, hgt, 0)
	L.add_child(l)
	if _headless():
		return
	var metal := _mat(Color(0.35, 0.37, 0.4), 0.8, 0.5)
	if kind == "furnace":
		_mi(L, _cyl(0.3, 0.38, 0.5, 8), metal, at + Vector3(0, 0.25, 0))
		_mi(L, _cyl(0.24, 0.24, 0.06, 8), _mat(col, 0.0, 0.4, 3.0), at + Vector3(0, 0.52, 0))
		return
	_mi(L, _cyl(0.05, 0.08, hgt, 6), metal, at + Vector3(0, hgt / 2.0, 0))
	var head := SphereMesh.new()
	head.radius = 0.16 if kind != "flood" else 0.28
	head.height = head.radius * 2.0
	_mi(L, head, _mat(col, 0.0, 0.3, 3.0), at + Vector3(0, hgt + 0.1, 0))


static func rim(L, cell: Vector2i, at: Vector3, style: String, r: RandomNumberGenerator) -> void:
	## the edge of a tech region's map: boulders and plate stacks instead of hedges and fences
	if _headless():
		return
	var j := Vector3(r.randf_range(-0.4, 0.4), 0.0, r.randf_range(-0.4, 0.4))
	if style == "plates":
		var metal := _surf(L, "wall")
		for i in r.randi_range(1, 3):
			var hh := r.randf_range(1.2, 3.0)
			_mi(L, _box(r.randf_range(1.0, 1.8), hh, 0.14), metal, at + j + Vector3(r.randf_range(-0.7, 0.7), hh / 2.0, r.randf_range(-0.7, 0.7)),
				Vector3(r.randf_range(-0.3, 0.3), r.randf() * TAU, r.randf_range(-0.4, 0.4)))
	else:
		var rockm := _mat(Color(0.34, 0.34, 0.4), 0.0, 0.95)
		var s := r.randf_range(0.8, 1.6)
		_mi(L, _box(s * 1.4, s, s * 1.1), rockm, at + j + Vector3(0, s * 0.4, 0), Vector3(r.randf_range(-0.2, 0.2), r.randf() * TAU, r.randf_range(-0.2, 0.2)))
