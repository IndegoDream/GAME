extends RefCounted
## Monster: the dungeon's creatures as real, smooth, textured bodies instead
## of the blocky Kenney orc (Robert, 2026-10-03: "less blocky and more
## smooth ... more realistic").
##
## Two of Quaternius' Bestiary monsters (assets/characters/monsters/, free
## under the Quaternius Asset License -- see LICENSE-bestiary.txt) -- the
## Imp and the Puglin -- are built on the same 55-bone skeleton as the
## people (Human.gd), so the same animation library moves them: walk,
## attack, hit, die. The pelvis keys are lowered to their shorter legs.
##
## Anything that isn't an imp or a puglin -- golems, guardians, wraiths,
## skeletons -- is a full human body (Human.gd) given a SKIN: stone, clay,
## brass, crystal, bone, or a ghost-light that you can half see through.
## pick() decides which from the name. Low graphics keeps the Kenney toys.

const ROOT := "res://assets/characters/monsters/"
const KINDS := {
	"imp": {"path": ROOT + "Imp.glb", "tex": ["", ROOT + "T_Imp_BaseColor_2.png", ROOT + "T_Imp_BaseColor_3.png"], "scale": 1.15},
	"puglin": {"path": ROOT + "Puglin.glb", "tex": ["", ROOT + "T_Puglin_BaseColor_2.png", ROOT + "T_Puglin_BaseColor_3.png"], "scale": 1.05},
}
const HUMAN_PELVIS := 0.9491       # the people's hip height in the library's keys

## words in a creature's name -> what it's built as
const BODY_WORDS := {
	"imp": ["imp", "wisp", "sporeling", "drakeling", "thornling", "ghoul", "stalker", "spider", "crawler", "fiend", "sprite", "gremlin", "kobold", "demon"],
	"puglin": ["goblin", "brute", "shambler", "chief", "orc", "ogre", "troll", "brood", "boar", "hog", "bandit", "raider"],
	"golem": ["golem", "guardian", "sentinel", "juggernaut", "colossus", "behemoth", "cavalier", "warden", "keeper", "soldier", "statue", "construct", "sentry", "automaton"],
}
## words -> a skin for a body (people included)
const SKIN_WORDS := {
	"spectral": ["wraith", "shade", "ghost", "spirit", "phantom", "wisp", "reflection", "shattered", "spectre", "specter", "echo", "dream"],
	"bone": ["skeleton", "bone", "skull", "lich", "ossuary"],
	"crystal": ["crystal", "shard", "glass", "resonant", "prism", "mirror", "frost", "rime", "ice", "glacial"],
	"metal": ["brass", "clock", "gear", "steel", "iron", "copper", "bronze", "nanite", "mechan"],
	"clay": ["clay", "terracotta", "buried", "mud"],
	"stone": ["golem", "stone", "rock", "meteor", "statue", "sentinel", "colossus", "celestial", "dune"],
	"bark": ["root", "thorn", "bark", "vine", "grove", "behemoth", "moss"],
	"ember": ["cinder", "slag", "ember", "furnace", "magma", "ash", "flame", "fire"],
}
const SKINS := {
	"stone": {"color": [0.55, 0.53, 0.5], "rough": 0.95, "metal": 0.0, "noise": 0.08},
	"clay": {"color": [0.66, 0.42, 0.3], "rough": 0.9, "metal": 0.0, "noise": 0.05},
	"metal": {"color": [0.72, 0.58, 0.32], "rough": 0.35, "metal": 0.85, "noise": 0.03},
	"crystal": {"color": [0.55, 0.8, 0.95], "rough": 0.08, "metal": 0.1, "noise": 0.02, "glow": 0.6, "alpha": 0.82},
	"bone": {"color": [0.86, 0.82, 0.72], "rough": 0.8, "metal": 0.0, "noise": 0.04},
	"bark": {"color": [0.36, 0.27, 0.18], "rough": 1.0, "metal": 0.0, "noise": 0.12},
	"ember": {"color": [0.2, 0.15, 0.13], "rough": 0.85, "metal": 0.0, "noise": 0.1, "glow": 1.6, "glow_color": [1.0, 0.42, 0.1]},
	"spectral": {"color": [0.6, 0.85, 1.0], "rough": 0.4, "metal": 0.0, "noise": 0.0, "glow": 1.2, "alpha": 0.45},
}

static var _scenes := {}
static var _libs := {}
static var _mats := {}


static func available(kind: String) -> bool:
	return KINDS.has(kind) and ResourceLoader.exists(str(KINDS[kind]["path"]))


static func _has_word(text: String, words: Array) -> bool:
	for w in words:
		if text.contains(str(w)):
			return true
	return false


static func pick(stats: Dictionary) -> String:
	## "imp" | "puglin" | "golem" -- what body a monster that used to be
	## the Kenney orc gets now
	var n := ("%s %s" % [stats.get("name", ""), stats.get("id", "")]).to_lower()
	for k in ["golem", "imp", "puglin"]:
		if _has_word(n, BODY_WORDS[k]):
			return k
	return "puglin" if float(stats.get("scale", 1.0)) >= 1.3 else "imp"


static func skin_for(stats: Dictionary) -> String:
	var n := ("%s %s" % [stats.get("name", ""), stats.get("id", "")]).to_lower()
	for k in SKIN_WORDS:
		if _has_word(n, SKIN_WORDS[k]):
			return k
	return ""


