extends Node3D
## The small things on a dungeon floor (round 52). Robert, 2026-10-04: "bring
## in more depth to the world, more detail, more contrast."
##
## Puddles that catch the torchlight (glossy, dark), patches of moss and of
## loose dirt that break up the stone, pebbles and grit drifted against the
## walls, cobwebs strung across the corners. How much of each depends on the
## region (data/feel.json "detail": a drowned seam is wet, a crypt is webbed,
## a forge is dry and gritty). All of it is a handful of draws (MultiMesh),
## looks only, never in the way, and placed the same way every visit.

var level
var state := {}             # how many of each (for tests)
var _rng := RandomNumberGenerator.new()

static var _tex := {}


func setup(lvl) -> void:
	level = lvl


func _ready() -> void:
	name = "GroundDetail"
	add_to_group("fog_exempt")
	_rng.seed = hash(str(level.level_id) + "detail")
	var all: Dictionary = preload("res://scripts/fx/FX.gd").feel("detail")
	var D: Dictionary = all.get(str(level.look_key), all.get("default", {}))
	var floor_cells := []
	var wall_side := []
	for c in level._floor_cells:
		var cell: Vector2i = c
		if level.char_at(cell) != ".":
			continue
		floor_cells.append(cell)
		if level._wall_neighbor(cell) != Vector2i.ZERO:
			wall_side.append(cell)
	floor_cells.sort()
	wall_side.sort()
	_puddles(floor_cells, float(D.get("puddles", 0.0)))
	_patches(wall_side, floor_cells, "moss", float(D.get("moss", 0.0)))
	_patches(floor_cells, floor_cells, "dirt", float(D.get("dirt", 0.0)))
	_pebbles(wall_side, float(D.get("pebbles", 0.0)))
	_webs(float(D.get("webs", 0.0)))


func _pick(cells: Array, chance: float, cap: int) -> Array:
	var out := []
	if chance <= 0.0:
		return out
	for c in cells:
		if _rng.randf() < chance:
			out.append(c)
			if out.size() >= cap:
				break
	return out


func _mm(mesh: Mesh, xforms: Array, mat: Material, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _jitter(cell: Vector2i, spread: float) -> Vector3:
	return level.cell_to_world(cell) + Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))


func _flat(at: Vector3, size: float, y: float) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(size * _rng.randf_range(0.8, 1.25), 1.0, size * _rng.randf_range(0.7, 1.1)))
	return Transform3D(b, Vector3(at.x, y, at.z))


# ---- puddles -----------------------------------------------------------------------------------

func _puddles(cells: Array, chance: float) -> void:
	var xs := []
	for c in _pick(cells, chance, 60):
		xs.append(_flat(_jitter(c, 0.5), _rng.randf_range(0.9, 2.2), 0.046))      # (the floor is drawn at 0.02, roads at 0.035)
	state["puddles"] = xs.size()
	if xs.is_empty():
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = _shader("puddle", """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D mask : hint_default_white, filter_linear;
uniform vec4 tint : source_color = vec4(0.05, 0.06, 0.07, 0.85);
void fragment() {
	float a = texture(mask, UV).r;
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.03;
	METALLIC = 0.35;
	SPECULAR = 0.9;
	ALPHA = a * tint.a;
}
""")
	if DisplayServer.get_name() != "headless":
		m.set_shader_parameter("mask", blob(11))
	m.render_priority = 2
	_mm(pm, xs, m, "Puddles")


# ---- moss and dirt -------------------------------------------------------------------------------

func _patches(cells: Array, _all: Array, kind: String, chance: float) -> void:
	var xs := []
	for c in _pick(cells, chance, 90):
		xs.append(_flat(_jitter(c, 0.6), _rng.randf_range(1.0, 2.4), 0.04 if kind == "dirt" else 0.043))
	state[kind] = xs.size()
	if xs.is_empty():
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = _shader("patch", """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask : hint_default_white, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform float scale = 0.35;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = texture(albedo_tex, wpos.xz * scale).rgb * tint.rgb;
	ROUGHNESS = 0.95;
	ALPHA = texture(mask, UV).r * tint.a;
}
""")
	var L := preload("res://scripts/world/Look.gd")
	if DisplayServer.get_name() != "headless":
		m.set_shader_parameter("albedo_tex", L.texture("forest_floor" if kind == "moss" else "stony_dirt_path", "albedo"))
		m.set_shader_parameter("mask", blob(23 if kind == "moss" else 37))
	m.set_shader_parameter("tint", Color(0.55, 0.75, 0.4, 0.9) if kind == "moss" else Color(0.75, 0.68, 0.58, 0.8))
	m.render_priority = 1 if kind == "moss" else 0
	_mm(pm, xs, m, "Moss" if kind == "moss" else "Dirt")


