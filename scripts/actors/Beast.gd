extends Node3D
## Beast: an animal that looks like one (round 29 -- Robert: "less blocky
## and more smooth ... more realistic"). The old beasts were a capsule, a
## ball and four sticks; now each animal is built to its kind -- a hare's
## long ears and big hind legs, a boar's bulk and tusks, a stag's antlers,
## a lizard's long tail, a crab's shell and claws, a crow's wings -- from
## smooth rounded shapes, with a fur (or shell, or scale) surface that
## catches the light, and it MOVES: legs swing in a gait as fast as it
## goes, a tail sways, a bird's wings beat, a worm ripples, a hare hops.
##
## Same size as before at scale 1 (about half a metre long; Enemy and
## Familiar draw it at 2x their scale), so nothing about play changes.
## Beast.build(name, colour) picks the body from words in the name.

const PLANS := {
	"golem": ["golem", "construct"],
	"hare": ["hare", "rabbit", "bunny", "jackal"],
	"boar": ["boar", "hog", "pig", "bear", "badger"],
	"stag": ["stag", "deer", "elk", "goat", "ram", "antelope", "horse", "ox"],
	"ferret": ["ferret", "mole", "weasel", "rat", "otter", "stoat", "mouse", "fox", "wolf", "hound", "dog", "cat", "lynx"],
	"lizard": ["lizard", "salamander", "newt", "drake", "gecko", "croc", "serpent", "snake"],
	"toad": ["toad", "frog"],
	"crab": ["crab", "beetle", "spider", "scorpion", "tick", "mite", "ant"],
	"bird": ["crow", "crane", "bird", "hawk", "raven", "heron", "owl", "sparrow", "eagle", "moth", "bat", "butterfly"],
	"worm": ["worm", "grub", "larva", "slug", "centipede", "eel"],
}

var plan := "ferret"
var flies := false
var _legs: Array = []           # [pivot, phase, swing]
var _wings: Array = []          # [pivot, side]
var _tail: Node3D
var _head: Node3D
var _torso: Node3D
var _segments: Array = []
var _t := 0.0
var _speed := 0.0
var _last := Vector3.ZERO
var _have_last := false
var _dead := false
var _mat: StandardMaterial3D
var _dark: StandardMaterial3D
var _pale: StandardMaterial3D

static var _noise_tex: Texture2D = null


static func plan_for(name: String) -> String:
	var n := name.to_lower()
	for p in PLANS:
		for w in PLANS[p]:
			if n.contains(str(w)):
				return p
	return "ferret"


static func build(name: String, c: Color) -> Node3D:
	var b = (load("res://scripts/actors/Beast.gd") as GDScript).new()
	b.name = "Beast"
	b.plan = plan_for(name)
	b.flies = b.plan == "bird" and not name.to_lower().contains("crane")
	b._make(c, name.to_lower())
	return b


# ---- surfaces -------------------------------------------------------------

static func _grain() -> Texture2D:
	## one fine bumpy normal map shared by every beast: fur, hide, scale
	if _noise_tex == null:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 4.0
		var fn := FastNoiseLite.new()
		fn.frequency = 0.09
		fn.fractal_octaves = 3
		nt.noise = fn
		_noise_tex = nt
	return _noise_tex


func _surface(c: Color, shiny: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.35 if shiny else 0.88
	m.metallic = 0.15 if shiny else 0.0
	if DisplayServer.get_name() != "headless":
		m.normal_enabled = true
		m.normal_texture = _grain()
		m.normal_scale = 0.35 if shiny else 0.7
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 6.0
		if not shiny:
			m.rim_enabled = true          # a soft edge of light, like fur
			m.rim = 0.35
			m.rim_tint = 0.7
	return m


func _blob(parent: Node3D, size: Vector3, at: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO) -> MeshInstance3D:
	## a smooth ellipsoid, size = full width/height/length
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	mi.scale = size
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, r_top: float, r_bot: float, length: float, mat: StandardMaterial3D) -> MeshInstance3D:
	## a tapered rounded limb hanging DOWN from its parent's origin
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = length
	cm.radial_segments = 14
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(0, -length * 0.5, 0)
	parent.add_child(mi)
	var foot := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = maxf(r_bot, 0.008) * 1.15
	fs.height = fs.radius * 2.0
	fs.radial_segments = 12
	fs.rings = 6
	foot.mesh = fs
	foot.material_override = mat
	foot.position = Vector3(0, -length, 0)
	parent.add_child(foot)
	return mi


func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = at
	parent.add_child(p)
	return p


