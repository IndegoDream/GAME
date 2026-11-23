extends RefCounted
## What people wear (Robert, 2026-10-02: "i want the characters to have more
## detail as well if its possible"). The Kenney figures are plain blocks; this
## dresses them from simple shapes pinned to their bones (so everything moves
## with them): hair and topknots, straw hats and scholar caps, beards, robes
## and sashes, aprons, capes, shoulder guards -- and the weapon actually in
## your hand. Townsfolk dress for their trade; rivals in their sect's colour;
## monsters get glowing eyes, tusks, spikes, and a crown for a boss.
## Looks only -- nothing here changes play.

const HEAD := "head"
const TORSO := "torso"
const ARM_R := "arm-right"
const ARM_L := "arm-left"

const ROLE_LOOK := {
	"merchant": {"robe": [0.85, 0.65, 0.25], "sash": [0.55, 0.2, 0.15], "hat": "scholar", "hat_color": [0.3, 0.2, 0.12]},
	"smith": {"apron": [0.35, 0.22, 0.14], "hair": "short", "beard": true, "arms_bare": true},
	"alchemist": {"robe": [0.3, 0.55, 0.35], "sash": [0.85, 0.75, 0.3], "hair": "topknot", "hat": "scholar", "hat_color": [0.15, 0.3, 0.2]},
	"guild": {"robe": [0.6, 0.18, 0.18], "cape": [0.45, 0.12, 0.12], "shoulders": [0.7, 0.6, 0.4], "hair": "short"},
	"elder": {"robe": [0.9, 0.88, 0.82], "sash": [0.5, 0.4, 0.7], "beard": true, "beard_color": [0.92, 0.92, 0.92], "hair": "topknot", "hair_color": [0.9, 0.9, 0.9]},
	"innkeeper": {"apron": [0.85, 0.82, 0.75], "hair": "long", "sash": [0.6, 0.3, 0.2]},
	"academy": {"robe": [0.92, 0.92, 0.95], "sash": [0.55, 0.3, 0.75], "cape": [0.55, 0.3, 0.75], "hair": "topknot", "hat": "crown", "hat_color": [0.8, 0.7, 0.3]},
	"tournament": {"robe": [0.75, 0.55, 0.15], "sash": [0.85, 0.2, 0.15], "hat": "rice", "hat_color": [0.75, 0.65, 0.4]},
}
const HAIR_COLORS := [[0.1, 0.08, 0.07], [0.25, 0.15, 0.08], [0.45, 0.3, 0.15], [0.7, 0.55, 0.3], [0.85, 0.85, 0.85], [0.5, 0.15, 0.1]]
const CLOTH := [[0.55, 0.45, 0.35], [0.35, 0.45, 0.55], [0.45, 0.55, 0.35], [0.6, 0.35, 0.3], [0.5, 0.45, 0.6], [0.7, 0.65, 0.5], [0.3, 0.35, 0.3]]


static func _c(a, fallback: Color = Color(0.5, 0.5, 0.5)) -> Color:
	if a is Color:
		return a
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


static func skeleton(model: Node) -> Skeleton3D:
	if model is Skeleton3D:
		return model
	for n in model.find_children("*", "Skeleton3D", true, false):
		return n
	return null


static func _attach(sk: Skeleton3D, bone: String, tag: String) -> Node3D:
	## A node that follows a bone (removed first if it's already there, so a
	## character can be re-dressed -- a new weapon in hand, say).
	var name := "Dress_" + tag
	var old := sk.get_node_or_null(NodePath(name))
	if old:
		old.free()
	var ba := BoneAttachment3D.new()
	ba.name = name
	ba.bone_name = bone
	sk.add_child(ba)
	# a bone attachment follows the bone's position and turn but not its
	# scale -- and the head is shrunk (Game.HEAD_SCALE): scale what's worn
	# on it to match
	var holder := Node3D.new()
	var i := sk.find_bone(bone)
	if i >= 0:
		holder.scale = sk.get_bone_pose_scale(i)
	ba.add_child(holder)
	return holder


