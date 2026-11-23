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
	## the longest word that matches wins (2026-11-06: "fox" contains "ox", so
	## every fox had been built as a stag)
	var n := name.to_lower()
	var best := "ferret"
	var best_len := 0
	for p in PLANS:
		for w in PLANS[p]:
			if n.contains(str(w)) and str(w).length() > best_len:
				best = p
				best_len = str(w).length()
	return best


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
		e.set_meta("eye", true)          # (the second "Eye" gets renamed by the tree, so the meta is what marks them)


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
		if ch is MeshInstance3D and ch.mesh is SphereMesh and not ch.has_meta("eye") and ch.scale.x > 0.07:
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
	# 2: a ridge of spines swept back along the spine, horns, burning eyes
	var bone := _surface(_mat.albedo_color.lerp(accent, 0.3).lightened(0.25), true)
	for i in 6:
		var z: float = float(t["z0"]) + ln * (0.2 + 0.12 * float(i))
		var h := hw * (0.42 + 0.3 * sin(PI * float(i) / 5.0))
		_cone(_torso, hw * 0.075, h, Vector3(0, top + h * 0.12, z), Vector3(-1.05, 0, 0), bone).name = "Spine"
	if _head != null:
		var h2 := _extent(_head)
		var hhw: float = h2["hw"] if bool(h2["ok"]) else 0.06
		var htop: float = h2["top"] if bool(h2["ok"]) else 0.06
		var hzc: float = h2["zc"] if bool(h2["ok"]) else 0.0
		for sd in [-1.0, 1.0]:
			_cone(_head, hhw * 0.18, hhw * 1.5, Vector3(sd * hhw * 0.45, htop + hhw * 0.1, hzc - hhw * 0.25), Vector3(-1.15, 0, sd * -0.25), bone)
		for ch in _head.get_children():
			if ch is MeshInstance3D and ch.has_meta("eye"):
				var gm := _glow(accent)
				ch.material_override = gm
				ch.scale *= 1.3
	if stage < 3:
		return
	_spirit_form(accent, t)


## 2026-11-06 (Robert: "the final form is kinda childish and bland"): the spirit
## beast was a lit-up toy -- the whole body glowing one flat colour, round spots
## on the flanks, a party-hat ring of cones round the head, three big flat cones
## for a tail. Now: the coat deepens and stays a coat; a cold rim of the form's
## light hangs round the body (a fresnel aura, faint face-on, bright at the
## edges, slowly breathing); thin swept stripes of light on the flanks; a mane
## of fine strands streaming back off the head and neck; a long plume of a tail;
## light pooling under the paws. Phones and Low graphics skip the aura.
var spirit_parts := {}                  # what the spirit form added (tests)
static var _aura_shader: Shader = null


func _aura_mat(c: Color) -> ShaderMaterial:
	if _aura_shader == null:
		_aura_shader = Shader.new()
		_aura_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float power = 2.6;