func _cone(parent: Node3D, r: float, length: float, at: Vector3, rot: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _leg(at: Vector3, r_top: float, r_bot: float, length: float, phase: float, swing: float, mat: StandardMaterial3D = null, splay := 0.0) -> Node3D:
	var p := _pivot(_torso, at)
	p.rotation.z = splay
	_limb(p, r_top, r_bot, length, mat if mat else _mat)
	_legs.append([p, phase, swing])
	return p


func _eyes(head: Node3D, at: Vector3, spread: float, r: float) -> void:
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.03, 0.03, 0.03)
	em.roughness = 0.05
	em.metallic = 0.3
	for sd in [-1.0, 1.0]:
		var e := _blob(head, Vector3.ONE * r * 2.0, at + Vector3(sd * spread, 0, 0), em)
		e.name = "Eye"


# ---- evolution: how a grown beast looks different (round 153) ----------------------------------------------
# stage 1 grown: a dark stripe down the back.  stage 2 fierce: a spine of bone spikes, horns, eyes that burn in its role's
# colour.  stage 3 spirit beast: a mane and tail of living light, glowing marks on its flanks, a faint sheen on the whole body.

func _extent(node: Node3D) -> Dictionary:
	## the bounds of the smooth blobs directly under node (what the body is made of)
	var top := -9.0
	var half_w := 0.0
	var z0 := 9.0
	var z1 := -9.0
	var found := false
	for ch in node.get_children():
		if ch is MeshInstance3D and ch.mesh is SphereMesh and ch.name != "Eye" and ch.scale.x > 0.07:
			var sc: Vector3 = ch.scale
			var po: Vector3 = ch.position
			top = maxf(top, po.y + sc.y * 0.5)
			half_w = maxf(half_w, sc.x * 0.5)
			z0 = minf(z0, po.z - sc.z * 0.5)
			z1 = maxf(z1, po.z + sc.z * 0.5)
			found = true
	return {"ok": found, "top": top, "hw": half_w, "z0": z0, "z1": z1, "zc": (z0 + z1) * 0.5, "len": z1 - z0}