static func _piece(parent: Node3D, mesh: Mesh, c: Color, at: Vector3, rot: Vector3 = Vector3.ZERO, glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, glow)
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(top: float, bottom: float, h: float, seg: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s


# ======================================================================
# dressing a person
# ======================================================================

static func spec_for(name: String, role: String = "villager", extra: Dictionary = {}) -> Dictionary:
	## Same name, same clothes -- every time you see them.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var s := {"hair": ["short", "long", "topknot", "topknot", "bald"][rng.randi() % 5],
		"hair_color": HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]}
	# (the realistic figure, Human.gd: who they are under the clothes)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash(name + "|body")
	s["sex"] = "f" if rng2.randf() < 0.45 else "m"
	s["skin"] = rng2.randi() % 2
	s["variant"] = rng2.randi() % 2
	if ROLE_LOOK.has(role):
		s.merge(ROLE_LOOK[role], true)
	else:
		# villagers: plain clothes, now and then a straw hat against the dust
		s["robe"] = CLOTH[rng.randi() % CLOTH.size()]
		if rng.randf() < 0.6:
			s["sash"] = CLOTH[rng.randi() % CLOTH.size()]
		if rng.randf() < 0.3:
			s["hat"] = "rice"
			s["hat_color"] = [0.8, 0.7, 0.45]
		if rng.randf() < 0.2:
			s["beard"] = true
	s.merge(extra, true)
	return s


static func human_spec(s: Dictionary) -> Dictionary:
	## The same clothes-spec, read for the realistic figure (Human.gd):
	## fighters and anyone caped or armoured wear the ranger's leathers,
	## everyone else the peasant's, tinted toward their robe or apron.
	var h := {"sex": str(s.get("sex", "m")), "skin": int(s.get("skin", 0)), "variant": int(s.get("variant", 0)),
		"hair": str(s.get("hair", "short")), "beard": bool(s.get("beard", false))}
	if s.has("hair_color"):
		h["hair_color"] = s["hair_color"]
	var fighter := s.has("cape") or s.has("shoulders") or str(s.get("held", "")) != "" or bool(s.get("ranger", false))
	h["outfit"] = "ranger" if fighter else "peasant"
	if s.has("robe"):
		h["tint"] = s["robe"]
	elif s.has("apron"):
		h["tint"] = s["apron"]
	h["hood"] = str(s.get("hat", "")) == "hood"
	return h


static func _human_mount(sk: Skeleton3D, bone: String, tag: String) -> Node3D:
	## Like _attach, but the holder's axes are the body's own at rest
	## (x = the figure's left, y = up, z = forward) -- whatever way the
	## bone itself happens to point -- so things are placed in plain terms.
	var holder := _attach(sk, bone, tag)
	var i := sk.find_bone(bone)
	if i >= 0:
		holder.transform = Transform3D(sk.get_bone_global_rest(i).basis.orthonormalized().inverse(), Vector3.ZERO)
	return holder


static func dress_human(model: Node, s: Dictionary) -> void:
	## The realistic figure brings its own clothes, hair and beard
	## (Human.make); this adds what's worn on top -- a hat -- and what's held.
	var sk := skeleton(model)
	if sk == null:
		return
	var head := _human_mount(sk, "Head", "head")
	match str(s.get("hat", "")):
		"rice":
			# round 47: woven straw, not a flat yellow cone
			var rh := _piece(head, _cyl(0.015, 0.3, 0.12, 32), _c(s.get("hat_color", [0.8, 0.7, 0.45])), Vector3(0, 0.25, 0.01))
			rh.material_override = _photo("thatch_roof_angled", _c(s.get("hat_color", [0.8, 0.7, 0.45])).lightened(0.3), 6.0)
		"scholar":
			# round 47: a soft scholar's cap that sits on the crown, with a knot on top (was a box)
			var cap := _piece(head, _cyl(0.098, 0.112, 0.075, 32), _c(s.get("hat_color", [0.2, 0.2, 0.25])), Vector3(0, 0.2, -0.012))
			cap.material_override = _photo("rough_linen", _c(s.get("hat_color", [0.2, 0.2, 0.25])), 8.0)
			_piece(head, _cyl(0.02, 0.028, 0.03, 16), _c(s.get("hat_color", [0.2, 0.2, 0.25])).darkened(0.25), Vector3(0, 0.25, -0.012))
		"crown":
			_piece(head, _cyl(0.06, 0.07, 0.06, 8), _c(s.get("hat_color", [0.8, 0.7, 0.3])), Vector3(0, 0.25, -0.02), Vector3.ZERO, 0.4)
	hold_human(model, str(s.get("held", "")), s.get("held_color", null))


