extends RefCounted
## FX: the little bursts that make a fight read (round 29 -- Robert: "we
## also want good effects"). Everything here is fire-and-forget: call it,
## it plays, it cleans itself up. Nothing in play depends on it -- under
## the headless engine check it does nothing at all -- and Low graphics
## gets a lighter version (fewer particles, no flash lights).
##
##   FX.hit(where, colour, big)      sparks where a blow lands, a flash
##   FX.slash(who, colour, reach)    a bright crescent where your blade swept
##   FX.puff(where, colour, size)    a death: smoke, and motes of qi rising
##   FX.sink(node, after)            a body settling into the ground, then gone
##   FX.dust(where, size)            boots on dirt: landing, a charge
##   FX.ring(where, colour, radius)  a shockwave on the ground (a stamp, a parry)
##   FX.aura(node, colour, height)   embers that keep rising around an elite
##   FX.trail(node, colour)          a glowing trail behind a bolt

static var _mats := {}
static var _meshes := {}


static func on() -> bool:
	return DisplayServer.get_name() != "headless"


static func _rich() -> bool:
	return str(preload("res://scripts/core/Gfx.gd").settings.get("preset", "high")) != "low"


static func _scene_root(n: Node) -> Node:
	var t := n.get_tree() if n != null and n.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if t == null:
		return null
	return t.current_scene if t.current_scene != null else t.root


static func _mat(kind: String) -> StandardMaterial3D:
	## shared: "add" glows (sparks, motes), "smoke" is soft and dark
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_dot()
	if kind == "add":
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[kind] = m
	return m


static func _soft_dot() -> Texture2D:
	## a round dot that fades to nothing at its edge
	if _meshes.has("dot"):
		return _meshes["dot"]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_meshes["dot"] = tex
	return tex


static func puff_texture() -> Texture2D:
	## round 37: a soft, ragged puff (noise inside a round falloff) for smoke
	## and mist -- no more square smoke from the chimneys
	if _meshes.has("puff"):
		return _meshes["puff"]
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.09
	n.fractal_octaves = 4
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var fall := clampf(1.0 - d, 0.0, 1.0)
			var v := 0.55 + 0.45 * n.get_noise_2d(x, y)
			var a := clampf(fall * fall * (0.6 + 0.8 * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_meshes["puff"] = tex
	return tex


static func soft_dot() -> Texture2D:
	return _soft_dot()


static func _quad(size: float) -> QuadMesh:
	var key := "q%.3f" % size
	if not _meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_meshes[key] = q
	return _meshes[key]


static func _ramp(c: Color, end_alpha := 0.0) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 1.0))
	g.set_color(1, Color(c.r, c.g, c.b, end_alpha))
	return g


static func _burst(parent: Node, at: Vector3, n: int, life: float, mesh_size: float, mat_kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(2, n if _rich() else n / 2)
	p.lifetime = life
	p.mesh = _quad(mesh_size)
	p.material_override = _solid_mat() if mat_kind == "solid" else _mat(mat_kind)
	p.local_coords = false
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	# gone once the last particle is
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)
	return p


static func _flash(parent: Node, at: Vector3, c: Color, energy: float, rng: float, secs: float) -> void:
	if not _rich():
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, secs)
	tw.tween_callback(l.queue_free)


# ---- the effects ------------------------------------------------------------

static func hit(where: Vector3, c: Color = Color(1.0, 0.8, 0.45), big: bool = false) -> void:
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var p := _burst(root, where, 22 if big else 12, 0.35, 0.07, "add")
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0 if big else 4.5
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.color_ramp = _ramp(Color(minf(c.r * 1.6, 1.0), minf(c.g * 1.6, 1.0), minf(c.b * 1.6, 1.0)))
	_flash(root, where, c, 2.2 if big else 1.2, 3.0, 0.14)


static func slash(who: Node3D, c: Color = Color(0.95, 0.95, 1.0), reach: float = 2.0, yaw: float = 0.0, height: float = 1.1) -> void:
	## a crescent of light swept in front of `who`, facing `yaw`
	if not on() or who == null or not who.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	who.add_child(mi)
	mi.position = Vector3(0, height, 0)
	mi.rotation = Vector3(0.0, yaw + 0.9, -0.25)
	mi.scale = Vector3.ONE * reach
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "rotation:y", yaw - 0.9, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.24).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)