uniform float strength = 1.6;
void fragment() {
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float pulse = 0.8 + 0.2 * sin(TIME * 1.3);
	ALBEDO = tint.rgb * fr * strength * pulse;
	ALPHA = clamp(fr * pulse, 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _aura_shader
	m.set_shader_parameter("tint", c)
	return m


func _wisp(c: Color, alpha: float) -> StandardMaterial3D:
	## a strand of light: softer than _glow, and lit from within
	var m := _glow(c.lerp(Color(1, 1, 1), 0.25), alpha)
	m.emission_energy_multiplier = 1.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _spirit_form(accent: Color, t: Dictionary) -> void:
	var top: float = t["top"]
	var hw: float = t["hw"]
	var zc: float = t["zc"]
	var ln: float = t["len"]
	var z0: float = t["z0"]
	# the coat deepens (richer, a little darker) -- no flat glow over the body
	for m in ([_mat, _dark, _pale] if plan == "worm" else [_mat, _dark]):
		if m == null:
			continue
		var c: Color = m.albedo_color
		m.albedo_color = Color.from_hsv(c.h, clampf(c.s * 1.12 + 0.04, 0.0, 1.0), c.v * (0.78 if m == _pale else 0.88))
		m.emission_enabled = false
		m.rim_enabled = true
		m.rim = 0.5
		m.rim_tint = 0.3
	var lite := false
	var Gx = load("res://scripts/core/Gfx.gd")
	if Gx != null and Gx.has_method("lite_art"):
		lite = bool(Gx.lite_art())
	lite = lite or OS.has_feature("mobile")
	var aura := _aura_mat(accent)
	var light := _wisp(accent, 0.55)
	var stripe := _glow(accent, 0.9)
	stripe.emission_energy_multiplier = 2.4
	var n_aura := 0
	if plan in ["ferret", "boar", "stag", "hare", "lizard", "toad"]:
		# one smooth body from rump to head: a deep chest, a tucked waist, heavy
		# haunches, a ruff at the neck, the head carried up on it; legs with
		# muscle in them, a brush of a tail -- instead of a bigger copy of the cub
		var body := _beast_body(t)
		spirit_parts["sculpt"] = true
		var hm = _beast_head()
		if hm != null:
			(body["meshes"] as Array).append(hm)
			spirit_parts["head"] = true
		# stripes of light on the flanks, sitting on the coat
		var n_st := 0
		for sd in [-1.0, 1.0]:
			for i in 4:
				var u := 0.3 + 0.1 * float(i)
				var f: Dictionary = body["at"].call(u)
				var p0: Vector3 = f["p"] + f["right"] * sd * float(f["rx"]) * 0.97 + f["up"] * float(f["ry"]) * 0.1
				var st := _blob(_torso, Vector3(0.008, float(f["ry"]) * 1.05, ln * 0.028), p0, stripe, Vector3(0.55, sd * 0.12, 0))
				st.name = "Stripe"
				n_st += 1
		spirit_parts["stripes"] = n_st
		if not lite:
			for mi in body["meshes"]:
				var sh := MeshInstance3D.new()
				sh.mesh = (mi as MeshInstance3D).get_meta("aura_mesh")
				sh.material_override = aura
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sh.name = "Aura"
				(mi as MeshInstance3D).add_child(sh)
				n_aura += 1
		# a few long streamers of light off the ruff, trailing over the shoulders
		var n_mane := 0
		var fr: Dictionary = body["at"].call(0.86)
		if plan == "lizard":
			fr = {}
		var soft := _wisp(accent, 0.35)
		for i in (0 if fr.is_empty() else 5):
			var a := lerpf(-1.1, 1.1, float(i) / 4.0)
			var base: Vector3 = fr["p"] + fr["right"] * sin(a) * float(fr["rx"]) * 0.9 + fr["up"] * cos(a) * float(fr["ry"]) * 0.9
			var L := hw * (1.5 + 0.5 * cos(a))
			var dir := (Vector3(sin(a) * 0.5, 0.35, -1.0)).normalized()
			var rot := _rot_to(dir)
			_cone(_torso, hw * 0.1, L, base + dir * L * 0.5, rot, soft)
			n_mane += 1
		spirit_parts["mane"] = n_mane
	else:
		# the rest (lizard, toad, crab, bird, worm, golem): marks of light and an aura on the body blobs
		var n_st2 := 0
		for sd in [-1.0, 1.0]:
			for i in 3:
				var zz: float = z0 + ln * (0.32 + 0.14 * float(i))
				_blob(_torso, Vector3(0.01, hw * 0.6, ln * 0.03), Vector3(sd * hw * 0.96, hw * 0.08, zz), stripe, Vector3(0.6, 0, 0)).name = "Stripe"
				n_st2 += 1
		spirit_parts["stripes"] = n_st2
		spirit_parts["mane"] = 0
		if plan == "bird":
			spirit_parts["feathers"] = _feather_wings(accent)
		elif plan == "crab":
			spirit_parts["carapace"] = _spirit_carapace(accent, t)
		elif plan == "worm":
			spirit_parts["rings"] = _spirit_rings(accent)
		elif plan == "golem":
			spirit_parts["veins"] = _spirit_veins(accent, t)
		if not lite:
			for ch in _torso.get_children():
				if ch is MeshInstance3D and ch.mesh is SphereMesh and ch.material_override == _mat and ch.scale.x > 0.07:
					var sh2 := MeshInstance3D.new()
					sh2.mesh = ch.mesh
					sh2.material_override = aura
					sh2.scale = Vector3.ONE * 1.08
					sh2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					sh2.name = "Aura"
					ch.add_child(sh2)
					n_aura += 1
	# a plume of light off the tail tip
	var n_tail := 0
	if _tail != null:
		var tip: Vector3 = _tail.get_meta("tip", Vector3(0, 0.02, -ln * 0.45))
		var tl := _wisp(accent, 0.4)
		for i in 3:
			var sp := (float(i) - 1.0) * 0.35
			var L3 := ln * (0.26 + 0.08 * (1.0 - absf(float(i) - 1.0)))
			var dir3 := Vector3(sin(sp) * 0.6, 0.25, -1.0).normalized()
			_cone(_tail, hw * 0.13, L3, tip + dir3 * L3 * 0.45, _rot_to(dir3), tl)
			n_tail += 1
	spirit_parts["tail"] = n_tail
	spirit_parts["aura"] = n_aura
	# light pooling on the ground under it
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 5.0, ln * 1.6)
	pool.mesh = pm
	var pool_m := StandardMaterial3D.new()
	pool_m.albedo_color = Color(accent.r, accent.g, accent.b, 0.22)
	pool_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_m.albedo_texture = _soft_dot()
	pool.material_override = pool_m
	pool.position = Vector3(0, 0.012, zc)
	pool.name = "SpiritPool"
	add_child(pool)
	spirit_parts["pool"] = true


func _feather_wings(accent: Color) -> int:
	## a bird's wings become fans of long flight feathers (on the wing pivots, so
	## they still beat) with a sheen of light; the tail a fan of long feathers
	var n := 0
	var fm := _surface(_dark.albedo_color if _dark else _mat.albedo_color, false)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.emission_enabled = true                # a sheen of the form's light in the feathers
	fm.emission = accent
	fm.emission_energy_multiplier = 0.22
	for W in _wings:
		var w: Node3D = W[0]
		var sd: float = W[1]
		var moth := false
		for ch in w.get_children():
			if ch is MeshInstance3D:
				if ch.material_override == _pale:
					moth = true
		if moth:
			continue
		for ch in w.get_children():
			if ch is MeshInstance3D:
				ch.visible = false
		for i in 7:
			var k := float(i) / 6.0
			var a := lerpf(0.12, 1.3, k)
			var d := Vector3(sd * cos(a), 0.04, -sin(a)).normalized()
			var L := 0.4 * (1.0 - 0.32 * k)
			var fb := _blob(w, Vector3.ONE, d * L * 0.5 + Vector3(0, 0.004 * i, 0), fm)
			fb.basis = Basis.looking_at(-d, Vector3.UP).scaled(Vector3(0.07, 0.012, L))
			n += 1
		var cv := _blob(w, Vector3.ONE, Vector3(sd * 0.09, 0.012, -0.03), _mat)
		cv.basis = Basis.looking_at(Vector3(-sd * 0.5, 0, 1).normalized(), Vector3.UP).scaled(Vector3(0.11, 0.035, 0.2))
	if _tail != null:
		for ch in _tail.get_children():
			if ch is MeshInstance3D:
				ch.visible = false
		for i in 5:
			var sp := (float(i) - 2.0) * 0.2
			var d2 := Vector3(sin(sp), -0.12, -1.0).normalized()
			var L2 := 0.3 * (1.0 - 0.12 * absf(float(i) - 2.0))
			var tf := _blob(_tail, Vector3.ONE, d2 * L2 * 0.5, fm)
			tf.basis = Basis.looking_at(-d2, Vector3.UP).scaled(Vector3(0.055, 0.012, L2))
			n += 1
		_tail.set_meta("tip", Vector3(0, -0.03, -0.3))
	return n


const HEAD_SHAPE := {
	# muzzle length (x head radius), muzzle thickness (x cranium), how far the muzzle drops, flatness
	"ferret": [1.35, 0.42, 0.25, 1.0],
	"boar": [0.85, 0.62, 0.2, 1.0],
	"stag": [1.5, 0.42, 0.2, 1.0],
	"hare": [0.55, 0.62, 0.15, 1.0],
	"lizard": [1.15, 0.5, 0.0, 0.62],
	"toad": [0.45, 0.75, 0.0, 0.55],
}


func _beast_head() -> MeshInstance3D:
	## the spirit beast's head: one smooth skull -- a rounded cranium, a stop, a
	## muzzle with a nose at the end, darker on top and pale under the jaw -- in
	## place of a ball with a cone stuck on. Eyes move onto it; ears, horns and
	## antlers stay where they grew.
	if _head == null or not HEAD_SHAPE.has(plan):
		return null
	var main: MeshInstance3D = null
	for ch in _head.get_children():
		if ch is MeshInstance3D and ch.mesh is SphereMesh and not ch.has_meta("eye") and (ch.material_override == _mat or ch.material_override == _dark) and ch.scale.x >= 0.07:
			if main == null or ch.scale.x * ch.scale.z > main.scale.x * main.scale.z:
				main = ch
	if main == null:
		return null
	var C: Vector3 = main.position
	var hr: float = main.scale.x * 0.5
	var hh: float = main.scale.y * 0.5
	var hl: float = main.scale.z * 0.5
	var shape: Array = HEAD_SHAPE[plan]
	var mlen: float = float(shape[0]) * hr
	var mth: float = float(shape[1])
	var drop: float = float(shape[2]) * hh
	var flat: float = float(shape[3])
	# hide the old skull, snout and nose (not the eyes, ears, horns)
	for ch in _head.get_children():
		if not (ch is MeshInstance3D) or ch.has_meta("eye"):
			continue
		var mi: MeshInstance3D = ch
		var mine: bool = mi.material_override == _mat or mi.material_override == _dark or mi.material_override == _pale
		if not mine:
			continue
		if mi.mesh is SphereMesh and (mi.scale.x >= 0.07 or mi.position.z > C.z + hl * 0.5):
			mi.visible = false
		elif mi.mesh is CylinderMesh and absf(absf(mi.rotation.x) - PI / 2.0) < 0.3 and mi.position.z > C.z:
			mi.visible = false
	var path := []
	var rxs := []
	var rys := []
	var N := 16
	var z_back := C.z - hl * 0.95
	var z_front := C.z + hl * 0.55 + mlen
	var z_tip := 0.0
	for i in N:
		var u := float(i) / float(N - 1)
		var z := lerpf(z_back, z_front, u)
		var m := smoothstep(0.38, 0.62, u)                  # cranium -> muzzle
		var back := sqrt(clampf(1.0 - pow((0.12 - minf(u, 0.12)) / 0.12, 2.0), 0.05, 1.0))
		var front := sqrt(clampf(1.0 - pow((maxf(u, 0.86) - 0.86) / 0.14, 2.0), 0.25, 1.0))
		var brow := exp(-pow((u - 0.36) / 0.08, 2.0)) * 0.06
		var rx := hr * lerpf(1.0, mth, m) * back * front
		var ry := hh * lerpf(1.0 + brow, mth * 0.95, m) * back * front * flat
		path.append(Vector3(0, C.y - drop * m + hh * 0.05 * (1.0 - m), z))
		rxs.append(maxf(rx, hr * 0.06))
		rys.append(maxf(ry, hr * 0.06))
		z_tip = z
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color.WHITE
	coat.vertex_color_use_as_albedo = true
	coat.roughness = _mat.roughness
	coat.rim_enabled = true
	coat.rim = 0.5
	coat.rim_tint = 0.3
	var mesh := MeshInstance3D.new()
	mesh.mesh = _loft(_head, path, rxs, rys, true, true)
	mesh.material_override = coat
	mesh.name = "SpiritHead"
	mesh.set_meta("aura_mesh", _loft(_head, path, rxs, rys, true, true, hr * 0.12))
	_head.add_child(mesh)
	# a nose at the end of the muzzle, a line of mouth under it
	var nose_mat := _surface(Color(0.08, 0.07, 0.07), true)
	var tip_r: float = rxs[N - 2]
	_blob(_head, Vector3(tip_r * 1.5, rys[N - 2] * 1.1, tip_r * 0.9), Vector3(0, path[N - 2].y + rys[N - 2] * 0.35, z_tip - tip_r * 0.15), nose_mat).name = "Nose"
	var mouth := _blob(_head, Vector3(tip_r * 2.3, hr * 0.03, mlen * 0.75), Vector3(0, path[N - 1].y - rys[N - 3] * 0.45, z_front - mlen * 0.45), nose_mat)
	mouth.name = "Mouth"
	# eyes sit on the front of the cranium, set apart, almond-shaped
	var ue := 0.42
	var ie := int(round(ue * float(N - 1)))
	for ch in _head.get_children():
		if ch is MeshInstance3D and ch.has_meta("eye"):
			var sd := 1.0 if (ch as MeshInstance3D).position.x >= 0.0 else -1.0
			var e: MeshInstance3D = ch
			var r0: float = e.scale.x
			e.position = Vector3(sd * float(rxs[ie]) * 0.8, path[ie].y + float(rys[ie]) * 0.38, (path[ie] as Vector3).z + hr * 0.1)
			e.scale = Vector3(r0 * 1.15, r0 * 0.75, r0 * 1.0)
			e.rotation = Vector3(0, sd * 0.55, sd * -0.25)
			# a slit of a pupil in the burning eye
			var pu := _blob(e, Vector3(0.22, 0.85, 0.3), Vector3(0, 0, 0.36), nose_mat)
			pu.name = "Pupil"
	return mesh


func _spirit_carapace(accent: Color, t: Dictionary) -> int:
	## crabs, beetles, spiders: a domed carapace with ridges of light and a rim of spines
	var hw: float = t["hw"]
	var ln: float = t["len"]
	var zc: float = t["zc"]
	var top: float = t["top"]
	var shell := _surface(_mat.albedo_color.darkened(0.2), true)
	shell.metallic = 0.35
	shell.roughness = 0.25
	var dome := _blob(_torso, Vector3(hw * 2.15, hw * 0.75, ln * 1.05), Vector3(0, top - hw * 0.28, zc), shell)
	dome.name = "Carapace"
	var seam := _glow(accent, 0.9)
	var n := 1
	for i in 3:
		var a := (float(i) - 1.0) * 0.5
		var arc := _blob(_torso, Vector3(0.012, hw * 0.5, ln * 0.85), Vector3(sin(a) * hw * 0.55, top - hw * 0.02 - absf(a) * hw * 0.12, zc), seam, Vector3(0, 0, -a * 0.9))
		arc.name = "Seam"
		n += 1
	var spike := _surface(accent.lerp(_mat.albedo_color, 0.5), true)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var d := Vector3(sin(ang), 0.25, cos(ang)).normalized()
		_cone(_torso, hw * 0.1, hw * 0.55, Vector3(sin(ang) * hw * 1.02, top - hw * 0.45, zc + cos(ang) * ln * 0.5) + d * hw * 0.2, _rot_to(d), spike)
		n += 1
	return n


func _spirit_rings(accent: Color) -> int:
	## worms and eels: bands of light between the segments, a crest of light at the head
	var n := 0
	var ring := _glow(accent, 0.85)
	for i in _segments.size():
		var seg: MeshInstance3D = _segments[i]
		var tr := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.47
		tm.outer_radius = 0.53
		tr.mesh = tm
		tr.material_override = ring
		tr.rotation = Vector3(PI / 2.0, 0, 0)
		tr.position = Vector3(0, 0, -0.38)
		tr.scale = Vector3(1.0, 0.5, 1.0)
		tr.name = "Band"
		seg.add_child(tr)
		n += 1
	if _head != null:
		var wl := _wisp(accent, 0.5)
		for i in 3:
			var a := (float(i) - 1.0) * 0.45
			var d := Vector3(sin(a) * 0.6, 1.0, -0.5).normalized()
			_cone(_head, 0.012, 0.12, Vector3(0, 0.04, -0.01) + d * 0.06, _rot_to(d), wl)
			n += 1
	return n


func _spirit_veins(accent: Color, t: Dictionary) -> int:
	## golems and constructs: cracks of light running through the stone, and
	## stones of its own body hanging in the air round its shoulders
	var hw: float = t["hw"]
	var top: float = t["top"]
	var vein := _glow(accent, 0.95)
	vein.emission_energy_multiplier = 3.0
	var n := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7177
	var hosts := []
	for ch in _torso.get_children():
		if ch is MeshInstance3D and ch.mesh is SphereMesh and (ch.material_override == _mat or ch.material_override == _dark) and ch.scale.x > 0.07:
			hosts.append(ch)
	for i in 12:
		if hosts.is_empty():
			break
		var host: MeshInstance3D = hosts[i % hosts.size()]
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.8), rng.randf_range(-1.0, 1.0)).normalized()
		var v := _blob(host, Vector3(0.025, rng.randf_range(0.2, 0.42), 0.025), dir * 0.5, vein, Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-1.2, 1.2)))
		v.name = "Vein"
		n += 1
	var stone := _surface(_dark.albedo_color if _dark else _mat.albedo_color.darkened(0.3), false)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var r := hw * 1.7
		var st := _blob(_torso, Vector3(0.07, 0.05, 0.06) * (1.0 + 0.2 * float(i % 2)), Vector3(cos(a) * r, top + hw * 0.25 + 0.03 * float(i % 2), sin(a) * r * 0.7), stone, Vector3(0.3 * i, 0.7 * i, 0.2))
		st.name = "Orbit"
		_blob(st, Vector3(0.25, 0.25, 0.25), Vector3(0, 0, 0.5), vein)
		n += 1
	return n