static var HUMAN_GRIP := Vector3(-0.01, 0.13, -0.02)
static var HUMAN_GRIP_ROT := -999.0
static var BLADE_Z := 0.10          # r149: where along the grip the sword's handle sits (its middle in the fist)                # tests override; -999 = by kind
# round 146 (Robert: "still doesn't look like it's holding the weapons"): the hand hangs at the hip when idle, so a blade
# pointing up and forward crossed the chest, away from the fist. Each kind now rests the way it would be carried:
# blades down-forward in a low guard, hafted heads up and forward, the stave held upright, the crossbow level.
const GRIP_PITCH := {"sword": -50.0, "saber": -50.0, "dagger": -45.0, "axe": -40.0, "hammer": -40.0, "crossbow": -35.0,
	"bow": -10.0, "spear": 18.0, "halberd": 18.0, "staff": 25.0, "ki": 0.0, "fists": 0.0}      # the middle of the fist, from the hand bone


static func hold_human(model: Node, kind: String, tint = null) -> void:
	var sk := skeleton(model)
	if sk == null:
		return
	var hand := _attach(sk, "hand_r", "held")
	if kind == "" or not HELD.has(kind):
		return
	var grip := Node3D.new()
	grip.name = "Grip"
	# out of the thumb side of the fist: the hand bone's -y (found by eye,
	# rendering each axis through the sword attack -- see DEV_GUIDE)
	# round 119 (Robert: "the way the weapon is held is weird"): it used to
	# stick up and BACK over the shoulder. -15 deg about the hand's x puts it
	# in a ready guard, pointing forward and a little up (rendered side-on)
	grip.rotation = Vector3(deg_to_rad(HUMAN_GRIP_ROT if HUMAN_GRIP_ROT > -900.0 else float(GRIP_PITCH.get(kind, -15.0))), 0, 0)
	grip.position = HUMAN_GRIP
	hand.add_child(grip)
	if kind in ["sword", "saber", "dagger"]:
		# the photo-scanned blade (Art.gd), pointing out of the fist
		var blade: Node3D = preload("res://scripts/core/Art.gd").make("mini-dungeon/weapon-sword.glb", 0 if kind != "saber" else 1)
		blade.rotation = Vector3(PI / 2, 0, 0)       # forward out of the fist
		blade.scale = Vector3.ONE * (2.0 if kind != "dagger" else 1.2)
		blade.position = Vector3(0, 0, BLADE_Z if kind != "dagger" else BLADE_Z - 0.11)
		grip.add_child(blade)
		return
	# everything else: made here, at a person's size -- round 47 (Robert: "can
	# the equipment be smoother, more realistic and not so blocky"): turned
	# wooden hafts in real wood, forged heads with curved edges, no boxes
	_held_real(grip, kind, tint)