func _glow(c: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func evolve(stage: int, accent: Color) -> void:
	if stage <= 0 or _torso == null:
		return
	var t := _extent(_torso)
	if not bool(t["ok"]):
		return
	var top: float = t["top"]
	var hw: float = t["hw"]
	var zc: float = t["zc"]
	var ln: float = t["len"]
	# 1: a stripe down the back
	_blob(_torso, Vector3(hw * 0.42, 0.03 + hw * 0.2, ln * 0.8), Vector3(0, top - 0.012, zc), _dark)
	if stage < 2:
		return
	# 2: spikes down the spine, horns, burning eyes
	var bone := _surface(_mat.albedo_color.lerp(accent, 0.3).lightened(0.25), true)
	for i in 5:
		var z: float = float(t["z0"]) + ln * (0.18 + 0.16 * float(i))
		var h := hw * (0.55 + 0.35 * sin(PI * float(i) / 4.0))
		_cone(_torso, hw * 0.13, h, Vector3(0, top + h * 0.35, z), Vector3(-0.35, 0, 0), bone)
	if _head != null:
		var h2 := _extent(_head)
		var hhw: float = h2["hw"] if bool(h2["ok"]) else 0.06
		var htop: float = h2["top"] if bool(h2["ok"]) else 0.06
		var hzc: float = h2["zc"] if bool(h2["ok"]) else 0.0
		for sd in [-1.0, 1.0]:
			_cone(_head, hhw * 0.22, hhw * 1.5, Vector3(sd * hhw * 0.45, htop + hhw * 0.2, hzc - hhw * 0.2), Vector3(-0.7, 0, sd * -0.3), bone)
		for ch in _head.get_children():
			if ch is MeshInstance3D and ch.name == "Eye":
				var gm := _glow(accent)
				ch.material_override = gm
				ch.scale *= 1.3
	if stage < 3:
		return
	# 3: a mane and tail of living light, marks on the flanks, a sheen
	var wisp := _glow(accent, 0.62)
	if _head != null:
		var h3 := _extent(_head)
		var r: float = (h3["hw"] if bool(h3["ok"]) else 0.06) * 0.95
		var base_z: float = (h3["z0"] if bool(h3["ok"]) else -0.05) + 0.02
		var wl: float = r * 4.6
		for i in 7:
			var a := TAU * float(i) / 7.0
			var base := Vector3(cos(a) * r, sin(a) * r * 0.9, base_z)
			_cone(_head, r * 0.4, wl, base + Vector3(0, 0, -wl * 0.5), Vector3(-PI / 2 + sin(a) * 0.15, 0, cos(a) * 0.15), wisp)
	if _tail != null:
		for i in 3:
			var sp := (float(i) - 1.0) * 0.35
			_cone(_tail, hw * 0.22, ln * 0.7, Vector3(sin(sp) * ln * 0.25, 0.0, -ln * 0.35), Vector3(-PI / 2, 0, sp), wisp)
	var mark := _glow(accent)
	for sd in [-1.0, 1.0]:
		_blob(_torso, Vector3(0.012, hw * 0.7, ln * 0.28), Vector3(sd * hw * 0.97, 0.0, zc), mark)
	_mat.emission_enabled = true
	_mat.emission = accent
	_mat.emission_energy_multiplier = 0.22


func lineage(stage: int, variant: String, vcol: Color, mixcol: Color, gen: int) -> void:
	## round 167: bred blood is seen, not just tinted -- each mutation grows its own features, a
	## second species shows as patches, and generations add marks; all of it deepens with the stage
	if _torso == null:
		return
	var t := _extent(_torso)
	if not bool(t["ok"]):
		return
	var top: float = t["top"]
	var hw: float = t["hw"]
	var zc: float = t["zc"]
	var ln: float = t["len"]
	var s: int = clampi(stage, 0, 3)
	var gl := _glow(vcol)
	var soft := _glow(vcol, 0.55)
	var hh: Dictionary = _extent(_head) if _head != null else {"ok": false}
	var hhw: float = hh["hw"] if bool(hh["ok"]) else 0.06
	var htop: float = hh["top"] if bool(hh["ok"]) else 0.06
	var hzc: float = hh["zc"] if bool(hh["ok"]) else 0.0
	match variant:
		"gilded":
			var n := 4 + s * 3
			for i in n:
				var a := float(i) * 2.399
				var z: float = zc + sin(a * 1.7) * ln * 0.38
				var x: float = cos(a) * hw * 0.55
				_blob(_torso, Vector3.ONE * (0.04 + hw * 0.1), Vector3(x, top - hw * 0.1 + absf(x) * 0.0, z), gl)
			if s >= 2 and _head != null:
				for sd in [-1.0, 1.0]:
					_cone(_head, hhw * 0.16, hhw * 0.9, Vector3(sd * hhw * 0.75, htop + hhw * 0.1, hzc - hhw * 0.3), Vector3(-0.4, 0, sd * -0.5), gl)
			if s >= 3 and _head != null:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = hhw * 1.1
				tm.outer_radius = hhw * 1.3
				ring.mesh = tm
				ring.material_override = gl
				ring.position = Vector3(0, htop + hhw * 0.9, hzc)
				_head.add_child(ring)
		"shadow":
			var n2 := 2 + s * 2
			for i in n2:
				var z2: float = zc + (float(i) / float(maxi(n2 - 1, 1)) - 0.5) * ln * 0.8
				var x2: float = (float(i % 2) - 0.5) * hw * 0.9
				var hgt: float = hw * (0.9 + 0.5 * float(s))
				_cone(_torso, hw * 0.3, hgt, Vector3(x2, top + hgt * 0.4, z2), Vector3(-0.2 * float(1 + i % 3), 0, x2 * 0.5), soft)
			if _head != null and s >= 1:
				_blob(_head, Vector3(hhw * 2.2, hhw * 0.25, hhw * 0.5), Vector3(0, hhw * 0.1, hzc + hhw * 0.9), _glow(Color(0.7, 0.4, 1.0)))
		"frost":
			var n3 := 3 + s * 2
			for i in n3:
				var z3: float = zc + (float(i) / float(maxi(n3 - 1, 1)) - 0.5) * ln * 0.85
				var hgt3: float = hw * (0.7 + 0.28 * float(s)) * (1.0 - 0.3 * absf(float(i) / float(maxi(n3 - 1, 1)) - 0.5))
				var sideo: float = (float(i % 2) - 0.5) * hw * 0.5
				_cone(_torso, hw * 0.14, hgt3, Vector3(sideo, top + hgt3 * 0.3, z3), Vector3(0.0, 0, sideo * 1.2), soft)
		"ember":
			for sd in [-1.0, 1.0]:
				for k in (1 + s):
					_blob(_torso, Vector3(0.02, hw * 0.6, ln * 0.16), Vector3(sd * hw * 0.98, (float(k) - 1.0) * hw * 0.35, zc + (float(k) - 1.0) * ln * 0.2), gl, Vector3(0, 0, sd * 0.4))
			if _tail != null:
				_blob(_tail, Vector3.ONE * (0.05 + hw * 0.18), Vector3(0, 0, -ln * 0.35), gl)
				if s >= 2:
					for k in 3:
						_cone(_tail, hw * 0.18, hw * (1.0 + 0.4 * float(s)), Vector3((float(k) - 1.0) * hw * 0.2, hw * 0.5, -ln * 0.35), Vector3(0, 0, (float(k) - 1.0) * 0.3), soft)
		"jade":
			var n4 := 1 + s
			for sd in [-1.0, 1.0]:
				for k in n4:
					_blob(_torso, Vector3(0.02, hw * 0.9, ln * 0.26), Vector3(sd * hw * 0.99, hw * 0.05, zc + (float(k) - float(n4 - 1) * 0.5) * ln * 0.3), gl, Vector3(0, 0, sd * 0.6))
			if s >= 2 and _head != null:
				for sd in [-1.0, 1.0]:
					_blob(_head, Vector3(hhw * 0.25, hhw * 1.4, hhw * 0.6), Vector3(sd * hhw * 0.9, htop * 0.6, hzc - hhw * 0.3), gl, Vector3(0.2, 0, sd * 0.5))
	# a second species: its colour shows as patches on the face, tail and flank
	if mixcol.a > 0.0:
		var pm := _surface(mixcol, false)
		_blob(_torso, Vector3(hw * 0.9, hw * 0.5, ln * 0.3), Vector3(hw * 0.5, top - hw * 0.3, zc - ln * 0.15), pm)
		if _head != null:
			_blob(_head, Vector3(hhw * 1.1, hhw * 0.7, hhw * 0.9), Vector3(0, htop - hhw * 0.1, hzc + hhw * 0.6), pm)
		if _tail != null:
			_blob(_tail, Vector3.ONE * (0.045 + hw * 0.16), Vector3(0, 0, -ln * 0.3), pm)
		if s >= 2:
			_blob(_torso, Vector3(hw * 0.9, hw * 0.5, ln * 0.25), Vector3(-hw * 0.5, -hw * 0.1, zc + ln * 0.2), pm)
	# generations: a pale collar, then a gold one, then a star on the brow
	if gen >= 2 and _head != null:
		var col_c: Color = Color(1.0, 0.82, 0.3) if gen >= 4 else Color(0.92, 0.9, 0.85)
		var cm := _surface(col_c, gen >= 4)
		_blob(_head, Vector3(hhw * 2.5, hhw * 0.7, hhw * 2.5), Vector3(0, -hhw * 0.45, hzc - hhw * 0.9), cm)
	if gen >= 6 and _head != null:
		_blob(_head, Vector3.ONE * hhw * 0.6, Vector3(0, htop - hhw * 0.1, hzc + hhw * 0.55), _glow(Color(1.0, 0.95, 0.6)))


# ---- bodies ---------------------------------------------------------------

func _make(c: Color, n: String) -> void:
	var shiny := plan in ["crab", "lizard", "toad", "worm", "golem"] or n.contains("glass") or n.contains("copper") or n.contains("jewel") or n.contains("steel")
	_mat = _surface(c, shiny)
	_dark = _surface(c.darkened(0.45), shiny)
	_pale = _surface(c.lerp(Color(0.95, 0.92, 0.85), 0.55), false)
	_torso = _pivot(self, Vector3.ZERO)
	match plan:
		"hare":
			_torso.position.y = 0.2
			_blob(_torso, Vector3(0.24, 0.24, 0.36), Vector3(0, 0.02, -0.04), _mat)
			_blob(_torso, Vector3(0.2, 0.18, 0.16), Vector3(0, -0.02, 0.1), _pale)
			_head = _pivot(_torso, Vector3(0, 0.14, 0.2))
			_blob(_head, Vector3(0.15, 0.14, 0.18), Vector3.ZERO, _mat)
			_eyes(_head, Vector3(0, 0.02, 0.06), 0.06, 0.018)
			for sd in [-1.0, 1.0]:
				_blob(_head, Vector3(0.05, 0.22, 0.025), Vector3(sd * 0.035, 0.15, -0.03), _mat, Vector3(-0.25, 0, sd * 0.15))
			_tail = _pivot(_torso, Vector3(0, 0.05, -0.22))
			_blob(_tail, Vector3.ONE * 0.08, Vector3.ZERO, _pale)
			_leg(Vector3(-0.07, -0.02, 0.1), 0.025, 0.018, 0.17, 0.0, 0.5)
			_leg(Vector3(0.07, -0.02, 0.1), 0.025, 0.018, 0.17, 0.0, 0.5)
			_leg(Vector3(-0.09, -0.04, -0.12), 0.05, 0.022, 0.15, PI, 0.7)
			_leg(Vector3(0.09, -0.04, -0.12), 0.05, 0.022, 0.15, PI, 0.7)
		"boar":
			_torso.position.y = 0.24
			_blob(_torso, Vector3(0.34, 0.32, 0.56), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.3, 0.2, 0.3), Vector3(0, 0.1, 0.1), _dark)      # the bristled hump
			_head = _pivot(_torso, Vector3(0, 0.02, 0.3))
			_blob(_head, Vector3(0.22, 0.22, 0.26), Vector3.ZERO, _mat)
			_blob(_head, Vector3(0.11, 0.09, 0.12), Vector3(0, -0.04, 0.13), _dark)   # snout
			_eyes(_head, Vector3(0, 0.05, 0.08), 0.07, 0.014)
			for sd in [-1.0, 1.0]:
				_cone(_head, 0.014, 0.1, Vector3(sd * 0.06, -0.05, 0.14), Vector3(-1.1, 0, sd * -0.3), _surface(Color(0.95, 0.92, 0.82), true))
				_blob(_head, Vector3(0.05, 0.08, 0.03), Vector3(sd * 0.08, 0.11, -0.02), _mat, Vector3(0, 0, sd * 0.4))
			_tail = _pivot(_torso, Vector3(0, 0.06, -0.28))
			_cone(_tail, 0.015, 0.1, Vector3(0, -0.04, -0.02), Vector3(0.6, 0, 0), _mat)
			_leg(Vector3(-0.09, -0.08, 0.16), 0.04, 0.028, 0.14, 0.0, 0.55)
			_leg(Vector3(0.09, -0.08, 0.16), 0.04, 0.028, 0.14, PI, 0.55)
			_leg(Vector3(-0.09, -0.08, -0.16), 0.045, 0.028, 0.14, PI, 0.55)
			_leg(Vector3(0.09, -0.08, -0.16), 0.045, 0.028, 0.14, 0.0, 0.55)
		"stag":
			_torso.position.y = 0.42
			_blob(_torso, Vector3(0.22, 0.24, 0.48), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.16, 0.12, 0.2), Vector3(0, -0.08, 0.05), _pale)
			var neck := _pivot(_torso, Vector3(0, 0.08, 0.2))
			_blob(neck, Vector3(0.11, 0.26, 0.12), Vector3(0, 0.1, 0.03), _mat, Vector3(0.45, 0, 0))
			_head = _pivot(neck, Vector3(0, 0.22, 0.08))
			_blob(_head, Vector3(0.1, 0.1, 0.2), Vector3(0, 0, 0.04), _mat)
			_blob(_head, Vector3(0.06, 0.05, 0.06), Vector3(0, -0.02, 0.13), _dark)
			_eyes(_head, Vector3(0, 0.03, 0.04), 0.05, 0.012)
			var horn_mat := _surface(Color(0.82, 0.74, 0.6), false)
			var antlers := n.contains("stag") or n.contains("deer") or n.contains("elk")
			for sd in [-1.0, 1.0]:
				_blob(_head, Vector3(0.03, 0.07, 0.02), Vector3(sd * 0.055, 0.05, -0.03), _mat, Vector3(0, 0, sd * 0.8))
				if antlers:
					var a := _pivot(_head, Vector3(sd * 0.03, 0.05, 0.0))
					a.rotation = Vector3(-0.3, 0, sd * -0.45)
					_cone(a, 0.012, 0.22, Vector3(0, 0.11, 0), Vector3.ZERO, horn_mat)
					_cone(a, 0.008, 0.1, Vector3(0, 0.1, 0.03), Vector3(0.7, 0, 0), horn_mat)
					_cone(a, 0.008, 0.09, Vector3(sd * 0.03, 0.17, 0.0), Vector3(0, 0, sd * -0.6), horn_mat)
				else:
					_cone(_head, 0.018, 0.14, Vector3(sd * 0.03, 0.08, -0.04), Vector3(-0.7, 0, sd * -0.2), horn_mat)
			_tail = _pivot(_torso, Vector3(0, 0.08, -0.24))
			_blob(_tail, Vector3(0.05, 0.08, 0.04), Vector3(0, -0.02, -0.01), _pale)
			_leg(Vector3(-0.06, -0.08, 0.15), 0.025, 0.014, 0.34, 0.0, 0.5)
			_leg(Vector3(0.06, -0.08, 0.15), 0.025, 0.014, 0.34, PI, 0.5)
			_leg(Vector3(-0.06, -0.08, -0.16), 0.032, 0.014, 0.34, PI, 0.5)
			_leg(Vector3(0.06, -0.08, -0.16), 0.032, 0.014, 0.34, 0.0, 0.5)
		"lizard":
			_torso.position.y = 0.1
			_blob(_torso, Vector3(0.18, 0.1, 0.4), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.14, 0.05, 0.32), Vector3(0, -0.03, 0), _pale)
			_head = _pivot(_torso, Vector3(0, 0.01, 0.22))
			_blob(_head, Vector3(0.12, 0.07, 0.16), Vector3(0, 0, 0.04), _mat)
			_eyes(_head, Vector3(0, 0.025, 0.05), 0.045, 0.013)
			_tail = _pivot(_torso, Vector3(0, 0, -0.19))
			_cone(_tail, 0.045, 0.38, Vector3(0, 0, -0.19), Vector3(-PI / 2, 0, 0), _mat)
			for z in [0.11, -0.11]:
				for sd in [-1.0, 1.0]:
					_leg(Vector3(sd * 0.08, -0.01, z), 0.022, 0.014, 0.1, (0.0 if (z > 0) == (sd > 0) else PI), 0.6, null, sd * 0.9)
		"toad":
			_torso.position.y = 0.11
			_blob(_torso, Vector3(0.3, 0.2, 0.3), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.24, 0.12, 0.22), Vector3(0, -0.05, 0.04), _pale)
			_head = _pivot(_torso, Vector3(0, 0.05, 0.12))
			_blob(_head, Vector3(0.24, 0.1, 0.14), Vector3.ZERO, _mat)
			for sd in [-1.0, 1.0]:
				_blob(_head, Vector3.ONE * 0.06, Vector3(sd * 0.07, 0.05, 0.0), _mat)
			_eyes(_head, Vector3(0, 0.07, 0.02), 0.07, 0.02)
			_leg(Vector3(-0.09, -0.04, 0.08), 0.022, 0.016, 0.07, 0.0, 0.3)
			_leg(Vector3(0.09, -0.04, 0.08), 0.022, 0.016, 0.07, 0.0, 0.3)
			_leg(Vector3(-0.13, -0.02, -0.08), 0.045, 0.02, 0.09, PI, 0.6, null, -0.8)
			_leg(Vector3(0.13, -0.02, -0.08), 0.045, 0.02, 0.09, PI, 0.6, null, 0.8)
		"crab":
			_torso.position.y = 0.12
			var wide := n.contains("crab")
			_blob(_torso, Vector3(0.36 if wide else 0.24, 0.13, 0.26 if wide else 0.34), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.3 if wide else 0.2, 0.06, 0.22 if wide else 0.28), Vector3(0, -0.04, 0), _dark)
			_head = _pivot(_torso, Vector3(0, 0.0, 0.14 if wide else 0.18))
			_blob(_head, Vector3(0.1, 0.07, 0.07), Vector3.ZERO, _dark)
			_eyes(_head, Vector3(0, 0.035, 0.02), 0.035, 0.014)
			for i in 3:
				var z := 0.07 - 0.07 * i
				for sd in [-1.0, 1.0]:
					var lp := _leg(Vector3(sd * (0.14 if wide else 0.1), 0.0, z), 0.016, 0.008, 0.16, (0.0 if (i % 2 == 0) == (sd > 0) else PI), 0.45, _dark, sd * 1.05)
					lp.rotation.y = sd * (0.25 - 0.25 * i)
			if wide or n.contains("scorpion"):
				for sd in [-1.0, 1.0]:
					var cl := _pivot(_torso, Vector3(sd * 0.12, 0.0, 0.16))
					_blob(cl, Vector3(0.08, 0.06, 0.12), Vector3(sd * 0.04, 0.0, 0.07), _mat)
					_blob(cl, Vector3(0.03, 0.03, 0.08), Vector3(sd * 0.06, 0.01, 0.14), _mat)
			if n.contains("beetle") or n.contains("jewel") or n.contains("copper"):
				_blob(_torso, Vector3(0.012, 0.15, 0.3), Vector3(0, 0.0, -0.01), _dark)     # the line between the wing-cases
		"bird":
			_torso.position.y = 0.36 if n.contains("crane") or n.contains("heron") else (0.5 if flies else 0.14)
			var moth := n.contains("moth") or n.contains("butterfly")
			_blob(_torso, Vector3(0.16, 0.16, 0.3) if not moth else Vector3(0.08, 0.08, 0.2), Vector3.ZERO, _mat, Vector3(-0.25, 0, 0))
			_head = _pivot(_torso, Vector3(0, 0.1, 0.15))
			_blob(_head, Vector3.ONE * (0.11 if not moth else 0.07), Vector3.ZERO, _mat)
			_eyes(_head, Vector3(0, 0.015, 0.04), 0.035, 0.012)
			if not moth:
				var beak_len := 0.16 if n.contains("crane") or n.contains("heron") else 0.08
				_cone(_head, 0.022, beak_len, Vector3(0, -0.01, 0.05 + beak_len * 0.5), Vector3(PI / 2, 0, 0), _surface(Color(0.85, 0.72, 0.35) if not n.contains("crow") and not n.contains("raven") else Color(0.15, 0.15, 0.15), true))
				_tail = _pivot(_torso, Vector3(0, 0.02, -0.14))
				_blob(_tail, Vector3(0.12, 0.02, 0.16), Vector3(0, 0, -0.07), _dark, Vector3(-0.2, 0, 0))
			else:
				for sd in [-1.0, 1.0]:
					_cone(_head, 0.004, 0.12, Vector3(sd * 0.025, 0.06, 0.04), Vector3(-0.5, 0, sd * -0.4), _dark)
			for sd in [-1.0, 1.0]:
				var w := _pivot(_torso, Vector3(sd * 0.06, 0.05, 0.0))
				if moth:
					_blob(w, Vector3(0.3, 0.012, 0.22), Vector3(sd * 0.15, 0, 0.03), _pale)
					_blob(w, Vector3(0.2, 0.012, 0.16), Vector3(sd * 0.1, 0, -0.1), _mat)
				else:
					_blob(w, Vector3(0.32, 0.03, 0.17), Vector3(sd * 0.15, 0, -0.03), _dark)
				_wings.append([w, sd])
			if not moth:
				var long := n.contains("crane") or n.contains("heron")
				_leg(Vector3(-0.04, -0.06, 0.0), 0.012, 0.008, 0.3 if long else 0.08, 0.0, 0.5, _surface(Color(0.3, 0.25, 0.2), true))
				_leg(Vector3(0.04, -0.06, 0.0), 0.012, 0.008, 0.3 if long else 0.08, PI, 0.5, _surface(Color(0.3, 0.25, 0.2), true))
		"golem":
			_torso.position.y = 0.36
			_blob(_torso, Vector3(0.34, 0.34, 0.24), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.4, 0.12, 0.28), Vector3(0, 0.18, 0), _dark)               # the shoulders
			_blob(_torso, Vector3(0.1, 0.1, 0.04), Vector3(0, 0.02, 0.12), _glow(c.lightened(0.5), 1.0))    # the spark inside
			_head = _pivot(_torso, Vector3(0, 0.3, 0.02))
			_blob(_head, Vector3(0.16, 0.14, 0.15), Vector3.ZERO, _dark)
			_eyes(_head, Vector3(0, 0.01, 0.07), 0.05, 0.016)
			_leg(Vector3(-0.1, -0.16, 0.0), 0.07, 0.06, 0.2, 0.0, 0.4)
			_leg(Vector3(0.1, -0.16, 0.0), 0.07, 0.06, 0.2, PI, 0.4)
			_leg(Vector3(-0.25, 0.1, 0.0), 0.05, 0.045, 0.24, PI, 0.3)
			_leg(Vector3(0.25, 0.1, 0.0), 0.05, 0.045, 0.24, 0.0, 0.3)
		"worm":
			_torso.position.y = 0.07
			for i in 7:
				var r := 0.14 - absf(i - 2.0) * 0.012
				var seg := _blob(_torso, Vector3(r, r * 0.85, r * 0.9), Vector3(0, 0, 0.18 - i * 0.07), _mat if i % 2 == 0 else _pale)
				_segments.append(seg)
			_head = _pivot(_torso, Vector3(0, 0.02, 0.24))
			_blob(_head, Vector3(0.11, 0.1, 0.09), Vector3.ZERO, _dark)
			_eyes(_head, Vector3(0, 0.02, 0.035), 0.03, 0.01)
		_:  # ferret: a long low furred body (mole, weasel, rat, fox...)
			var big := n.contains("wolf") or n.contains("hound") or n.contains("fox") or n.contains("dog") or n.contains("lynx")
			var hy := 0.26 if big else 0.13
			_torso.position.y = hy
			_blob(_torso, Vector3(0.2, 0.18, 0.46) if big else Vector3(0.17, 0.14, 0.42), Vector3.ZERO, _mat)
			_blob(_torso, Vector3(0.15, 0.1, 0.3), Vector3(0, -0.05, 0.04), _pale)
			_head = _pivot(_torso, Vector3(0, 0.06 if big else 0.02, 0.24))
			_blob(_head, Vector3(0.14, 0.12, 0.16), Vector3.ZERO, _mat)
			_cone(_head, 0.045, 0.1, Vector3(0, -0.015, 0.1), Vector3(PI / 2, 0, 0), _mat)
			_blob(_head, Vector3.ONE * 0.025, Vector3(0, -0.01, 0.15), _dark)          # nose
			_eyes(_head, Vector3(0, 0.03, 0.05), 0.045, 0.013)
			for sd in [-1.0, 1.0]:
				if n.contains("mole"):
					continue
				_cone(_head, 0.03, 0.07, Vector3(sd * 0.045, 0.07, -0.02), Vector3(-0.2, 0, sd * -0.3), _mat)
			_tail = _pivot(_torso, Vector3(0, 0.02, -0.21))
			if n.contains("rat") or n.contains("mouse"):
				_cone(_tail, 0.015, 0.34, Vector3(0, 0, -0.17), Vector3(-PI / 2, 0, 0), _pale)
			else:
				_blob(_tail, Vector3(0.07, 0.07, 0.3 if big else 0.22), Vector3(0, 0.02, -0.12), _mat, Vector3(0.35, 0, 0))
			var ll := (hy - 0.02) if big else 0.11
			_leg(Vector3(-0.06, -0.04, 0.13), 0.028, 0.018, ll, 0.0, 0.6)
			_leg(Vector3(0.06, -0.04, 0.13), 0.028, 0.018, ll, PI, 0.6)
			_leg(Vector3(-0.06, -0.04, -0.13), 0.032, 0.018, ll, PI, 0.6)
			_leg(Vector3(0.06, -0.04, -0.13), 0.032, 0.018, ll, 0.0, 0.6)
	if DisplayServer.get_name() == "headless":
		set_process(false)