static func _rot_to(dir: Vector3) -> Vector3:
	## the euler rotation that points a cone's +Y along dir
	var d := dir.normalized()
	var axis := Vector3.UP.cross(d)
	if axis.length() < 0.0001:
		return Vector3.ZERO if d.y > 0.0 else Vector3(PI, 0, 0)
	return Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(d), -1.0, 1.0))).get_euler()


func _coat_colors() -> Array:
	## [coat, back, belly] for the lofted body's vertex colours
	var c: Color = _mat.albedo_color
	var back: Color = _dark.albedo_color if _dark else c.darkened(0.4)
	var belly: Color = _pale.albedo_color if _pale else c.lightened(0.4)
	return [c, back, belly]


func _loft(parent: Node3D, path: Array, rx: Array, ry: Array, close_start: bool, close_end: bool, grow := 0.0, two_tone := true) -> ArrayMesh:
	## a smooth tube along path (points in parent space) with an elliptical
	## section rx x ry at each point; coloured coat / darker back / paler belly.
	## grow > 0 inflates it (the aura shell).
	var cols := _coat_colors()
	var segs := 20
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var frames := []
	for i in n:
		var tng: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var right := Vector3.UP.cross(tng)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := tng.cross(right).normalized()
		frames.append([right, up])
	for i in n:
		var right: Vector3 = frames[i][0]
		var up: Vector3 = frames[i][1]
		for j in segs + 1:
			var th := TAU * float(j) / float(segs)
			var sy := sin(th)
			var v: Vector3 = path[i] + right * cos(th) * (float(rx[i]) + grow) + up * sy * (float(ry[i]) + grow)
			var col: Color = cols[0]
			if not two_tone:
				pass
			elif sy > 0.3:
				col = (cols[0] as Color).lerp(cols[1], clampf((sy - 0.3) / 0.6, 0.0, 1.0) * 0.85)
			elif sy < -0.25:
				col = (cols[0] as Color).lerp(cols[2], clampf((-sy - 0.25) / 0.6, 0.0, 1.0))
			st.set_color(col)
			st.set_uv(Vector2(float(j) / float(segs), float(i) / float(n - 1)))
			st.add_vertex(v)
	for i in n - 1:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + segs + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	var base_count := n * (segs + 1)
	var caps := 0
	for end in [0, n - 1]:
		if (end == 0 and not close_start) or (end == n - 1 and not close_end):
			continue
		var tng2: Vector3 = (path[mini(end + 1, n - 1)] - path[maxi(end - 1, 0)]).normalized() * (-1.0 if end == 0 else 1.0)
		st.set_color(cols[0])
		st.set_uv(Vector2(0.5, 0.0 if end == 0 else 1.0))
		st.add_vertex(path[end] + tng2 * minf(float(rx[end]), float(ry[end])) * 0.6)
		var ci := base_count + caps
		caps += 1
		for j in segs:
			var r0: int = int(end) * (segs + 1) + j
			if end == 0:
				st.add_index(ci)
				st.add_index(r0)
				st.add_index(r0 + 1)
			else:
				st.add_index(ci)
				st.add_index(r0 + 1)
				st.add_index(r0)
	st.generate_normals()
	return st.commit()


