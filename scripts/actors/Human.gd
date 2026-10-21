extends RefCounted
## Human: a realistic person (Robert, 2026-10-02: "go ahead and download
## them" -- the characters to match the Morrowind/Skyrim look).
##
## Built from three free (CC0) Quaternius kits in assets/characters/:
##   base/     Universal Base Characters -- we use only the HEAD (and eyes,
##             brows) of the male / female base body
##   outfits/  Modular Character Outfits - Fantasy -- peasant and ranger
##             clothes, each with its own arms, legs and feet
##   hair/     hairstyles and a beard, rigged to the head bone
##   anim/     Universal Animation Library -- 40-odd animations on the same
##             skeleton, renamed to what the game already asks for ("idle",
##             "walk", "attack-melee-right", "sit", "die" ...)
## Everything shares one skeleton (same 65 bones, same names), so the head,
## hair and clothes all ride the outfit's skeleton and one AnimationPlayer
## moves the lot. Real-world size: about 1.8 m.
##
## Same spec, same person every time (Dress.spec_for decides it from the
## name). Low graphics keeps the Kenney figure (Art.person).

const ROOT := "res://assets/characters/"
const BASE := {"m": ROOT + "base/Superhero_Male_FullBody.gltf", "f": ROOT + "base/Superhero_Female_FullBody.gltf"}
const BASE_BODY := {"m": "SuperHero_Male", "f": "Superhero_Female"}
const SKIN_TEX := {
	"m": [ROOT + "base/T_Superhero_Male_Light.png", ROOT + "base/T_Superhero_Male_Dark.png"],
	"f": [ROOT + "base/T_Superhero_Female_Light_BaseColor.png", ROOT + "base/T_Superhero_Female_Dark_BaseColor.png"],
}
const OUTFITS := {
	"m": {"peasant": ROOT + "outfits/Male_Peasant.gltf", "ranger": ROOT + "outfits/Male_Ranger.gltf"},
	"f": {"peasant": ROOT + "outfits/Female_Peasant.gltf", "ranger": ROOT + "outfits/Female_Ranger.gltf"},
}
const OUTFIT_TEX := {
	"peasant": [ROOT + "outfits/T_Peasant_BaseColor.png", ROOT + "outfits/T_Peasant_2_BaseColor.png"],
	"ranger": [ROOT + "outfits/T_Ranger_BaseColor.png", ROOT + "outfits/T_Ranger_3_BaseColor.png"],
}
const HAIR := {"short": {"m": "Hair_SimpleParted", "f": "Hair_BuzzedFemale"}, "long": {"m": "Hair_Long", "f": "Hair_Long"},
	"topknot": {"m": "Hair_Buns", "f": "Hair_Buns"}, "buzzed": {"m": "Hair_Buzzed", "f": "Hair_BuzzedFemale"}}
const ANIM_FILE := ROOT + "anim/UAL1_Standard.glb"
## the game's animation names -> the library's
const ANIMS := {"idle": "Idle", "walk": "Walk", "sprint": "Sprint", "jog": "Jog_Fwd", "jump": "Jump", "sit": "Sitting_Idle",
	"attack-melee-right": "Sword_Attack", "punch": "Punch_Cross", "jab": "Punch_Jab", "die": "Death01", "hit": "Hit_Chest",
	"interact": "Interact", "roll": "Roll", "cast": "Spell_Simple_Shoot", "talk": "Idle_Talking", "crouch": "Crouch_Idle",
	"pickup": "PickUp_Table", "kneel": "Fixing_Kneeling", "dance": "Dance", "torch": "Idle_Torch", "guard": "Sword_Idle",
	"aim": "Pistol_Aim_Neutral", "shoot": "Pistol_Shoot", "charge": "Spell_Simple_Idle"}
const LOOPING := ["idle", "walk", "sprint", "jog", "sit", "talk", "crouch", "dance", "torch", "kneel", "guard", "aim", "charge"]
const HEAD_BONES := ["Head", "neck_01"]
## "sit" is always on the ground in this game (meditation, a master at
## their work): the library's chair-sit, turned cross-legged and lowered
## to the floor -- [bone, [[axis, angle], ...]] added to each key, then the
## hips dropped. (Found by eye, rendering variants: tools/ notes in DEV_GUIDE.)
const LOTUS := {"thigh_l": [[Vector3(0, 0, -1), 0.7], [Vector3(0, -1, 0), 1.1]], "thigh_r": [[Vector3(0, 0, 1), 0.7], [Vector3(0, 1, 0), 1.1]],
	"calf_l": [[Vector3(1, 0, 0), 0.9]], "calf_r": [[Vector3(1, 0, 0), 0.9]]}
const SIT_DROP := 0.55

static var _lib: AnimationLibrary = null
static var _scenes := {}
static var _heads := {}            # base body path -> ArrayMesh of just the head
static var _tex := {}