static func _arc_mesh() -> ArrayMesh:
	## a flat crescent, brightest at its outer edge and its leading tip
	if _meshes.has("arc"):
		return _meshes["arc"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 18
	var a0 := -0.9
	var a1 := 0.9
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var ang0 := lerpf(a0, a1, t0)
		var ang1 := lerpf(a0, a1, t1)
		var w0 := sin(t0 * PI)          # thickest in the middle of the sweep
		var w1 := sin(t1 * PI)
		var o0 := Vector3(sin(ang0), 0, cos(ang0))
		var o1 := Vector3(sin(ang1), 0, cos(ang1))
		var i0 := o0 * (1.0 - 0.35 * w0)
		var i1 := o1 * (1.0 - 0.35 * w1)
		var ca := Color(1, 1, 1, 0.0)
		var cb0 := Color(1, 1, 1, 0.25 + 0.75 * t0)
		var cb1 := Color(1, 1, 1, 0.25 + 0.75 * t1)
		st.set_color(ca); st.add_vertex(i0)
		st.set_color(cb0); st.add_vertex(o0)
		st.set_color(cb1); st.add_vertex(o1)
		st.set_color(ca); st.add_vertex(i0)
		st.set_color(cb1); st.add_vertex(o1)
		st.set_color(ca); st.add_vertex(i1)
	var mesh := st.commit()
	_meshes["arc"] = mesh
	return mesh


static func puff(where: Vector3, c: Color = Color(0.55, 0.52, 0.5), size: float = 1.0) -> void:
	## a death: a soft cloud, and motes of qi drifting up out of it
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var s := _burst(root, where, 14, 1.1, 0.55 * size, "smoke")
	s.direction = Vector3.UP
	s.spread = 70.0
	s.initial_velocity_min = 0.4
	s.initial_velocity_max = 1.4
	s.gravity = Vector3(0, 0.6, 0)
	s.damping_min = 1.0
	s.damping_max = 2.0
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.35 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.6))
	s.scale_amount_curve = sc
	s.color_ramp = _ramp(Color(c.r * 0.6, c.g * 0.6, c.b * 0.6))
	s.color_ramp.set_color(0, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.55))
	var q := _burst(root, where + Vector3(0, 0.3, 0), 16, 1.6, 0.06, "add")
	q.direction = Vector3.UP
	q.spread = 35.0
	q.initial_velocity_min = 0.8
	q.initial_velocity_max = 2.2
	q.gravity = Vector3(0, 0.8, 0)
	q.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	q.emission_sphere_radius = 0.4 * size
	q.color_ramp = _ramp(Color(0.6, 0.95, 1.0))


static func sink(n: Node3D, after: float = 1.2, depth: float = 1.2, secs: float = 0.9) -> void:
	## a body settles into the ground, then is gone (it frees the node)
	if n == null or not n.is_inside_tree():
		return
	var tw := n.create_tween()
	tw.tween_interval(after)
	if on():
		tw.tween_callback(func(): dust(n.global_position, 1.2))
		tw.tween_property(n, "position:y", n.position.y - depth, secs).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)


static func dust(where: Vector3, size: float = 1.0) -> void:
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var d := _burst(root, where + Vector3(0, 0.05, 0), 10, 0.7, 0.3 * size, "smoke")
	d.direction = Vector3.UP
	d.spread = 85.0
	d.initial_velocity_min = 0.6
	d.initial_velocity_max = 1.6
	d.gravity = Vector3(0, -0.5, 0)
	d.damping_min = 2.0
	d.damping_max = 3.0
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	d.emission_ring_axis = Vector3.UP
	d.emission_ring_radius = 0.3 * size
	d.emission_ring_inner_radius = 0.1
	d.emission_ring_height = 0.02
	d.color_ramp = _ramp(Color(0.55, 0.47, 0.38))
	d.color_ramp.set_color(0, Color(0.55, 0.47, 0.38, 0.45))