func _beast_body(t: Dictionary) -> Dictionary:
	## the spirit beast's lofted body (and legs and tail); the old blobs stay
	## (hidden) so _extent, role bodies and barding still fit to them
	var hw: float = t["hw"]
	var ln: float = t["len"]
	var z0: float = t["z0"]
	var top: float = t["top"]
	var heavy := plan == "boar"
	var tall := plan == "stag"
	var low := plan == "lizard" or plan == "toad"     # long and low: no neck, no ruff (a lizard: a long tapering tail)
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color.WHITE
	coat.vertex_color_use_as_albedo = true
	coat.roughness = _mat.roughness
	coat.rim_enabled = true
	coat.rim = 0.5
	coat.rim_tint = 0.3
	if DisplayServer.get_name() != "headless":
		coat.normal_enabled = true
		coat.normal_texture = _grain()
		coat.normal_scale = 0.5
		coat.uv1_triplanar = true
		coat.uv1_scale = Vector3.ONE * 6.0
	# hide the cub's body blobs (kept for measuring), and the fierce spines (the ruff takes their place)
	for ch in _torso.get_children():
		if ch is MeshInstance3D and str(ch.name).begins_with("Spine") and not low:
			ch.visible = false
		if ch is MeshInstance3D and ch.mesh is SphereMesh and not ch.has_meta("eye") and (ch.material_override == _mat or ch.material_override == _pale or ch.material_override == _dark):
			ch.visible = false
	var H := hw * (1.05 if heavy else (0.62 if low else 0.95))       # half-height of the body at its fullest
	var W := hw * (1.05 if heavy else (0.95 if low else 0.9))
	var cy := -hw * 0.05
	# head: carried up on a neck (the stag already has one)
	var head_at: Vector3 = Vector3(0, top + hw * 0.5, z0 + ln * 1.05)
	if _head != null:
		if low:
			head_at = _head.position + Vector3(0, 0, -hw * 0.3)
		elif _head.get_parent() == _torso and not tall:
			_head.position = _head.position + Vector3(0, hw * (0.45 if heavy else 0.85), hw * 0.45)
			head_at = _head.position + Vector3(0, -hw * 0.1, -hw * 0.2)
		elif tall:
			head_at = Vector3(0, top + hw * 0.4, z0 + ln * 0.95)
	var path := []
	var rxs := []
	var rys := []
	var N := 30
	var p_sh := Vector3(0, cy + hw * 0.1, z0 + ln * 0.8)
	for i in N:
		var u := float(i) / float(N - 1)
		var p: Vector3
		if u <= 0.8:
			var k := u / 0.8
			p = Vector3(0, cy + sin(k * PI) * hw * 0.12 - k * hw * 0.05, lerpf(z0 + ln * 0.02, z0 + ln * 0.8, k))
		else:
			var k2 := (u - 0.8) / 0.2
			var ctrl := Vector3(0, p_sh.y + hw * 0.2, p_sh.z + ln * 0.14)
			p = p_sh.lerp(ctrl, k2).lerp(ctrl.lerp(head_at, k2), k2)
		# the section: rounded rump, haunch, tucked waist, deep chest, ruff, neck
		var rump := sqrt(clampf(1.0 - pow((0.1 - minf(u, 0.1)) / 0.1, 2.0), 0.02, 1.0))
		var haunch := exp(-pow((u - 0.2) / 0.11, 2.0))
		var waist := exp(-pow((u - 0.47) / 0.12, 2.0))
		var chest := exp(-pow((u - 0.72) / 0.1, 2.0))
		var ruff := exp(-pow((u - 0.86) / 0.06, 2.0))
		var neck := smoothstep(0.82, 1.0, u)
		if low:
			chest *= 0.3
			ruff = 0.0
			waist *= 0.4
		var ry := H * (0.88 + 0.12 * haunch - 0.2 * waist + 0.28 * chest + 0.2 * ruff - 0.45 * neck) * rump
		var rx := W * (0.88 + 0.16 * haunch - 0.22 * waist + 0.14 * chest + 0.3 * ruff - 0.42 * neck) * rump
		# the chest hangs deeper than the back rises
		p.y -= H * 0.22 * chest
		path.append(p)
		rxs.append(maxf(rx, hw * 0.12))
		rys.append(maxf(ry, hw * 0.12))
	var back := -9.0
	for i in N:
		var u2 := float(i) / float(N - 1)
		if u2 >= 0.12 and u2 <= 0.72:
			back = maxf(back, (path[i] as Vector3).y + float(rys[i]))
	_torso.set_meta("back_y", back)
	var meshes := []
	var bm := MeshInstance3D.new()
	bm.mesh = _loft(_torso, path, rxs, rys, true, true)
	bm.material_override = coat
	bm.name = "SpiritBody"
	bm.set_meta("aura_mesh", _loft(_torso, path, rxs, rys, true, true, hw * 0.1))
	_torso.add_child(bm)
	meshes.append(bm)
	# legs: a lofted leg in each pivot -- a thick thigh tapering to the ankle, a broad paw
	for L in _legs:
		var piv: Node3D = L[0]
		var limb: MeshInstance3D = null
		var foot: MeshInstance3D = null
		for ch in piv.get_children():
			if ch is MeshInstance3D and ch.mesh is CylinderMesh and limb == null:
				limb = ch
			elif ch is MeshInstance3D and ch.mesh is SphereMesh and foot == null:
				foot = ch
		if limb == null:
			continue
		var cm: CylinderMesh = limb.mesh
		var leng: float = cm.height
		var hind := piv.position.z < 0.0
		var lp := []
		var lrx := []
		var lry := []
		for i in 9:
			var u := float(i) / 8.0
			# hind legs bend back at the hock, fore legs fall straight
			var zoff := (sin(u * PI) * -0.12 * leng) if hind else (u * 0.03 * leng)
			lp.append(Vector3(0, H * 0.2 - u * (leng + H * 0.2), zoff))
			var thigh := 1.0 - smoothstep(0.0, 0.55, u)
			var r := lerpf(cm.bottom_radius * 1.3, minf(cm.top_radius * 2.3, H * 0.55), thigh)
			lrx.append(r * 0.85)
			lry.append(r * 1.1)
		var lm := MeshInstance3D.new()
		lm.mesh = _loft(piv, lp, lrx, lry, true, true, 0.0, false)
		lm.material_override = coat
		lm.name = "SpiritLeg"
		piv.add_child(lm)
		limb.visible = false
		if foot:
			foot.scale = Vector3(1.9, 1.0, 2.4)
			foot.position = Vector3(0, -leng + cm.bottom_radius * 0.7, cm.bottom_radius * 1.2)
			foot.material_override = _dark
	# the tail: a full brush, rising then falling, pointed at the tip
	if _tail != null and not tall:
		for ch in _tail.get_children():
			if ch is MeshInstance3D:
				ch.visible = false
		var tp := []
		var trx := []
		var tr_y := []
		var TL := ln * (1.1 if low else (0.75 if not heavy else 0.4))
		for i in 12:
			var u := float(i) / 11.0
			if low:
				tp.append(Vector3(sin(u * PI) * TL * 0.06, -u * TL * 0.06, -u * TL))
			else:
				tp.append(Vector3(0, sin(u * PI * 0.9) * TL * 0.25 - u * TL * 0.12, -u * TL))
			var r := (hw * 0.6 * pow(1.0 - u, 1.1)) if low else hw * (0.28 + 0.42 * sin(minf(u * 1.15, 1.0) * PI)) * (1.0 - 0.75 * u * u)
			trx.append(maxf(r, hw * 0.03))
			tr_y.append(maxf(r * 1.1, hw * 0.03))
		var tm := MeshInstance3D.new()
		tm.mesh = _loft(_tail, tp, trx, tr_y, true, true)
		tm.material_override = coat
		tm.name = "SpiritTail"
		tm.set_meta("aura_mesh", _loft(_tail, tp, trx, tr_y, true, true, hw * 0.08))
		_tail.add_child(tm)
		meshes.append(tm)
		_tail.set_meta("tip", tp[tp.size() - 1])
	var at := func(u: float) -> Dictionary:
		var idx := clampi(int(round(u * float(N - 1))), 1, N - 2)
		var tng: Vector3 = (path[idx + 1] - path[idx - 1]).normalized()
		var right := Vector3.UP.cross(tng).normalized()
		return {"p": path[idx], "rx": rxs[idx], "ry": rys[idx], "right": right, "up": tng.cross(right).normalized()}
	return {"meshes": meshes, "at": at}