static func available() -> bool:
	for p in [BASE["m"], BASE["f"], OUTFITS["m"]["peasant"], ANIM_FILE]:
		if not ResourceLoader.exists(p):
			return false
	return true


static func _scene(p: String) -> PackedScene:
	if not _scenes.has(p):
		_scenes[p] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[p]


static func _texture(p: String) -> Texture2D:
	if not _tex.has(p):
		_tex[p] = load(p) if ResourceLoader.exists(p) else null
	return _tex[p]


static func library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	_lib = AnimationLibrary.new()
	var sc := _scene(ANIM_FILE)
	if sc == null:
		return _lib
	var n: Node = sc.instantiate()
	var aps := n.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		for k in ANIMS:
			if ap.has_animation(ANIMS[k]):
				var a: Animation = ap.get_animation(ANIMS[k]).duplicate(true)
				a.loop_mode = Animation.LOOP_LINEAR if k in LOOPING else Animation.LOOP_NONE
				if k == "sit":
					_cross_legged(a)
				_lib.add_animation(k, a)
	n.free()
	return _lib


static func _cross_legged(a: Animation) -> void:
	for t in a.get_track_count():
		var bn := str(a.track_get_path(t)).get_slice(":", 1)
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and LOTUS.has(bn):
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				for r in LOTUS[bn]:
					q = q * Quaternion(r[0], float(r[1]))
				a.track_set_key_value(t, k, q)
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and bn == "pelvis":
			for k in a.track_get_key_count(t):
				a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) + Vector3(0, -SIT_DROP, 0))


static func skeleton(model: Node) -> Skeleton3D:
	for n in model.find_children("*", "Skeleton3D", true, false):
		return n
	return null