static func ring(where: Vector3, c: Color, radius: float = 2.5, secs: float = 0.4) -> void:
	## a shockwave rolling out over the ground
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 1.0
	t.rings = 32
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_position = where + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.3, radius), secs).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, secs)
	tw.chain().tween_callback(mi.queue_free)


static func aura(n: Node3D, c: Color, height: float = 1.6, amount: int = 24) -> CPUParticles3D:
	## embers that keep rising around someone -- an elite, a boss
	if not on() or n == null:
		return null
	var p := CPUParticles3D.new()
	p.name = "Aura"
	p.amount = amount if _rich() else amount / 3
	p.lifetime = 1.4
	p.mesh = _quad(0.07)
	p.material_override = _mat("add")
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.55
	p.emission_ring_inner_radius = 0.35
	p.emission_ring_height = height * 0.6
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, 0.6, 0)
	p.color_ramp = _ramp(Color(minf(c.r * 1.4, 1.0), minf(c.g * 1.4, 1.0), minf(c.b * 1.4, 1.0)))
	p.position = Vector3(0, height * 0.35, 0)
	n.add_child(p)
	return p


static func trail(n: Node3D, c: Color) -> CPUParticles3D:
	## a stream of fading light left behind something flying
	if not on() or n == null:
		return null
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.amount = 28 if _rich() else 10
	p.lifetime = 0.35
	p.mesh = _quad(0.16)
	p.material_override = _mat("add")
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = sc
	p.color_ramp = _ramp(c)
	n.add_child(p)
	return p


# ---- round 52: what a blow throws off, the numbers, the qi a kill gives ------------------------
# (Robert, 2026-10-04: "action special effects that make sense") -- every
# number in data/feel.json

static var _feel := {}


static func feel(sec: String) -> Dictionary:
	if _feel.is_empty():
		var d = Game._load_json("res://data/feel.json", {}) if Game else {}
		_feel = d if d is Dictionary and not d.is_empty() else {"_empty": true}
	return _feel.get(sec, {})


static func matter_kind(stats: Dictionary) -> String:
	## what a creature is made of: flesh unless its name says bone, stone, metal ...
	var s := str(preload("res://scripts/actors/Monster.gd").skin_for(stats))
	return s if s != "" and feel("matter").has(s) else "flesh"


static func matter(where: Vector3, kind: String, away: Vector3 = Vector3.ZERO, big: bool = false) -> void:
	## what a blow knocks loose: blood from flesh, chips from bone, sparks from
	## metal, grit from stone and clay, sap from bark, embers from fire, shards
	## from crystal, wisps from a spirit -- thrown away from the blow
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var M: Dictionary = feel("matter").get(kind, feel("matter").get("flesh", {}))
	if M.is_empty():
		return
	var c := Color(0.42, 0.03, 0.04)
	var ca: Array = M.get("color", [])
	if ca.size() >= 3:
		c = Color(float(ca[0]), float(ca[1]), float(ca[2]))
	var add := bool(M.get("add", false))
	var p := _burst(root, where, int(int(M.get("count", 14)) * (1.6 if big else 1.0)), 0.6 if not add else 0.45, float(M.get("size", 0.06)), "add" if add else "solid")
	var dir := away.normalized() if away.length() > 0.01 else Vector3.UP
	p.direction = (dir + Vector3(0, 0.6, 0)).normalized()
	p.spread = 55.0 if away.length() > 0.01 else 180.0
	var sp: Array = M.get("speed", [2.0, 4.5])
	p.initial_velocity_min = float(sp[0])
	p.initial_velocity_max = float(sp[1]) * (1.25 if big else 1.0)
	p.gravity = Vector3(0, float(M.get("gravity", -11.0)), 0)
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color_ramp = _ramp(c if not add else Color(minf(c.r * 1.5, 1.0), minf(c.g * 1.5, 1.0), minf(c.b * 1.5, 1.0)), 0.0)