static var _dot_tex: Texture2D = null


static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_dot_tex = gt
	return _dot_tex


## 2026-11-06 (Robert's note 2026-10-31, items 1 and 3: "a real change of body at
## fierce and spirit beast ... each role its own awakened look"): on top of what
## every beast gains (evolve), the role's own body -- wings for the messengers, a
## shell for the guards, great horns for the fighters, more tails for the
## trackers, crystal for the diggers, flame for the fire-born, light-antlers and
## a halo for the seers, a crest for the hunters-at-range. Fierce grows it;
## spirit beast makes it bigger and lights it in the form's colour.
const ROLE_BODY := {
	"courier": "wings", "lucky": "wings", "scholar": "wings",
	"guardian": "shell", "warden": "shell", "sentinel": "shell",
	"striker": "horns", "fury": "horns", "hunter": "horns",
	"tracker": "tails", "forager": "tails", "charmer": "tails",
	"digger": "crystal", "hoarder": "crystal",
	"ember": "flame", "brewer": "flame",
	"lantern": "antlers", "mystic": "antlers", "healer": "antlers",
	"marksman": "crest",
}
var role_body_kind := ""                 # what was added (tests)


func role_form(role: String, stage: int, accent: Color) -> String:
	if stage < 2 or _torso == null or not ROLE_BODY.has(role):
		return ""
	var t := _extent(_torso)
	if not bool(t["ok"]):
		return ""
	var kind: String = ROLE_BODY[role]
	if (plan == "golem" and kind in ["shell", "wings", "tails"]) or (plan == "worm" and kind in ["shell", "wings", "tails", "horns"]):
		return ""              # a stone body or a worm doesn't grow those; its spirit form says the rest
	var top: float = float(_torso.get_meta("back_y", t["top"]))      # the spirit beast's lofted back, when it has one
	var hw: float = t["hw"]
	var zc: float = t["zc"]
	var ln: float = t["len"]
	var z0: float = t["z0"]
	var big := 1.0 if stage < 3 else 1.45
	var lit := stage >= 3
	var body := _surface(_mat.albedo_color.lerp(accent, 0.2), false)
	var bone := _surface(_mat.albedo_color.lerp(accent, 0.3).lightened(0.3), true)
	var glow := _glow(accent, 0.8)
	# 2026-11-06: lit horns, antlers and crests are bone that burns from within (shaded), not flat cut-outs of light
	var litbone := _surface(accent.lerp(Color(1, 1, 1), 0.4), true)
	litbone.emission_enabled = true
	litbone.emission = accent
	litbone.emission_energy_multiplier = 0.9
	var h := _extent(_head) if _head != null else {"ok": false}
	var hhw: float = h["hw"] if bool(h["ok"]) else hw * 0.6
	var htop: float = h["top"] if bool(h["ok"]) else top
	var hzc: float = h["zc"] if bool(h["ok"]) else zc
	match kind:
		"wings":
			# two feathered wings off the shoulders, half-spread and swept back:
			# a fan of long flight feathers over shorter coverts, the edges lit at spirit beast
			var feathers := 5 if stage < 3 else 7
			var fm := _surface(_mat.albedo_color.lerp(accent, 0.15).darkened(0.1), false)
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			if lit:
				fm.emission_enabled = true          # a sheen of the form's light in the feathers
				fm.emission = accent
				fm.emission_energy_multiplier = 0.25
			for sd in ([] if plan == "bird" else [-1.0, 1.0]):           # a bird has its own (Beast._feather_wings)
				var root := Vector3(sd * hw * 0.7, top + hw * 0.05, zc + ln * 0.2)
				var span := hw * 2.2 * big
				for i in feathers:
					var k := float(i) / float(feathers - 1)
					var a := lerpf(0.25, 1.35, k)                     # from straight out to swept right back
					var d := Vector3(sd * cos(a), 0.32 - 0.12 * k, -sin(a)).normalized()
					var L := span * (1.0 - 0.28 * k)
					var w := hw * 0.34
					var fb := _blob(_torso, Vector3.ONE, root + d * L * 0.5, fm)
					fb.basis = Basis.looking_at(-d, Vector3.UP).scaled(Vector3(w, hw * 0.035, L))
				# the coverts: a rounded shoulder of the wing
				var cv := Vector3(sd * cos(0.7), 0.25, -sin(0.7)).normalized()
				var cb := _blob(_torso, Vector3.ONE, root + cv * span * 0.25, body)
				cb.basis = Basis.looking_at(-cv, Vector3.UP).scaled(Vector3(hw * 0.9, hw * 0.12, span * 0.55))
		"shell":
			# overlapping plates laid along the back like scales, a guard over the neck
			var plate := _surface(_mat.albedo_color.darkened(0.35).lerp(accent, 0.12), true)
			var pl := 5
			for i in pl:
				var zz: float = z0 + ln * (0.16 + 0.17 * float(i))
				var wv := hw * (1.75 + 0.25 * sin(PI * float(i) / float(pl - 1))) * minf(big, 1.2)
				_blob(_torso, Vector3(wv, hw * 0.24, ln * 0.25), Vector3(0, top - hw * 0.12, zz), plate, Vector3(-0.3, 0, 0))
				if lit:
					_blob(_torso, Vector3(wv * 0.92, 0.01, ln * 0.025), Vector3(0, top + hw * 0.02, zz + ln * 0.1), glow, Vector3(-0.28, 0, 0))
			_blob(_torso, Vector3(hw * 1.7 * minf(big, 1.2), hw * 0.28, ln * 0.14), Vector3(0, top - hw * 0.06, z0 + ln * 0.95), plate, Vector3(-0.4, 0, 0))
		"horns":
			# great curving horns and tusks
			if _head != null:
				for sd in [-1.0, 1.0]:
					_cone(_head, hhw * 0.32 * big, hhw * 2.6 * big, Vector3(sd * hhw * 0.6, htop + hhw * 0.35, hzc - hhw * 0.1), Vector3(-1.05, 0, sd * -0.75), litbone if lit else bone)
					_cone(_head, hhw * 0.16, hhw * 1.1 * big, Vector3(sd * hhw * 0.45, htop - hhw * 1.1, hzc + hhw * 0.8), Vector3(0.9, 0, sd * 0.25), bone)
			for sd2 in [-1.0, 1.0]:
				_cone(_torso, hw * 0.15, hw * 0.9 * big, Vector3(sd2 * hw * 0.85, top - hw * 0.1, z0 + ln * 0.82), Vector3(-0.2, 0, sd2 * -0.9), bone)
		"tails":
			# more tails, fanned out behind
			var n := 2 if stage < 3 else 4
			var tlen := ln * 0.5 * big
			for i3 in n:
				var a := (float(i3) - float(n - 1) / 2.0) * 0.32
				var c := Vector3(sin(a) * tlen * 0.5, top - hw * 0.25 + tlen * 0.18, z0 - tlen * 0.42)
				_blob(_torso, Vector3(hw * 0.32, hw * 0.32, tlen), c, body, Vector3(-0.35, a, 0))
				if lit:
					var tip: Vector3 = c + Basis.from_euler(Vector3(-0.35, a, 0)) * Vector3(0, 0, -tlen * 0.45)
					_blob(_torso, Vector3(hw * 0.26, hw * 0.26, tlen * 0.24), tip, glow, Vector3(-0.35, a, 0))
		"crystal":
			# shards grown out of the shoulders and spine
			var cm := _glow(accent, 0.85) if lit else _surface(accent.lerp(Color(0.85, 0.9, 1.0), 0.5), true)
			for i4 in (5 if stage < 3 else 9):
				var zz2: float = z0 + ln * (0.15 + 0.08 * float(i4))
				var sd3 := -1.0 if i4 % 2 == 0 else 1.0
				_cone(_torso, hw * 0.16, hw * (0.6 + 0.12 * float(i4 % 3)) * big, Vector3(sd3 * hw * 0.45, top + hw * 0.1, zz2), Vector3(-0.25, 0, sd3 * -0.45), cm)
		"flame":
			# tongues of flame along the back, a burning tail tip
			var fl := _glow(accent.lerp(Color(1.0, 0.55, 0.2), 0.5), 0.75)
			for i5 in 6:
				var zz3: float = z0 + ln * (0.15 + 0.13 * float(i5))
				_cone(_torso, hw * 0.2, hw * (0.6 + 0.3 * sin(PI * float(i5) / 5.0)) * big, Vector3(0, top + hw * 0.2, zz3), Vector3(-0.5, 0, 0), fl)
			if _tail != null:
				_blob(_tail, Vector3(hw * 0.5, hw * 0.5, hw * 0.9) * big, _tail.get_meta("tip", Vector3(0, 0, -ln * 0.42)), fl)
		"antlers":
			# branching antlers of bone (light, at spirit beast) and a halo
			if _head != null:
				var am := litbone if lit else bone
				for sd in [-1.0, 1.0]:
					var base := Vector3(sd * hhw * 0.5, htop + hhw * 0.2, hzc - hhw * 0.15)
					_cone(_head, hhw * 0.13, hhw * 2.4 * big, base, Vector3(-0.35, 0, sd * -0.5), am)
					for b in 2:
						_cone(_head, hhw * 0.08, hhw * 1.1 * big, base + Vector3(sd * hhw * (0.45 + 0.4 * b) * big, hhw * (0.7 + 0.6 * b) * big, 0), Vector3(-0.2, 0, sd * -1.1), am)
				if lit:
					var ring := MeshInstance3D.new()
					var tm := TorusMesh.new()
					tm.inner_radius = hhw * 1.3
					tm.outer_radius = hhw * 1.45
					ring.mesh = tm
					ring.material_override = glow
					ring.position = Vector3(0, htop + hhw * 2.2, hzc)
					_head.add_child(ring)
		"crest":
			# a crest down the head and neck, long ears
			if _head != null:
				for i6 in 5:
					_blob(_head, Vector3(hhw * 0.1, hhw * (0.8 - 0.1 * i6) * big, hhw * 0.45), Vector3(0, htop + hhw * 0.25, hzc - hhw * 0.3 * float(i6)), litbone if lit else bone)
				for sd in [-1.0, 1.0]:
					_blob(_head, Vector3(hhw * 0.22, hhw * 1.6 * big, hhw * 0.5), Vector3(sd * hhw * 0.6, htop + hhw * 0.7, hzc - hhw * 0.2), body, Vector3(-0.4, 0, sd * -0.35))
	role_body_kind = kind
	return kind