# ---- moving ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _dead or _torso == null:
		return
	var p := global_position
	if _have_last and delta > 0.0:
		var v := (p - _last) / delta
		v.y = 0.0
		_speed = lerpf(_speed, minf(v.length(), 12.0) / maxf(scale.x, 0.2), clampf(delta * 8.0, 0.0, 1.0))
	_last = p
	_have_last = true
	var moving := clampf(_speed / 2.0, 0.0, 1.0)
	_t += delta * (2.0 + _speed * 4.0)
	for L in _legs:
		var piv: Node3D = L[0]
		piv.rotation.x = sin(_t + float(L[1])) * float(L[2]) * moving
	var base_y: float = _torso.get_meta("y", _torso.position.y)
	if not _torso.has_meta("y"):
		_torso.set_meta("y", base_y)
	match plan:
		"hare":
			# hops: up and down in arcs while moving, a twitch of the nose standing
			_torso.position.y = base_y + absf(sin(_t)) * 0.08 * moving
			_torso.rotation.x = -cos(_t) * 0.15 * moving
		"bird":
			var flap := 9.0 if flies else (4.0 if moving > 0.2 else 0.0)
			for W in _wings:
				var w: Node3D = W[0]
				w.rotation.z = float(W[1]) * (sin(Time.get_ticks_msec() * 0.001 * flap) * 0.7 if flap > 0.0 else -0.15)
			if flies:
				_torso.position.y = base_y + sin(_t * 0.5) * 0.04
		"worm":
			for i in _segments.size():
				var s: MeshInstance3D = _segments[i]
				s.position.x = sin(_t * 1.5 - i * 0.9) * 0.025 * (0.4 + moving)
				s.position.y = absf(sin(_t * 1.5 - i * 0.9)) * 0.02 * moving
		_:
			_torso.position.y = base_y + absf(sin(_t)) * 0.012 * moving
			_torso.rotation.z = sin(_t) * 0.04 * moving
	if _tail:
		_tail.rotation.y = sin(_t * 0.7) * (0.35 if plan in ["lizard", "ferret"] else 0.15)
	if _head:
		_head.rotation.y = sin(Time.get_ticks_msec() * 0.0007 + float(get_instance_id() % 7)) * 0.2 * (1.0 - moving)


func die() -> void:
	## falls on its side (the bird drops)
	if _dead:
		return
	_dead = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation:z", PI / 2.0 * (1.0 if get_instance_id() % 2 == 0 else -1.0), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if plan == "bird" and flies:
		tw.tween_property(_torso, "position:y", 0.08, 0.4).set_ease(Tween.EASE_IN)
	for W in _wings:
		var w: Node3D = W[0]
		tw.tween_property(w, "rotation:z", float(W[1]) * -0.6, 0.3)
