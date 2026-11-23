extends RefCounted
## What a reach looks like (round 56) -- the big growths, its lamps, its
## pools of water or fire, and the glow that runs through it. Called by
## Level.gd for the cells inside a reach (Reach.gd grows the shape). Every
## piece is looks only except where a cell was already solid (a growth or a
## pool stands on a cell the map marks as blocked). Off on the headless
## engine check except what play needs (blockers, counts).

const Look := preload("res://scripts/world/Look.gd")


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func tint(B: Dictionary) -> Color:
	return Look.color3(B.get("tint", []), Color(1, 0.9, 0.7))


static func _mat_glow(c: Color, e: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.25
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _mesh(L, mesh: Mesh, mat: Material, at: Vector3, rot: Vector3 = Vector3.ZERO, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.scale = sc
	L.add_child(mi)
	return mi


static func _cone(r: float, h: float, segs: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 3
	return c


static func _prism(r: float, h: float, top: float = 0.6, segs: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r * top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func giant(L, cell: Vector2i, B: Dictionary, column: bool) -> void:
	## the land's big growth on a blocked cell ('x'), or its column ('c')
	var at: Vector3 = L.cell_to_world(cell)
	var kind := str(B.get("column" if column else "giant", "stalagmite"))
	var rng: RandomNumberGenerator = L._rng
	L._blocker(cell, 1.0)
	L._count("reach_growths")
	if _headless():
		return
	var c := tint(B)
	var rock: Material = Look.surface(Look.LOOKS.get(str(B.get("look", "")), {}).get("wall", ["rock_face", [0.6, 0.6, 0.62], 3.0]))
	match kind:
		"mushroom":
			var m: Node3D = L._prop("nature-kit/mushroom_tanTall.glb" if rng.randf() < 0.6 else "nature-kit/mushroom_redTall.glb", at, rng.randf_range(5.5, 8.5), rng.randf() * TAU)
			L._glow_tint(m, c)
			if rng.randf() < 0.35:
				L._feature_light(at + Vector3(0, 2.6, 0), c, 0.9, 6.0)
		"stalagmite":
			var hh := rng.randf_range(2.2, 4.2)
			_mesh(L, _cone(rng.randf_range(0.7, 1.1), hh), rock, at + Vector3(rng.randf_range(-0.3, 0.3), hh / 2.0, rng.randf_range(-0.3, 0.3)))
			if rng.randf() < 0.5:
				var h2 := hh * 0.55
				_mesh(L, _cone(0.45, h2), rock, at + Vector3(0.6, h2 / 2.0, -0.4))
		"crystal":
			for i in rng.randi_range(3, 5):
				var hh := rng.randf_range(1.2, 3.4)
				var tilt := Vector3(rng.randf_range(-0.45, 0.45), rng.randf() * TAU, rng.randf_range(-0.45, 0.45))
				var off := Vector3(rng.randf_range(-0.5, 0.5), hh * 0.45, rng.randf_range(-0.5, 0.5))
				_mesh(L, _prism(rng.randf_range(0.18, 0.34), hh, 0.15), _mat_glow(c, rng.randf_range(1.2, 2.4), 0.88), at + off, tilt)
			if rng.randf() < 0.3:
				L._feature_light(at + Vector3(0, 1.4, 0), c, 0.8, 5.0)
		"root":
			# a root grown down out of the roof and into the floor
			var r: Node3D = L._prop("nature-kit/log_large.glb", at + Vector3(0, 1.4, 0), rng.randf_range(2.6, 3.6), rng.randf() * TAU)
			r.rotation = Vector3(deg_to_rad(rng.randf_range(55, 75)), rng.randf() * TAU, 0)
			L._prop("nature-kit/stump_oldTall.glb", at, rng.randf_range(2.4, 3.2), rng.randf() * TAU)
		"basalt":
			var dark: StandardMaterial3D = (rock as StandardMaterial3D).duplicate() if rock is StandardMaterial3D else StandardMaterial3D.new()
			dark.albedo_color = Color(0.22, 0.2, 0.2)
			for i in rng.randi_range(2, 4):
				var hh := rng.randf_range(1.0, 3.6)
				_mesh(L, _prism(rng.randf_range(0.35, 0.55), hh, 1.0), dark, at + Vector3(rng.randf_range(-0.55, 0.55), hh / 2.0, rng.randf_range(-0.55, 0.55)))
			_mesh(L, _prism(0.9, 0.04, 1.0, 8), _mat_glow(c, 2.5), at + Vector3(0, 0.05, 0))
		"bones":
			var bone := StandardMaterial3D.new()
			bone.albedo_color = Color(0.85, 0.82, 0.72)
			bone.roughness = 0.8
			for i in rng.randi_range(5, 9):
				var cap := CapsuleMesh.new()
				cap.radius = rng.randf_range(0.06, 0.1)
				cap.height = rng.randf_range(0.6, 1.2)
				_mesh(L, cap, bone, at + Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.1, 0.5), rng.randf_range(-0.7, 0.7)),
					Vector3(rng.randf_range(-1.4, 1.4), rng.randf() * TAU, rng.randf_range(-1.4, 1.4)))
			for i2 in rng.randi_range(1, 3):
				var skull := SphereMesh.new()
				skull.radius = 0.2
				skull.height = 0.34
				_mesh(L, skull, bone, at + Vector3(rng.randf_range(-0.5, 0.5), 0.6 + i2 * 0.18, rng.randf_range(-0.5, 0.5)))
			L._prop("mini-dungeon/stones.glb", at, 1.6, rng.randf() * TAU)
		"statue":
			L._prop("nature-kit/statue_head.glb" if rng.randf() < 0.4 else "nature-kit/statue_column.glb", at, rng.randf_range(1.4, 2.0), rng.randf() * TAU)
		"ice":
			var ice := _mat_glow(Color(0.75, 0.9, 1.0), 0.35, 0.82)
			ice.roughness = 0.05
			var hh := rng.randf_range(2.0, 3.8)
			_mesh(L, _prism(rng.randf_range(0.45, 0.7), hh, 0.75, 7), ice, at + Vector3(0, hh / 2.0, 0), Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1)))
			if rng.randf() < 0.6:
				_mesh(L, _cone(0.35, 1.2, 6), ice, at + Vector3(0.5, 0.6, 0.3))
		"ruin":
			L._prop("nature-kit/statue_columnDamaged.glb" if rng.randf() < 0.6 else "nature-kit/statue_block.glb", at, rng.randf_range(1.2, 1.6), rng.randf() * TAU)
			L._prop("nature-kit/stone_smallFlatA.glb", at + Vector3(0.6, 0, 0.4), 2.0, rng.randf() * TAU)
		"column":
			L._prop("nature-kit/statue_column.glb", at, rng.randf_range(1.3, 1.6), rng.randf() * TAU)
		"spire":
			var sp: Node3D = L._prop("nature-kit/rock_tall%s.glb" % ["A", "B", "C", "D", "E"][rng.randi() % 5], at, rng.randf_range(1.6, 2.4), rng.randf() * TAU)
			if rng.randf() < 0.45:
				var arc := _mesh(L, _prism(0.03, 1.8, 1.0, 4), _mat_glow(c, 4.0), at + Vector3(0, 1.6, 0), Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)))
				arc.set_meta("flicker", true)
				L._feature_light(at + Vector3(0, 2.2, 0), c, 1.1, 5.0)
		"mine":
			L._prop("fantasy-town-kit/cart.glb" if rng.randf() < 0.4 else "mini-dungeon/wood-structure.glb", at, rng.randf_range(1.0, 1.3), rng.randf() * TAU)
			L._prop("mini-dungeon/rocks.glb", at + Vector3(0.5, 0, -0.4), 1.2)
		"support":
			L._prop("mini-dungeon/wood-support.glb", at, 1.6, (rng.randi() % 4) * PI / 2)
		_:
			L._prop("mini-dungeon/rocks.glb", at, 2.0)