## 2026-11-06 (Robert's note 2026-10-31, item 4: "show barding on the model"): the
## armour you fit is worn -- a saddle-cloth or plates over the back, a brow-guard,
## in the armour's own stuff, and grander as the beast grows.
const BARDING := {
	"hide_barding": {"c": Color(0.42, 0.29, 0.18), "shiny": false, "plates": 0, "trim": Color(0.6, 0.45, 0.3)},
	"iron_barding": {"c": Color(0.46, 0.48, 0.52), "shiny": true, "plates": 4, "trim": Color(0.3, 0.3, 0.33)},
	"jade_barding": {"c": Color(0.32, 0.62, 0.45), "shiny": true, "plates": 5, "trim": Color(0.85, 0.75, 0.35)},
	"spiritsilk_barding": {"c": Color(0.68, 0.76, 0.88), "shiny": false, "plates": 3, "trim": Color(0.55, 0.85, 1.0), "glow": true},
}


func barding(armor_id: String, stage: int) -> bool:
	if not BARDING.has(armor_id) or _torso == null:
		return false
	var t := _extent(_torso)
	if not bool(t["ok"]):
		return false
	var spec: Dictionary = BARDING[armor_id]
	var top: float = float(_torso.get_meta("back_y", t["top"]))
	var hw: float = t["hw"]
	var zc: float = t["zc"]
	var ln: float = t["len"]
	var cloth := _surface(spec["c"], bool(spec["shiny"]))
	var trim := _surface(spec["trim"], true)
	if bool(spec.get("glow", false)):
		cloth.emission_enabled = true
		cloth.emission = spec["trim"]
		cloth.emission_energy_multiplier = 0.18
	# the cloth over the back, draping down both flanks
	_blob(_torso, Vector3(hw * 2.12, hw * 0.78, ln * 0.6), Vector3(0, top - hw * 0.26, zc), cloth)
	for sd in [-1.0, 1.0]:
		_blob(_torso, Vector3(hw * 0.12, hw * 1.05, ln * 0.58), Vector3(sd * hw * 1.02, top - hw * 0.75, zc), cloth)
		_blob(_torso, Vector3(hw * 0.14, hw * 0.12, ln * 0.6), Vector3(sd * hw * 1.04, top - hw * 1.25, zc), trim)
	# plates down the spine (more as it grows)
	var n: int = int(spec["plates"]) + (clampi(stage, 0, 3) if int(spec["plates"]) > 0 else 0)
	for i in n:
		var z: float = float(t["z0"]) + ln * (0.22 + 0.56 * float(i) / maxf(1.0, float(n - 1)))
		_blob(_torso, Vector3(hw * 1.1, hw * 0.28, ln * 0.12), Vector3(0, top + hw * 0.12, z), trim)
	# a brow-guard
	if _head != null and int(spec["plates"]) > 0:
		var h := _extent(_head)
		if bool(h["ok"]):
			_blob(_head, Vector3(float(h["hw"]) * 1.5, float(h["hw"]) * 0.35, float(h["len"]) * 0.7), Vector3(0, float(h["top"]) + 0.004, float(h["zc"])), trim)
	return true