static func dress(model: Node, s: Dictionary) -> void:
	if model.has_meta("human"):
		dress_human(model, s)
		return
	var sk := skeleton(model)
	if sk == null:
		return
	var hc := _c(s.get("hair_color", [0.15, 0.1, 0.08]))
	var head := _attach(sk, HEAD, "head")
	# (the head bone sits at the neck; the head itself is ~0.41 tall, ~0.45
	# wide, its face toward +z)
	match str(s.get("hair", "short")):
		"short":
			_piece(head, _box(0.47, 0.12, 0.38), hc, Vector3(0, 0.38, 0.0))
			_piece(head, _box(0.47, 0.24, 0.06), hc, Vector3(0, 0.3, -0.17))
		"long":
			_piece(head, _box(0.48, 0.12, 0.39), hc, Vector3(0, 0.38, 0.0))
			_piece(head, _box(0.48, 0.5, 0.08), hc, Vector3(0, 0.18, -0.18))
		"topknot":
			_piece(head, _box(0.47, 0.1, 0.38), hc, Vector3(0, 0.38, 0.0))
			_piece(head, _box(0.47, 0.18, 0.05), hc, Vector3(0, 0.32, -0.17))
			_piece(head, _ball(0.09), hc, Vector3(0, 0.49, -0.04))
			_piece(head, _cyl(0.022, 0.022, 0.26, 6), Color(0.85, 0.75, 0.4), Vector3(0, 0.5, -0.04), Vector3(0, 0, PI / 2))   # the hairpin
		_:
			pass
	match str(s.get("hat", "")):
		"rice":
			_piece(head, _cyl(0.02, 0.42, 0.16, 16), _c(s.get("hat_color", [0.8, 0.7, 0.45])), Vector3(0, 0.5, 0.0))
		"scholar":
			_piece(head, _box(0.34, 0.14, 0.3), _c(s.get("hat_color", [0.2, 0.2, 0.25])), Vector3(0, 0.47, -0.02))
		"crown":
			_piece(head, _cyl(0.11, 0.12, 0.1, 8), _c(s.get("hat_color", [0.8, 0.7, 0.3])), Vector3(0, 0.47, -0.02), Vector3.ZERO, 0.4)
		"hood":
			_piece(head, _box(0.52, 0.48, 0.44), _c(s.get("hat_color", [0.3, 0.3, 0.35])), Vector3(0, 0.22, -0.02))
	if bool(s.get("beard", false)):
		var bc := _c(s.get("beard_color", hc))
		_piece(head, _box(0.3, 0.16, 0.06), bc, Vector3(0, 0.05, 0.2))
		_piece(head, _box(0.14, 0.1, 0.05), bc, Vector3(0, -0.06, 0.2))
	var torso := _attach(sk, TORSO, "torso")
	# (the torso bone sits at the hips; the chest is ~0.19 tall above it)
	if s.has("robe"):
		var rc := _c(s["robe"])
		_piece(torso, _cyl(0.17, 0.24, 0.19, 12), rc, Vector3(0, -0.07, 0))            # the skirt of the robe, over the legs
		_piece(torso, _box(0.3, 0.17, 0.25), rc, Vector3(0, 0.1, 0))                     # its body
		_piece(torso, _box(0.05, 0.17, 0.02), rc.darkened(0.25), Vector3(0.04, 0.1, 0.13), Vector3(0, 0, 0.25))    # the crossed collar
	if s.has("apron"):
		_piece(torso, _box(0.28, 0.32, 0.03), _c(s["apron"]), Vector3(0, 0.0, 0.14))
	if s.has("sash"):
		_piece(torso, _cyl(0.175, 0.175, 0.045, 14), _c(s["sash"]), Vector3(0, 0.02, 0))
		_piece(torso, _box(0.06, 0.12, 0.02), _c(s["sash"]), Vector3(0.09, -0.04, 0.17))
	if s.has("cape"):
		_piece(torso, _box(0.34, 0.36, 0.025), _c(s["cape"]), Vector3(0, 0.02, -0.15), Vector3(-0.08, 0, 0))
	if s.has("shoulders"):
		for side in [[ARM_R, -1.0, "sr"], [ARM_L, 1.0, "sl"]]:
			var arm := _attach(sk, str(side[0]), str(side[2]))
			_piece(arm, _box(0.14, 0.05, 0.16), _c(s["shoulders"]), Vector3(float(side[1]) * 0.07, 0.03, 0))
	if s.has("held"):
		hold(model, str(s["held"]), s.get("held_color", null))


# ======================================================================
# the weapon in your hand
# ======================================================================

const HELD := {
	# kind: [blade length, blade width, handle length, head shape]
	"sword": [0.42, 0.045, 0.1, "blade"], "dagger": [0.22, 0.04, 0.08, "blade"], "saber": [0.4, 0.05, 0.1, "curve"],
	"spear": [0.12, 0.05, 0.8, "point"], "axe": [0.0, 0.0, 0.42, "axe"], "hammer": [0.0, 0.0, 0.45, "hammer"],
	"halberd": [0.14, 0.05, 0.85, "halberd"], "staff": [0.0, 0.0, 0.8, "staff"], "fists": [0.0, 0.0, 0.0, "wraps"],
	# round 119: the distance weapons
	"bow": [0.0, 0.0, 0.5, "bow"], "crossbow": [0.0, 0.0, 0.3, "xbow"], "ki": [0.0, 0.0, 0.0, "kifocus"],
}