# ---- pebbles --------------------------------------------------------------------------------------

func _pebbles(cells: Array, chance: float) -> void:
	var xs := []
	for c in _pick(cells, chance, 160):
		var wd: Vector2i = level._wall_neighbor(c)
		var base: Vector3 = level.cell_to_world(c) + Vector3(wd.x, 0, wd.y) * 0.65
		for i in _rng.randi_range(3, 7):
			var at := base + Vector3(_rng.randf_range(-0.55, 0.55), 0.0, _rng.randf_range(-0.55, 0.55))
			var s := _rng.randf_range(0.05, 0.16)
			var b := Basis(Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(), _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.45, 0.75), s * _rng.randf_range(0.8, 1.2)))
			xs.append(Transform3D(b, Vector3(at.x, 0.02 + s * 0.18, at.z)))
	state["pebbles"] = xs.size()
	if xs.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 7
	sm.rings = 4
	var wspec: Array = level.look.get("wall", ["rock_face", [0.6, 0.58, 0.56], 3.0])
	var mat := preload("res://scripts/world/Look.gd").surface(["rock_face", wspec[1], 0.6], 0.75)
	_mm(sm, xs, mat, "Pebbles")


# ---- cobwebs ----------------------------------------------------------------------------------------

func _webs(chance: float) -> void:
	## strung across an inside corner, up under the top of the walls
	var xs := []
	if chance > 0.0:
		var C: float = level.CELL
		for c in level._floor_cells:
			var cell: Vector2i = c
			if level.char_at(cell) != "." or _rng.randf() >= chance * 0.25:
				continue
			for pair in [[Vector2i(1, 0), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(0, 1)], [Vector2i(1, 0), Vector2i(0, -1)], [Vector2i(-1, 0), Vector2i(0, -1)]]:
				var a: Vector2i = pair[0]
				var b: Vector2i = pair[1]
				if _solid(cell + a) and _solid(cell + b):
					var corner: Vector3 = level.cell_to_world(cell) + Vector3(a.x + b.x, 0, a.y + b.y) * (C * 0.5)
					var inward := -Vector3(a.x + b.x, 0, a.y + b.y).normalized()
					var size := _rng.randf_range(0.9, 1.6)
					var pos := corner + inward * size * 0.36
					pos.y = level.WALL_H - size * 0.45 - _rng.randf_range(0.0, 0.3)
					var bz := Basis.looking_at(inward, Vector3.UP).scaled(Vector3(size, size, 1.0))
					xs.append(Transform3D(bz, pos))
					break
			if xs.size() >= 40:
				break
	state["webs"] = xs.size()
	if xs.is_empty():
		return
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.9, 0.9, 0.88, 0.55)
	m.roughness = 0.6
	if DisplayServer.get_name() != "headless":
		m.albedo_texture = web()
	_mm(q, xs, m, "Webs")


func _solid(cell: Vector2i) -> bool:
	var ch: String = level.char_at(cell)
	return ch == "#" or ch == " "


# ---- textures, made once -------------------------------------------------------------------------

static func blob(seed_v: int) -> Texture2D:
	## a soft, ragged-edged splotch (white where it is)
	var key := "blob%d" % seed_v
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.045
	n.fractal_octaves = 4
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S * 0.5 + 0.5, y - S * 0.5 + 0.5).length() / (S * 0.5)
			var v := (1.0 - d) * 1.6 + n.get_noise_2d(x, y) * 0.9 - 0.25
			var a := clampf(v * 2.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(a, a, a, 1.0))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func web() -> Texture2D:
	## threads: spokes from the middle and a spiral round them
	if _tex.has("web"):
		return _tex["web"]
	var S := 128
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := Vector2(S * 0.5, S * 0.5)
	var spokes := 9
	for i in spokes:
		var ang := TAU * i / spokes + 0.2 * sin(i * 1.7)
		for r in range(0, S / 2):
			var p := c + Vector2(cos(ang), sin(ang)) * r
			_dot(img, p, 0.75 * (1.0 - float(r) / (S * 0.5)) + 0.2)
	var t := 0.0
	while t < 26.0:
		var r2 := 4.0 + t * 2.3
		var p2 := c + Vector2(cos(t * 1.0), sin(t * 1.0)) * r2
		_dot(img, p2, 0.55)
		t += 0.02
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	_tex["web"] = tx
	return tx


static func _dot(img: Image, p: Vector2, a: float) -> void:
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(1, 1, 1, maxf(o.a, a)))


static func _shader(key: String, code: String) -> Shader:
	if _tex.has("sh_" + key):
		return _tex["sh_" + key]
	var s := Shader.new()
	s.code = code
	_tex["sh_" + key] = s
	return s