func trinket(spec: Dictionary) -> bool:
	## round 183b: Familiar Trinkets (Looks.gd, data/looks.json) -- a collar at the neck, a bell, ribbons, a saddle
	## cloth; looks only. spec: {"collar": [r,g,b], "bell": [..], "ribbon": [..], "cloth": [..], "trim": [..]}
	if _torso == null or _head == null:
		return false
	var h := _extent(_head)
	var t := _extent(_torso)
	if not bool(h["ok"]):
		return false
	var hw: float = float(h["hw"])
	var cf := func(k: String, fb: Color) -> Color:
		var a = spec.get(k, [])
		return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else fb
	var neck := Vector3(0, -hw * 0.35, float(h["z0"]) + hw * 0.25)        # the back of the head, where the neck meets it
	if spec.has("collar"):
		var cm := _surface(cf.call("collar", Color(0.6, 0.15, 0.12)), false)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = hw * 0.78
		tm.outer_radius = hw * 1.02
		tm.rings = 24
		tm.ring_segments = 10
		ring.mesh = tm
		ring.material_override = cm
		ring.position = neck
		ring.rotation.x = PI / 2.0 - 0.35
		ring.name = "Trinket"
		_head.add_child(ring)
	if spec.has("bell"):
		var bm := _surface(cf.call("bell", Color(0.95, 0.78, 0.3)), true)
		var bell := _blob(_head, Vector3(hw * 0.55, hw * 0.6, hw * 0.55), neck + Vector3(0, -hw * 1.1, hw * 0.45), bm)
		bell.name = "Trinket"
	if spec.has("ribbon"):
		var rm := _surface(cf.call("ribbon", Color(0.8, 0.2, 0.3)), false)
		for sd in [-1.0, 1.0]:
			var rb := _blob(_head, Vector3(hw * 0.22, hw * 0.1, hw * 2.4), neck + Vector3(sd * hw * 0.55, hw * 0.45, -hw * 1.2), rm, Vector3(0.45, sd * 0.4, 0))
			rb.name = "Trinket"
	if spec.has("cloth") and bool(t["ok"]):
		var top: float = float(_torso.get_meta("back_y", t["top"]))
		var thw: float = float(t["hw"])
		var cl := _surface(cf.call("cloth", Color(0.2, 0.25, 0.5)), false)
		var tr := _surface(cf.call("trim", Color(0.9, 0.75, 0.35)), true)
		var ln: float = float(t["len"])
		var zc: float = float(t["zc"])
		# a cloth band wrapped round the barrel (a girth), hemmed at both edges, tassels at the flanks
		var cy: float = top - thw * 1.0
		var band := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = ln * 0.36
		cm.radial_segments = 28
		cm.rings = 1
		band.mesh = cm
		band.material_override = cl
		band.rotation.x = PI / 2.0
		band.scale = Vector3(thw * 1.07, 1.0, thw * 1.07)
		band.position = Vector3(0, cy, zc)
		band.name = "Trinket"
		_torso.add_child(band)
		for e in [-1.0, 1.0]:
			var hem := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.97
			tm.outer_radius = 1.05
			tm.rings = 28
			hem.mesh = tm
			hem.material_override = tr
			hem.rotation.x = PI / 2.0
			hem.scale = Vector3(thw * 1.08, thw * 1.08, thw * 1.08)
			hem.position = Vector3(0, cy, zc + e * ln * 0.18)
			hem.name = "Trinket"
			_torso.add_child(hem)
		for sd in [-1.0, 1.0]:
			for k in 2:
				var ts := _blob(_torso, Vector3(thw * 0.12, thw * 0.26, thw * 0.12), Vector3(sd * thw * 1.1, cy - thw * 0.2, zc + ln * (-0.07 + 0.14 * float(k))), tr)
				ts.name = "Trinket"
	return true


func lineage(stage: int, variant: String, vcol: Color, mixcol: Color, gen: int) -> void:
	## round 167: bred blood is seen, not just tinted -- each mutation grows its own features, a
	## second species shows as patches, and generations add marks; all of it deepens with the stage
	if _torso == null:
		return
	var t := _extent(_torso)
	if not bool(t["ok"]):
		return
	var top: float = float(_torso.get_meta("back_y", t["top"]))
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