static func hold(model: Node, kind: String, tint = null) -> void:
	## Put a weapon of this kind in the right hand ("" = empty hands). It
	## rides the arm bone, so it swings with every attack.
	if model.has_meta("human"):
		hold_human(model, kind, tint)
		return
	var sk := skeleton(model)
	if sk == null:
		return
	var hand := _attach(sk, ARM_R, "held")
	if kind == "" or not HELD.has(kind):
		return
	var grip := Node3D.new()
	grip.name = "Grip"
	# the hand is at the end of the arm (arm points out and down from the
	# shoulder); the weapon points forward out of the fist
	grip.position = Vector3(-0.2, -0.05, 0.03)
	grip.rotation = Vector3(deg_to_rad(-35.0), 0, 0)   # round 119: it used to stick out sideways; now forward and a little up
	hand.add_child(grip)
	_held_shapes(grip, kind, tint)


static var _photos := {}


static func _photo(folder: String, tint: Color, scale: float) -> Material:
	## a photographed surface that rides on what it's on (object space -- a hat
	## turns with the head and its weave turns with it)
	var key := "%s|%s|%s" % [folder, tint.to_html(), scale]
	if _photos.has(key):
		return _photos[key]
	var L := preload("res://scripts/world/Look.gd")
	var m := StandardMaterial3D.new()
	_photos[key] = m
	m.albedo_color = tint
	m.roughness = 0.9
	if DisplayServer.get_name() != "headless":
		var a: Texture2D = L.texture(folder, "albedo")
		if a:
			m.albedo_texture = a
		var n: Texture2D = L.texture(folder, "normal")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


static func _wood() -> Material:
	return _photo("fine_grained_wood", Color(0.95, 0.82, 0.68), 5.0)


static func _metal(tint) -> Material:
	var c := _c(tint, Color(0.78, 0.8, 0.85)) if tint != null else Color(0.78, 0.8, 0.85)
	return preload("res://scripts/actors/Armour.gd").material("metal", c)