static func _head_only(mesh: Mesh, skin: Skin) -> ArrayMesh:
	## The base body cut down to its head and neck: only the triangles whose
	## corners are carried by the head or neck bones (the clothes bring
	## their own arms, legs and feet -- the full body would poke through).
	var keep := {}
	for b in skin.get_bind_count():
		if str(skin.get_bind_name(b)) in HEAD_BONES:
			keep[b] = true
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if bones.is_empty() or idx.is_empty():
			continue
		var per := bones.size() / maxi(1, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		var on := PackedByteArray()
		on.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		for v in on.size():
			var w := 0.0
			for j in per:
				if keep.has(bones[v * per + j]):
					w += weights[v * per + j]
			on[v] = 1 if w >= 0.5 else 0
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if on[idx[t]] == 1 and on[idx[t + 1]] == 1 and on[idx[t + 2]] == 1:
				kept.append(idx[t])
				kept.append(idx[t + 1])
				kept.append(idx[t + 2])
		arr[Mesh.ARRAY_INDEX] = kept
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arr[c] = null          # (custom channels need their own format flags; the head doesn't use them)
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


static func make(spec: Dictionary) -> Node3D:
	## A person dressed by spec: {"sex": "m"|"f", "outfit": "peasant"|"ranger",
	## "variant": 0|1, "skin": 0|1, "hair": style, "hair_color", "beard",
	## "hood", "tint": [r,g,b]}
	var sex := "f" if str(spec.get("sex", "m")) == "f" else "m"
	var kind := "ranger" if str(spec.get("outfit", "peasant")) == "ranger" else "peasant"
	var model: Node3D = _scene(OUTFITS[sex][kind]).instantiate()
	model.name = "Human"
	model.set_meta("human", true)
	model.set_meta("sex", sex)
	var sk := skeleton(model)
	# the clothes: texture variant, a tint toward the person's colours, the
	# hood only when they wear it
	var tint: Color = Color(1, 1, 1)
	if spec.get("tint") is Array and (spec["tint"] as Array).size() >= 3:
		var t: Array = spec["tint"]
		tint = Color(1, 1, 1).lerp(Color(float(t[0]), float(t[1]), float(t[2])), 0.55)
	var otex := _texture(OUTFIT_TEX[kind][int(spec.get("variant", 0)) % 2])
	var hood := bool(spec.get("hood", false))
	# (re-materialling is looks only -- and the headless engine check's dummy
	# renderer errors on it, the same as Companion._tint found -- so skip it there)
	var looks := DisplayServer.get_name() != "headless"
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.name.contains("Hood"):
			m3.visible = hood
			continue
		for s in (m3.mesh.get_surface_count() if looks else 0):
			var mat = m3.get_active_material(s)
			if mat is StandardMaterial3D:
				var dm: StandardMaterial3D = mat.duplicate()
				var tex_name := str(dm.albedo_texture.resource_path) if dm.albedo_texture else ""
				if tex_name.contains("T_Peasant") or tex_name.contains("T_Ranger"):
					if otex:
						dm.albedo_texture = otex
					dm.albedo_color = tint
					_cloth(dm)
				else:
					_skin(dm)
				m3.set_surface_override_material(s, dm)
	# the hair colour (the brows take it too -- round 47: they were left white)
	var hc: Color = Color(0.25, 0.17, 0.1)
	if spec.get("hair_color") is Array and (spec["hair_color"] as Array).size() >= 3:
		var c: Array = spec["hair_color"]
		hc = Color(float(c[0]), float(c[1]), float(c[2]))
	# the head, eyes and brows from the base character, onto this skeleton
	var base: Node = _scene(BASE[sex]).instantiate()
	var skin_tex := _texture(SKIN_TEX[sex][int(spec.get("skin", 0)) % 2])
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		var src := mi as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.name = "Head_" + src.name
		copy.skin = src.skin
		if src.name == BASE_BODY[sex]:
			var key: String = BASE[sex]
			if not _heads.has(key):
				_heads[key] = _head_only(src.mesh, src.skin)
			copy.mesh = _heads[key]
			var hm = copy.mesh.surface_get_material(0)
			if looks and hm is StandardMaterial3D and skin_tex:
				var dm2: StandardMaterial3D = hm.duplicate()
				dm2.albedo_texture = skin_tex
				_skin(dm2)
				copy.set_surface_override_material(0, dm2)
		else:
			copy.mesh = src.mesh
			if looks and str(src.name) == "Eyebrows":
				var bm = src.get_active_material(0)
				if bm is StandardMaterial3D:
					var db: StandardMaterial3D = bm.duplicate()
					db.albedo_color = Color(minf(hc.r * 1.15, 1.0), minf(hc.g * 1.15, 1.0), minf(hc.b * 1.15, 1.0)).darkened(0.15)
					db.roughness = 0.85
					copy.set_surface_override_material(0, db)
			elif looks and str(src.name) == "Eyes":
				var em = src.get_active_material(0)
				if em is StandardMaterial3D:
					var de: StandardMaterial3D = em.duplicate()
					de.roughness = 0.08                 # a wet eye catches the light
					de.clearcoat_enabled = true
					de.clearcoat = 0.6
					copy.set_surface_override_material(0, de)
		sk.add_child(copy)
		copy.skeleton = NodePath("..")
	base.free()
	# hair (and a beard), unless a hood covers it
	var hs := str(spec.get("hair", "short"))
	var hair_names := []
	if HAIR.has(hs) and not hood:
		hair_names.append(str(HAIR[hs][sex]))
	if bool(spec.get("beard", false)) and sex == "m":
		hair_names.append("Hair_Beard")
	for hn in hair_names:
		var hsc := _scene(ROOT + "hair/" + str(hn) + ".gltf")
		if hsc == null:
			continue
		var hnode: Node = hsc.instantiate()
		for mi in hnode.find_children("*", "MeshInstance3D", true, false):
			var src2 := mi as MeshInstance3D
			var h := MeshInstance3D.new()
			h.name = "Hair_" + str(hn)
			h.mesh = src2.mesh
			h.skin = src2.skin
			for s in (src2.mesh.get_surface_count() if looks else 0):
				var hm2 = src2.get_active_material(s)
				if hm2 is StandardMaterial3D:
					var d3: StandardMaterial3D = hm2.duplicate()
					d3.albedo_color = Color(minf(hc.r * 1.35, 1.0), minf(hc.g * 1.35, 1.0), minf(hc.b * 1.35, 1.0))     # the hair texture is light: colour it
					d3.roughness = 0.42                       # round 37: hair has a sheen that runs along it
					d3.anisotropy_enabled = true
					d3.anisotropy = 0.55
					d3.rim_enabled = true
					d3.rim = 0.2
					d3.rim_tint = 0.6
					h.set_surface_override_material(s, d3)
			sk.add_child(h)
			h.skeleton = NodePath("..")
		hnode.free()
	# one AnimationPlayer for everything, with the game's names
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", library())
	ap.playback_default_blend_time = 0.2       # round 37: every figure eases from one move into the next
	return model



# ---- round 37: materials that read as skin and cloth (Robert: "make the
# characters more realistic") ---------------------------------------------------
static func _skin(m: StandardMaterial3D) -> void:
	## light that sinks into skin and glows back out of it, a soft sheen, a
	## faint rim so a face holds its shape in the dark
	m.roughness = 0.62                  # round 47: less plastic, more skin
	m.metallic = 0.0
	m.metallic_specular = 0.32
	m.albedo_color = m.albedo_color * Color(0.94, 0.89, 0.87)       # (the scanned skin ran orange under warm light)
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.45
	m.subsurf_scatter_skin_mode = true
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.5


static func _cloth(m: StandardMaterial3D) -> void:
	## cloth drinks light: rough, a little fuzz at the edges (rim)
	m.roughness = maxf(m.roughness, 0.88)
	m.metallic = 0.0
	m.rim_enabled = true
	m.rim = 0.12
	m.rim_tint = 0.8