## 2026-11-06 (Robert's note 2026-10-31, item 5: "better animation set per
## stage: idle, walk, bite, deed, down. Faster, heavier, more confident as it
## grows"). How it carries itself, by stage -- a young animal (0) is light and
## quick and keeps glancing about; grown (1) is the old motion exactly (every
## wild beast and every enemy moves as before); fierce (2) and spirit beast (3)
## stride long and land heavy, hold the head high, look about less, breathe
## slow and deep, and strike faster and further.
##   stride: gait rate   swing: leg swing   bob: weight in each step
##   glance: how much the head wanders   head: head carried (minus is up)
##   bite: seconds a bite takes   lunge: how far it drives in
##   breathe / rate: chest swell and its speed at rest   hop: the follow-hop
const MOTION := [
	{"stride": 1.25, "swing": 0.8, "bob": 0.6, "glance": 1.4, "head": 0.05, "bite": 0.42, "lunge": 0.05, "breathe": 0.012, "rate": 2.8, "hop": 1.0},
	{"stride": 1.0, "swing": 1.0, "bob": 1.0, "glance": 1.0, "head": 0.0, "bite": 0.36, "lunge": 0.07, "breathe": 0.015, "rate": 2.4, "hop": 0.8},
	{"stride": 0.92, "swing": 1.15, "bob": 1.6, "glance": 0.55, "head": -0.1, "bite": 0.3, "lunge": 0.1, "breathe": 0.02, "rate": 2.0, "hop": 0.55},
	{"stride": 0.85, "swing": 1.25, "bob": 2.0, "glance": 0.3, "head": -0.17, "bite": 0.25, "lunge": 0.12, "breathe": 0.026, "rate": 1.6, "hop": 0.4},
]
const DEED_SECONDS := 0.9
var motion_stage := 1                  # set by Familiar (set_motion_stage); wild beasts stay 1
var action := ""                       # "bite", "deed" while it plays (tests)
var _act_t := 0.0
var _down := false                     # lying down (resting while you sit)
var _down_k := 0.0                     # 0 standing .. 1 lying
var _life := 0.0                       # its own clock (breathing, glances)


func set_motion_stage(stage: int) -> void:
	motion_stage = clampi(stage, 0, MOTION.size() - 1)


func motion() -> Dictionary:
	return MOTION[clampi(motion_stage, 0, MOTION.size() - 1)]


func act(kind: String) -> void:
	## "bite" (a lunge and a snap), "deed" (nose down, then a proud rear),
	## "down" (lies down and stays), "up" (gets back up)
	if _dead:
		return
	match kind:
		"down":
			_down = true
		"up":
			_down = false
		"bite", "deed":
			action = kind
			_act_t = 0.0
			if kind == "bite":
				_down = false


func act_seconds() -> float:
	return float(motion()["bite"]) if action == "bite" else DEED_SECONDS


func is_down() -> bool:
	return _down


func _process(delta: float) -> void:
	animate(delta)


func animate(delta: float) -> void:
	if _dead or _torso == null:
		return
	var M := motion()
	var p := global_position
	if _have_last and delta > 0.0:
		var v := (p - _last) / delta
		v.y = 0.0
		_speed = lerpf(_speed, minf(v.length(), 12.0) / maxf(scale.x, 0.2), clampf(delta * 8.0, 0.0, 1.0))
	_last = p
	_have_last = true
	var moving := clampf(_speed / 2.0, 0.0, 1.0)
	_t += delta * (2.0 + _speed * 4.0) * float(M["stride"])
	_down_k = move_toward(_down_k, 1.0 if _down and moving < 0.3 else 0.0, delta / 0.6)
	var swing_m: float = M["swing"]
	for L in _legs:
		var piv: Node3D = L[0]
		piv.rotation.x = sin(_t + float(L[1])) * float(L[2]) * moving * swing_m
	var base_y: float = _torso.get_meta("y", _torso.position.y)
	if not _torso.has_meta("y"):
		_torso.set_meta("y", base_y)
	var base_z: float = _torso.get_meta("z", _torso.position.z)
	if not _torso.has_meta("z"):
		_torso.set_meta("z", base_z)
	var base_rx: float = _torso.get_meta("rx", _torso.rotation.x)
	if not _torso.has_meta("rx"):
		_torso.set_meta("rx", base_rx)
	var bob_m: float = M["bob"]
	var tilt := 0.0
	match plan:
		"hare":
			# hops: up and down in arcs while moving, a twitch of the nose standing
			_torso.position.y = base_y + absf(sin(_t)) * 0.08 * moving * minf(bob_m, 1.3)
			tilt = -cos(_t) * 0.15 * moving
		"bird":
			var flap := 9.0 if flies else (4.0 if moving > 0.2 else 0.0)
			for W in _wings:
				var w: Node3D = W[0]
				w.rotation.z = float(W[1]) * (sin(Time.get_ticks_msec() * 0.001 * flap) * 0.7 if flap > 0.0 else -0.15)
			_torso.position.y = base_y + (sin(_t * 0.5) * 0.04 if flies else 0.0)
		"worm":
			_torso.position.y = base_y
			for i in _segments.size():
				var s: MeshInstance3D = _segments[i]
				s.position.x = sin(_t * 1.5 - i * 0.9) * 0.025 * (0.4 + moving)
				s.position.y = absf(sin(_t * 1.5 - i * 0.9)) * 0.02 * moving
		_:
			# a heavier animal sinks into each step, and rolls with it
			_torso.position.y = base_y + absf(sin(_t)) * 0.012 * moving * bob_m - absf(cos(_t)) * 0.006 * moving * maxf(bob_m - 1.0, 0.0)
			_torso.rotation.z = sin(_t) * 0.04 * moving * sqrt(bob_m)
	_torso.position.z = base_z
	var still := 1.0 - moving
	# idle: the chest rises and falls, slower and deeper as it grows
	_life += delta
	var br: float = sin(_life * float(M["rate"])) * float(M["breathe"]) * still
	_torso.scale = Vector3(1.0 + br * 0.5, 1.0 + br, 1.0)
	var nod := 0.0
	if action != "":
		_act_t += delta
		var dur := act_seconds()
		var k := clampf(_act_t / dur, 0.0, 1.0)
		if action == "bite":
			# drive in fast, snap the jaw down, pull back
			var lunge := sin(k * PI) if k < 0.5 else sin(k * PI) * 0.8
			_torso.position.z = base_z + float(M["lunge"]) * lunge
			tilt += 0.14 * lunge
			nod += 0.45 * sin(minf(k * 1.6, 1.0) * PI)
		else:
			# nose to the ground, then up on its haunches, pleased with itself
			if k < 0.45:
				nod += 0.6 * sin(k / 0.45 * PI * 0.5)
			else:
				var r := sin((k - 0.45) / 0.55 * PI)
				nod += 0.6 * (1.0 - (k - 0.45) / 0.55) - 0.25 * r
				tilt -= 0.3 * r
				_torso.position.y += 0.05 * r
		if _act_t >= dur:
			action = ""
			_act_t = 0.0
	if _down_k > 0.0:
		# lying down: the body sinks, legs fold under (front back, hind forward), head rests
		var dk := _down_k * _down_k * (3.0 - 2.0 * _down_k)
		_torso.position.y = lerpf(_torso.position.y, base_y * 0.45, dk)      # (a bird lands)
		for L in _legs:
			var piv: Node3D = L[0]
			var fold := 1.25 if piv.position.z >= 0.0 else -1.25
			piv.rotation.x = lerpf(piv.rotation.x, fold, dk)
		for W in _wings:
			var w: Node3D = W[0]
			w.rotation.z = lerpf(w.rotation.z, float(W[1]) * -0.15, dk)
		nod = lerpf(nod, 0.22, dk)
		tilt *= 1.0 - dk
	_torso.rotation.x = base_rx + tilt
	if _tail:
		var tw := 0.35 if plan in ["lizard", "ferret"] else 0.15
		_tail.rotation.y = sin(_t * 0.7) * tw * (1.0 - 0.6 * _down_k)
	if _head:
		var base_hx: float = _head.get_meta("rx", _head.rotation.x)
		if not _head.has_meta("rx"):
			_head.set_meta("rx", base_hx)
		var g: float = M["glance"]
		_head.rotation.y = sin(_life * 0.7 * (0.6 + 0.4 * g) + float(get_instance_id() % 7)) * 0.2 * g * still * (1.0 - _down_k)
		_head.rotation.x = base_hx + float(M["head"]) * (1.0 - _down_k) + nod


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