static func _mesh_at(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, b: Basis = Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(b, at)
	parent.add_child(mi)
	return mi


static func _haft(r: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r * 0.9
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 18
	c.rings = 2
	return c


static var _extrusions := {}


static func _extrude(pts: Array, thick: float, edge: float = 0.35) -> ArrayMesh:
	## a flat forged shape: the outline `pts` (x, y) given thickness along z,
	## thinning toward the outline so an edge reads as an edge
	var key := "%s|%s|%s" % [str(pts), thick, edge]
	if _extrusions.has(key):
		return _extrusions[key]
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(float(p[0]), float(p[1])))
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= poly.size()
	var tri := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := thick * 0.5
	for side in [1.0, -1.0]:
		for i in range(0, tri.size(), 3):
			var idx := [tri[i], tri[i + 1], tri[i + 2]] if side > 0 else [tri[i], tri[i + 2], tri[i + 1]]
			for k in idx:
				var v: Vector2 = poly[k]
				st.set_uv(v * 4.0)
				st.add_vertex(Vector3(v.x, v.y, hz * side * edge))
	# the sides: from the thin edge to the full thickness at the middle, as a bevel
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		for side in [1.0, -1.0]:
			var q := [Vector3(a.x, a.y, hz * side * edge), Vector3(b.x, b.y, hz * side * edge), Vector3(b.x, b.y, 0.0), Vector3(a.x, a.y, 0.0)]
			var order := [0, 2, 1, 0, 3, 2] if side > 0 else [0, 1, 2, 0, 2, 3]
			for o in order:
				st.set_uv(Vector2(float(o % 2), float(o / 2)))
				st.add_vertex(q[o])
	st.generate_normals()
	var m := st.commit()
	_extrusions[key] = m
	return m


static func _held_real(grip: Node3D, kind: String, tint = null) -> void:
	## a weapon in metres, pointing +z out of the fist (the haft runs back
	## through the hand for the long ones)
	var h: Array = HELD[kind]
	var metal := _metal(tint)
	var wood := _wood()
	var down := Basis(Vector3.RIGHT, PI / 2)            # cylinders are built on y: lay them along z
	var A := preload("res://scripts/actors/Armour.gd")
	match str(h[3]):
		"point", "halberd":
			var L := float(h[2]) * 2.0
			_mesh_at(grip, _haft(0.017, L), wood, Vector3(0, 0, L * 0.25), down)
			# a leaf-shaped spearhead, flat in section, and its socket
			var leaf := []
			for i in 13:
				var t := float(i) / 12.0
				leaf.append([0.06 - 0.24 * t, 0.006 + 0.032 * sin(PI * pow(t, 0.7)) * (1.0 - t * 0.85)])
			_mesh_at(grip, A._lathe(leaf, 24), metal, Vector3(0, 0, L * 0.75 + 0.12), down * Basis.from_scale(Vector3(1.0, 1.0, 0.3)).rotated(Vector3.FORWARD, 0.0))
			_mesh_at(grip, A._tube(0.02, 0.022, 0.07, 12), metal, Vector3(0, 0, L * 0.75 + 0.015), down)
			_mesh_at(grip, A._rim(0.022, 0.004), metal, Vector3(0, 0, L * 0.75 - 0.02), down)
			if str(h[3]) == "halberd":
				var hb := [[0.0, 0.0], [0.03, -0.02], [0.17, -0.09], [0.2, -0.02], [0.21, 0.06], [0.19, 0.13], [0.15, 0.1], [0.04, 0.05], [0.0, 0.04]]
				_mesh_at(grip, _extrude(hb, 0.014), metal, Vector3(0, 0, L * 0.72), Basis(Vector3.FORWARD, PI / 2) * Basis(Vector3.UP, PI / 2))
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = 0.012
				spike.height = 0.1
				spike.radial_segments = 10
				_mesh_at(grip, spike, metal, Vector3(0, -0.06, L * 0.72), Basis(Vector3.RIGHT, PI))
		"axe":
			var L2 := float(h[2]) * 2.0
			_mesh_at(grip, _haft(0.018, L2), wood, Vector3(0, 0, L2 * 0.35), down)
			# a bearded blade with a curved cutting edge, and the eye round the haft
			var ax := [[0.0, -0.03], [0.06, -0.035], [0.14, -0.1], [0.17, -0.06], [0.185, 0.0], [0.18, 0.07], [0.15, 0.11], [0.07, 0.045], [0.0, 0.035]]
			_mesh_at(grip, _extrude(ax, 0.022), metal, Vector3(0, 0, L2 * 0.78), Basis(Vector3.FORWARD, PI / 2) * Basis(Vector3.UP, PI / 2))
			_mesh_at(grip, A._tube(0.024, 0.024, 0.075, 12), metal, Vector3(0, 0, L2 * 0.78), Basis())
		"hammer":
			var L3 := float(h[2]) * 2.0
			_mesh_at(grip, _haft(0.02, L3), wood, Vector3(0, 0, L3 * 0.35), down)
			# a round forged head across the haft, banded at the faces
			_mesh_at(grip, A._tube(0.048, 0.048, 0.2, 14), metal, Vector3(0, 0, L3 * 0.8), Basis())
			for e in [-1.0, 1.0]:
				_mesh_at(grip, A._rim(0.05, 0.007), metal, Vector3(0, e * 0.085, L3 * 0.8), Basis())
		"staff":
			var L4 := float(h[2]) * 2.0
			_mesh_at(grip, _haft(0.02, L4), wood, Vector3(0, 0, L4 * 0.2), down)
			for z in [0.55, 0.62]:
				_mesh_at(grip, A._rim(0.022, 0.005), metal, Vector3(0, 0, L4 * z), down)
			var orb := SphereMesh.new()
			orb.radius = 0.05
			orb.height = 0.1
			orb.radial_segments = 24
			orb.rings = 12
			_piece(grip, orb, Color(0.5, 0.85, 1.0), Vector3(0, 0, L4 * 0.7 + 0.05), Vector3.ZERO, 1.5)
			_mesh_at(grip, A._rim(0.05, 0.005), metal, Vector3(0, 0, L4 * 0.7 + 0.03), down)
		"bow":
			# a recurve: the stave runs up the fist (grip y), belly bowed forward, a string across the tips
			var pts := []
			for i in 11:
				var t := float(i) / 10.0 * 2.0 - 1.0
				pts.append(Vector3(0, t * 0.4, 0.14 * (1.0 - t * t) - 0.05 + 0.1 * pow(absf(t), 3.0)))
			for i in range(1, pts.size()):
				var a: Vector3 = pts[i - 1]
				var b: Vector3 = pts[i]
				var seg := b - a
				_mesh_at(grip, _haft(0.024 - 0.012 * absf(float(i) / 5.0 - 1.0), seg.length() + 0.006), wood, (a + b) * 0.5, Basis(Quaternion(Vector3.UP, seg.normalized())))
			_mesh_at(grip, A._tube(0.019, 0.019, 0.1, 10), preload("res://scripts/actors/Armour.gd").material("cloth", Color(0.3, 0.18, 0.1)), Vector3(0, 0, 0.08), Basis())
			var s0: Vector3 = pts[0]
			var s1: Vector3 = pts[pts.size() - 1]
			var sd := s1 - s0
			_mesh_at(grip, _haft(0.004, sd.length()), preload("res://scripts/actors/Armour.gd").material("cloth", Color(0.9, 0.88, 0.8)), (s0 + s1) * 0.5, Basis(Quaternion(Vector3.UP, sd.normalized())))
		"xbow":
			# a stock pointing out of the fist, a steel prod across the front, a bolt laid in the groove
			var SL := 0.62
			_mesh_at(grip, _haft(0.024, SL), wood, Vector3(0, 0, SL * 0.35), down)
			var px := SL * 0.35 + SL * 0.5 - 0.04
			for side in [-1.0, 1.0]:
				_mesh_at(grip, A._tube(0.008, 0.012, 0.3, 8), metal, Vector3(side * 0.15, 0, px), Basis(Vector3.FORWARD, PI / 2 + side * 0.18))
			_mesh_at(grip, _haft(0.003, 0.3), preload("res://scripts/actors/Armour.gd").material("cloth", Color(0.9, 0.88, 0.8)), Vector3(0, 0, px - 0.12), Basis(Vector3.FORWARD, PI / 2))
			_mesh_at(grip, _haft(0.006, SL * 0.8), metal, Vector3(0, 0.03, SL * 0.4), down)
			_mesh_at(grip, A._tube(0.0, 0.012, 0.05, 8), metal, Vector3(0, 0.03, SL * 0.8 + 0.02), down)
		"kifocus":
			# no weapon at all: a wrapped fist with a small sphere of your own qi turning over it
			for i in 3:
				_mesh_at(grip, A._rim(0.045, 0.01), preload("res://scripts/actors/Armour.gd").material("cloth", Color(0.85, 0.82, 0.75)), Vector3(0, 0, -0.04 + i * 0.03), down)
			var core := SphereMesh.new()
			core.radius = 0.055
			core.height = 0.11
			core.radial_segments = 24
			core.rings = 12
			var cm := _piece(grip, core, Color(0.45, 0.8, 1.0), Vector3(0, 0, 0.16), Vector3.ZERO, 1.1)
			_piece(grip, A._rim(0.085, 0.004), Color(0.6, 0.9, 1.0), Vector3(0, 0, 0.16), Vector3(0.5, 0.2, 0), 1.0)
			cm.set_meta("ki", true)
		"wraps":
			for i in 3:
				_mesh_at(grip, A._rim(0.045, 0.01), preload("res://scripts/actors/Armour.gd").material("cloth", Color(0.85, 0.82, 0.75)), Vector3(0, 0, -0.04 + i * 0.03), down)
		_:
			var big := Node3D.new()
			big.scale = Vector3.ONE * 2.0
			grip.add_child(big)
			_held_shapes(big, kind, tint)


static func _held_shapes(grip: Node3D, kind: String, tint = null) -> void:
	var h: Array = HELD[kind]
	var metal := _c(tint, Color(0.78, 0.8, 0.85)) if tint != null else Color(0.78, 0.8, 0.85)
	var wood := Color(0.42, 0.28, 0.16)
	match str(h[3]):
		"blade", "curve":
			_piece(grip, _box(0.03, 0.03, float(h[2])), wood, Vector3(0, 0, 0))
			_piece(grip, _box(0.11, 0.03, 0.025), Color(0.75, 0.6, 0.25), Vector3(0, 0, float(h[2]) / 2.0))
			var bl := _piece(grip, _box(float(h[1]), 0.012, float(h[0])), metal, Vector3(0, 0, float(h[2]) / 2.0 + float(h[0]) / 2.0), Vector3.ZERO, 0.15)
			if str(h[3]) == "curve":
				bl.rotation.y = 0.12
		"point", "halberd":
			_piece(grip, _cyl(0.018, 0.018, float(h[2]), 6), wood, Vector3(0, 0, float(h[2]) * 0.25), Vector3(PI / 2, 0, 0))
			_piece(grip, _cyl(0.0, 0.035, float(h[0]), 6), metal, Vector3(0, 0, float(h[2]) * 0.75 + float(h[0]) / 2.0), Vector3(PI / 2, 0, 0), 0.15)
			if str(h[3]) == "halberd":
				_piece(grip, _box(0.02, 0.14, 0.12), metal, Vector3(0, 0.06, float(h[2]) * 0.7), Vector3.ZERO, 0.15)
		"axe":
			_piece(grip, _cyl(0.018, 0.02, float(h[2]), 6), wood, Vector3(0, 0, float(h[2]) * 0.35), Vector3(PI / 2, 0, 0))
			_piece(grip, _box(0.02, 0.16, 0.12), metal, Vector3(0, 0.07, float(h[2]) * 0.75), Vector3.ZERO, 0.15)
		"hammer":
			_piece(grip, _cyl(0.02, 0.022, float(h[2]), 6), wood, Vector3(0, 0, float(h[2]) * 0.35), Vector3(PI / 2, 0, 0))
			_piece(grip, _box(0.1, 0.1, 0.16), metal.darkened(0.2), Vector3(0, 0, float(h[2]) * 0.78))
		"staff":
			_piece(grip, _cyl(0.02, 0.022, float(h[2]), 8), wood, Vector3(0, 0, float(h[2]) * 0.2), Vector3(PI / 2, 0, 0))
			_piece(grip, _ball(0.04), Color(0.5, 0.85, 1.0), Vector3(0, 0, float(h[2]) * 0.62), Vector3.ZERO, 1.5)
		"wraps":
			_piece(grip, _box(0.09, 0.09, 0.09), Color(0.85, 0.82, 0.75), Vector3(0.0, 0, -0.03))


# ======================================================================
# monsters
# ======================================================================

static func dress_monster(model: Node, stats: Dictionary) -> void:
	## Glowing eyes on every monster; tusks and shoulder spikes on the big
	## ones; a crown of horns on a boss.
	var sk := skeleton(model)
	if sk == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(stats.get("name", "")))
	var t: Array = stats.get("tint", [1, 1, 1])
	var eye := Color(1.0, 0.25, 0.1)
	var tc := _c(t, Color(1, 1, 1))
	if tc.b > tc.r + 0.15:
		eye = Color(0.4, 0.8, 1.0)
	elif tc.g > tc.r + 0.15:
		eye = Color(0.7, 1.0, 0.3)
	var head := _attach(sk, HEAD, "head")
	for side in [-1.0, 1.0]:
		_piece(head, _ball(0.035), eye, Vector3(side * 0.09, 0.22, 0.19), Vector3.ZERO, 3.5)
	var big := float(stats.get("scale", 1.0)) >= 1.25 or bool(stats.get("boss", false))
	if big or rng.randf() < 0.5:
		for side in [-1.0, 1.0]:
			_piece(head, _cyl(0.0, 0.025, 0.09, 6), Color(0.95, 0.92, 0.8), Vector3(side * 0.1, 0.06, 0.2), Vector3(-0.3, 0, 0))   # tusks
	var torso := _attach(sk, TORSO, "torso")
	_piece(torso, _cyl(0.18, 0.18, 0.04, 10), Color(0.3, 0.2, 0.12), Vector3(0, 0.02, 0))         # a crude belt
	if big:
		for side in [[ARM_R, -1.0, "sr"], [ARM_L, 1.0, "sl"]]:
			var arm := _attach(sk, str(side[0]), str(side[2]))
			_piece(arm, _box(0.14, 0.05, 0.16), Color(0.35, 0.33, 0.32), Vector3(float(side[1]) * 0.07, 0.03, 0))
			_piece(arm, _cyl(0.0, 0.03, 0.1, 6), Color(0.8, 0.78, 0.72), Vector3(float(side[1]) * 0.07, 0.1, 0))
	if bool(stats.get("boss", false)):
		for i in 5:
			var a := -0.6 + i * 0.3
			_piece(head, _cyl(0.0, 0.03, 0.14 + (0.06 if i == 2 else 0.0), 6), Color(0.85, 0.7, 0.3), Vector3(sin(a) * 0.2, 0.46, cos(a) * 0.05), Vector3(0, 0, -a * 0.5), 0.6)