static func lava(L, cell: Vector2i, B: Dictionary) -> void:
	## the Ember Rift's fire: a cell of slow lava -- solid, glowing, lighting the rock
	L._solid(cell)
	var at: Vector3 = L.cell_to_world(cell)
	L._box_body(at + Vector3(0, 1.5, 0), Vector3(L.CELL, 3.0, L.CELL))
	L._count("lava")
	if _headless():
		return
	var c := tint(B)
	var pm := PlaneMesh.new()
	pm.size = Vector2(L.CELL, L.CELL)
	var m := _mat_glow(Color(1.0, 0.42, 0.08), 2.6)
	m.albedo_color = Color(0.5, 0.12, 0.02)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := _mesh(L, pm, m, at + Vector3(0, 0.03, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if L._rng.randf() < 0.18:
		L._feature_light(at + Vector3(0, 0.8, 0), c, 1.2, 4.5)


static func water(L, cell: Vector2i, B: Dictionary) -> Material:
	## the look of a reach's water: the Underlake black and glassy, the Frost
	## Gallery's frozen white
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if bool(B.get("water", {}).get("frozen", false)):
		m.albedo_color = Color(0.78, 0.88, 0.95, 0.95)
		m.roughness = 0.08
		m.metallic = 0.1
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.albedo_color = Color(0.03, 0.08, 0.13, 0.92)
		m.roughness = 0.03
		m.metallic = 0.4
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func lamp(L, cell: Vector2i, B: Dictionary) -> void:
	## a reach's light: its own kind of glow, not a torch
	var at: Vector3 = L.cell_to_world(cell)
	L._count("lights")
	var c := tint(B)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.35
	l.omni_range = 10.0
	l.position = at + Vector3(0, 2.0, 0)
	L.add_child(l)
	if _headless():
		return
	match str(B.get("giant", "")):
		"mushroom":
			L._glow_mushroom(at)
			L._glow_mushroom(at + Vector3(0.6, 0, -0.5))
		"crystal", "ice":
			for i in 3:
				_mesh(L, _prism(0.14, L._rng.randf_range(0.6, 1.2), 0.1), _mat_glow(c, 2.2, 0.9), at + Vector3(L._rng.randf_range(-0.4, 0.4), 0.4, L._rng.randf_range(-0.4, 0.4)),
					Vector3(L._rng.randf_range(-0.4, 0.4), 0, L._rng.randf_range(-0.4, 0.4)))
		"basalt":
			_mesh(L, _prism(0.5, 0.05, 1.0, 8), _mat_glow(Color(1.0, 0.45, 0.1), 3.0), at + Vector3(0, 0.04, 0))
		"root":
			# light falling through where the roots broke in
			var shaft := _mesh(L, _prism(0.9, 4.0, 1.25, 10), _mat_glow(c, 0.7, 0.12), at + Vector3(0, 2.0, 0))
			shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(shaft.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(shaft.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		"mine":
			L._prop("fantasy-town-kit/lantern.glb", at, 1.4)
		"spire":
			_mesh(L, SphereMesh.new(), _mat_glow(c, 3.0), at + Vector3(0, 1.6, 0), Vector3.ZERO, Vector3.ONE * 0.25)
		_:
			L._spawn_script("res://scripts/objects/Torch.gd", at, {"color": [c.r, c.g, c.b]})


static func glows(L, cells: Array, B: Dictionary) -> void:
	## light running through the land itself, scattered over open ground
	if _headless() or cells.is_empty():
		return
	var c := tint(B)
	var rng: RandomNumberGenerator = L._rng
	var n := mini(cells.size() / 45 + 2, 18)
	for i in n:
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		var at: Vector3 = L.cell_to_world(cell) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		match str(B.get("giant", "")):
			"mushroom":
				L._glow_mushroom(at)
			"crystal", "ice":
				_mesh(L, _prism(0.1, rng.randf_range(0.3, 0.7), 0.1), _mat_glow(c, 2.0, 0.9), at + Vector3(0, 0.2, 0), Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
			"basalt", "spire":
				var crack := BoxMesh.new()
				crack.size = Vector3(rng.randf_range(0.6, 1.8), 0.02, rng.randf_range(0.05, 0.12))
				_mesh(L, crack, _mat_glow(c, 3.0), at + Vector3(0, 0.045, 0), Vector3(0, rng.randf() * TAU, 0))
			"root":
				L._prop("nature-kit/grass_large.glb", at, 2.2, rng.randf() * TAU)
			"bones", "statue":
				var cap := CapsuleMesh.new()
				cap.radius = 0.05
				cap.height = 0.7
				var bone := StandardMaterial3D.new()
				bone.albedo_color = Color(0.82, 0.8, 0.7)
				_mesh(L, cap, bone, at + Vector3(0, 0.06, 0), Vector3(PI / 2, rng.randf() * TAU, 0))
			"stalagmite":
				var lily := CylinderMesh.new()
				lily.top_radius = 0.22
				lily.bottom_radius = 0.22
				lily.height = 0.01
				_mesh(L, lily, _mat_glow(c, 1.4), at + Vector3(0, 0.05, 0))
			_:
				L._prop("mini-dungeon/stones.glb", at, 1.2, rng.randf() * TAU)