static func _solid_mat() -> StandardMaterial3D:
	if _mats.has("solid"):
		return _mats["solid"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.albedo_texture = _soft_dot()
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["solid"] = m
	return m


static func number(where: Vector3, amount: int, style: String = "normal") -> void:
	## a damage number that pops up off the target and fades as it rises
	var N := feel("numbers")
	if not on() or not bool(N.get("on", true)) or amount <= 0:
		return
	var root := _scene_root(null)
	if root == null:
		return
	var l := Label3D.new()
	l.text = str(amount) + ("!" if style == "crit" else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.006
	l.font_size = int(N.get("crit_size", 58)) if style == "crit" else (int(N.get("size", 40)) * (3 if style == "you" else 4) / 4)
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	var f := preload("res://scripts/core/UiStyle.gd").font("heavy")
	if f:
		l.font = f
	var cc: Array = N.get("colors", {}).get(style, [1.0, 0.95, 0.86])
	l.modulate = Color(float(cc[0]), float(cc[1]), float(cc[2])) * 1.5      # (bright enough to read through the tonemap)
	l.render_priority = 20
	root.add_child(l)
	var jitter := Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.2), randf_range(-0.35, 0.35))
	l.global_position = where + jitter
	var secs := float(N.get("secs", 0.85))
	var s0 := 1.45 if style == "crit" else 1.15
	l.scale = Vector3.ONE * s0
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + float(N.get("rise", 1.0)), secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, secs * 0.4).set_delay(secs * 0.6)
	tw.tween_property(l, "outline_modulate:a", 0.0, secs * 0.4).set_delay(secs * 0.6)
	tw.chain().tween_callback(l.queue_free)


static func beam(where: Vector3, c: Color, secs: float = 3.5) -> void:
	## round 61: a column of light where something rare fell
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.42
	cm.height = 14.0
	cm.radial_segments = 16
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(c.r, c.g, c.b, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	root.add_child(m)
	m.global_position = where + Vector3(0, 7.0, 0)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.55, 0.35)
	tw.tween_interval(secs)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tw.tween_callback(m.queue_free)
	ring(where, c, 2.2, 0.5)
	puff(where + Vector3(0, 0.8, 0), c, 1.2)


static func word(where: Vector3, text: String, c: Color = Color(1.0, 0.85, 0.35), size: int = 54) -> void:
	## round 60: a word that pops off a fighter -- OPENING!, PERFECT, GUARD BROKEN
	if not on():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	l.font_size = size
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	var f := preload("res://scripts/core/UiStyle.gd").font("heavy")
	if f:
		l.font = f
	l.modulate = c * 1.5
	l.render_priority = 21
	root.add_child(l)
	l.global_position = where
	l.scale = Vector3.ONE * 1.4
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", where.y + 0.7, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.75)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(0.75)
	tw.chain().tween_callback(l.queue_free)


static func qi_stream(from: Vector3, to: Node3D, amount_scale: float = 1.0) -> void:
	## a kill's qi, flowing into you: motes that curve up and in
	if not on() or to == null or not to.is_inside_tree():
		return
	var root := _scene_root(null)
	if root == null:
		return
	var Q := feel("qi_stream")
	var cc: Array = Q.get("color", [0.55, 0.85, 1.0])
	var col := Color(float(cc[0]), float(cc[1]), float(cc[2]))
	var n := clampi(int(round(float(Q.get("count", 7)) * amount_scale)), 3, 16)
	if not _rich():
		n = maxi(3, n / 2)
	var secs: Array = Q.get("secs", [0.45, 0.8])
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _quad(float(Q.get("size", 0.13)))
		var m: StandardMaterial3D = _mat("add").duplicate()
		m.albedo_color = col
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var start := from + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 0.9), randf_range(-0.5, 0.5))
		mi.global_position = start
		var lift := Vector3(randf_range(-1.6, 1.6), randf_range(1.4, 2.6), randf_range(-1.6, 1.6))
		var t := randf_range(float(secs[0]), float(secs[1]))
		var follow := func(k: float):
			if not is_instance_valid(mi) or not is_instance_valid(to):
				return
			var end: Vector3 = to.global_position + Vector3(0, 1.1, 0)
			var mid: Vector3 = start.lerp(end, 0.5) + lift
			var a := start.lerp(mid, k)
			var b := mid.lerp(end, k)
			mi.global_position = a.lerp(b, k)
		var tw := mi.create_tween()
		tw.tween_interval(0.12 + 0.04 * i)
		tw.tween_method(follow, 0.0, 1.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