static func library(kind: String) -> AnimationLibrary:
	## the people's animations, hips lowered to this creature's legs
	if _libs.has(kind):
		return _libs[kind]
	var H := preload("res://scripts/actors/Human.gd")
	var base: AnimationLibrary = H.library()
	var lib := AnimationLibrary.new()
	var ratio := 1.0
	var sc := _scene(str(KINDS[kind]["path"]))
	if sc:
		var n: Node = sc.instantiate()
		var sk: Skeleton3D = H.skeleton(n)
		if sk and sk.find_bone("pelvis") >= 0:
			ratio = sk.get_bone_rest(sk.find_bone("pelvis")).origin.z / HUMAN_PELVIS if absf(sk.get_bone_rest(sk.find_bone("pelvis")).origin.z) > 0.1 else sk.get_bone_rest(sk.find_bone("pelvis")).origin.y / HUMAN_PELVIS
		n.free()
	ratio = clampf(absf(ratio), 0.4, 1.2)
	for an in base.get_animation_list():
		var a: Animation = base.get_animation(an).duplicate(true)
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and str(a.track_get_path(t)).ends_with(":pelvis"):
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ratio)
		lib.add_animation(an, a)
	_libs[kind] = lib
	return lib


static func _scene(p: String) -> PackedScene:
	if not _scenes.has(p):
		_scenes[p] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[p]


static var _texs := {}


static func make(kind: String, variant: int, tint: Color) -> Node3D:
	## an Imp or a Puglin, its own texture variant, nudged toward the
	## creature's colour, with the game's animation names
	var sc := _scene(str(KINDS[kind]["path"]))
	var model: Node3D = sc.instantiate() if sc else Node3D.new()
	model.name = "Monster"
	model.set_meta("monster", kind)
	var looks := DisplayServer.get_name() != "headless"
	var texs: Array = KINDS[kind]["tex"]
	var tp := str(texs[variant % texs.size()])
	var tex: Texture2D = null
	if looks and tp != "":           # (a headless run never draws it: skipping the load saves ~19 ms a foe; one load per texture)
		if not _texs.has(tp):
			_texs[tp] = load(tp) if ResourceLoader.exists(tp) else null
		tex = _texs[tp]
	var t2 := Color(1, 1, 1).lerp(tint, 0.35)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for s in (m3.mesh.get_surface_count() if looks else 0):
			var mat = m3.get_active_material(s)
			if mat is StandardMaterial3D:
				var dm: StandardMaterial3D = mat.duplicate()
				if tex and m3.name.ends_with("_Body"):
					dm.albedo_texture = tex
				if m3.name.ends_with("_Body"):
					dm.albedo_color = t2
				m3.set_surface_override_material(s, dm)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", library(kind))
	model.scale = Vector3.ONE * float(KINDS[kind]["scale"])
	return model


static func skin_material(skin: String, tint: Color) -> StandardMaterial3D:
	## one shared material per skin and colour
	var key := "%s:%s" % [skin, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var d: Dictionary = SKINS.get(skin, SKINS["stone"])
	var c: Array = d["color"]
	var base := Color(float(c[0]), float(c[1]), float(c[2])).lerp(tint, 0.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = float(d["rough"])
	m.metallic = float(d["metal"])
	if float(d.get("noise", 0.0)) > 0.0:
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		var fn := FastNoiseLite.new()
		fn.frequency = 0.04
		fn.fractal_octaves = 4
		nt.noise = fn
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 0.8
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.0
		var at := NoiseTexture2D.new()
		at.width = 256
		at.height = 256
		at.seamless = true
		var fa := FastNoiseLite.new()
		fa.frequency = 0.03
		at.noise = fa
		at.color_ramp = Gradient.new()
		at.color_ramp.set_color(0, Color(1, 1, 1).darkened(float(d["noise"]) * 4.0))
		at.color_ramp.set_color(1, Color(1, 1, 1))
		m.albedo_texture = at
	if d.has("glow"):
		m.emission_enabled = true
		var gc: Array = d.get("glow_color", c)
		m.emission = Color(float(gc[0]), float(gc[1]), float(gc[2])).lerp(tint, 0.25)
		m.emission_energy_multiplier = float(d["glow"])
		if d.has("glow_color"):
			# the glow shows in the cracks, not all over (the noise in the albedo)
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_texture = m.albedo_texture
	if d.has("alpha"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(d["alpha"])
		m.rim_enabled = true
		m.rim = 0.8
		m.rim_tint = 0.6
	_mats[key] = m
	return m


static func apply_skin(model: Node, skin: String, tint: Color) -> void:
	## dress every surface of a body in a skin (stone, bone, ghost-light...)
	if skin == "" or DisplayServer.get_name() == "headless":
		return
	var m := skin_material(skin, tint)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		if m3.name.begins_with("Hair_") or m3.name.contains("Eye") or m3.name.contains("Brow"):
			m3.visible = false     # no hair or eyes on a golem, a skeleton, a ghost
			continue
		for s in m3.mesh.get_surface_count():
			m3.set_surface_override_material(s, m)
	if model is Node3D:
		(model as Node3D).set_meta("skin", skin)
