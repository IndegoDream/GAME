extends RefCounted
## Art: which model stands in for a prop. Robert, 2026-10-02: "as close to
## Morrowind or Skyrim in style". The world was built from Kenney's simple
## low-poly kits; at Medium graphics and up, every prop that has a
## photo-scanned stand-in (Poly Haven, CC0 -- assets/realistic/, with
## manifest.json saying where each came from) uses it instead.
##
## The stand-in is fitted to the Kenney model's own size and footing, so
## nothing in a level moves: a barrel is still exactly where (and as big
## as) the barrel was. Anything without a stand-in -- or a stand-in that
## isn't there / hasn't been imported yet -- stays the Kenney model.
## style "kenney" (Low graphics) is the old look, untouched.

const KENNEY := "res://assets/kenney/"
const REAL := "res://assets/realistic/"

## kenney model -> [stand-ins...] (a level picks among them by place, so a
## room of barrels isn't twelve copies of one barrel). An entry can be
## [id, extra_scale] when the fitted size reads wrong.
const SWAP := {
	"mini-dungeon/barrel.glb": ["wine_barrel_01", "wooden_barrels_01"],
	"mini-dungeon/pot.glb": ["ceramic_pot", "wooden_bucket_01"],
	"nature-kit/pot_small.glb": ["ceramic_vase_01", "antique_ceramic_vase_01", "jug_01"],
	"nature-kit/pot_large.glb": ["brass_pot_01", "antique_ceramic_vase_01"],
	"mini-dungeon/rocks.glb": ["boulder_01", "namaqualand_boulder_02"],
	"mini-dungeon/stones.glb": ["rock_07", "rock_09", "stone_01"],
	"nature-kit/rock_smallA.glb": ["rock_07"], "nature-kit/rock_smallB.glb": ["rock_09"], "nature-kit/rock_smallC.glb": ["stone_01"],
	"nature-kit/rock_largeA.glb": ["boulder_01"], "nature-kit/rock_tallA.glb": ["namaqualand_boulder_02"],
	"nature-kit/stone_smallA.glb": ["stone_01"], "nature-kit/stone_smallB.glb": ["rock_07"],
	"nature-kit/stone_smallFlatA.glb": ["rock_09"], "nature-kit/stone_smallFlatB.glb": ["rock_09"],
	"nature-kit/stone_smallTopA.glb": ["rock_07"],
	"nature-kit/stone_tallA.glb": ["boulder_01"], "nature-kit/stone_tallB.glb": ["namaqualand_boulder_02"], "nature-kit/stone_tallC.glb": ["boulder_01"],
	"mini-dungeon/table.glb": ["WoodenTable_01", "chinese_tea_table"],
	"mini-dungeon/chair.glb": ["chinese_stool"],
	"mini-dungeon/chest.glb": ["treasure_chest"],
	"mini-dungeon/weapon-sword.glb": ["antique_katana_01", "wooden_handle_saber"],
	"mini-dungeon/shield-round.glb": ["kite_shield"], "mini-dungeon/shield-rectangle.glb": ["kite_shield"],
	"mini-dungeon/potion.glb": ["jug_01"],
	# (no stand-in for the town's street lanterns: a real hand lantern blown
	# up to street-lamp size looked silly -- seen in the village, round 18)
	"nature-kit/campfire_stones.glb": ["stone_fire_pit"], "nature-kit/campfire_bricks.glb": ["stone_fire_pit"],
	"nature-kit/log.glb": ["dead_tree_trunk", "dead_tree_trunk_02"],
	"nature-kit/stump_old.glb": ["tree_stump_01"], "nature-kit/stump_roundDetailed.glb": ["tree_stump_02"],
	"nature-kit/plant_bush.glb": ["shrub_02"], "nature-kit/plant_bushLarge.glb": ["shrub_02"],
	"nature-kit/plant_bushDetailed.glb": ["shrub_04", "nettle_plant"],
	"nature-kit/grass.glb": ["grass_medium_01"], "nature-kit/grass_large.glb": ["grass_medium_01"],
	"nature-kit/grass_leafs.glb": ["weed_plant_02"], "nature-kit/grass_leafsLarge.glb": ["fern_02"],
	"nature-kit/plant_flatShort.glb": ["fern_02"], "nature-kit/plant_flatTall.glb": ["fern_02"],
	"nature-kit/statue_head.glb": ["marble_bust_01"],
	"nature-kit/statue_block.glb": ["boulder_01"],
	"nature-kit/statue_columnDamaged.glb": ["gothic_statue"],
	"nature-kit/bed_floor.glb": ["old_bed_frame"],
	# round 47: real flowers
	"nature-kit/flower_purpleA.glb": ["flower_empodium"], "nature-kit/flower_purpleB.glb": ["flower_gazania"], "nature-kit/flower_purpleC.glb": ["flower_empodium"],
	"nature-kit/flower_redA.glb": ["flower_gazania"], "nature-kit/flower_redB.glb": ["flower_gazania"], "nature-kit/flower_redC.glb": ["flower_empodium"],
	"nature-kit/flower_yellowA.glb": ["flower_empodium"], "nature-kit/flower_yellowB.glb": ["flower_gazania"], "nature-kit/flower_yellowC.glb": ["flower_empodium"],
	"mini-dungeon/wood-structure.glb": ["wooden_bookshelf_worn"],
}

## kenney model -> a photo texture laid over its own shape (houses, roofs,
## columns: no photo-scanned stand-in, but they needn't look like toys):
## [texture folder (assets/textures), tint, metres per tile]
const REMAT := {
	"fantasy-town-kit/wall-block.glb": ["old_stone_wall", [0.95, 0.92, 0.88], 2.0],
	"fantasy-town-kit/wall-wood-block.glb": ["old_wood_floor", [0.85, 0.75, 0.62], 1.6],
	"fantasy-town-kit/chimney.glb": ["castle_brick_01", [0.85, 0.8, 0.78], 1.2],
	"fantasy-town-kit/planks.glb": ["old_wood_floor", [0.85, 0.78, 0.68], 1.6],
	"mini-dungeon/column.glb": ["castle_brick_01", [0.9, 0.88, 0.85], 1.5],
	"nature-kit/cliff_block_rock.glb": ["rock_face", [0.9, 0.88, 0.85], 2.5],
	"nature-kit/statue_obelisk.glb": ["mossy_stone_wall", [0.9, 0.9, 0.88], 1.5],
	"nature-kit/statue_ring.glb": ["mossy_stone_wall", [0.9, 0.9, 0.88], 1.5],
	# round 47 (Robert: "more visually realistic worlds"): what was still a toy --
	# canvas tents, weathered wood stalls, carts and fences, linen banners,
	# a thatched roof, a marble fountain, iron lamp posts and trap plates.
	# A {"default": spec, "<material>": spec, "keep": [materials]} entry
	# re-surfaces each part of a model by its material.
	"fantasy-town-kit/roof-gable.glb": ["thatch_roof_angled", [0.92, 0.85, 0.72], 1.4],
	"nature-kit/tent_smallOpen.glb": {"default": ["rough_linen", [0.9, 0.82, 0.7], 1.2], "wood": ["weathered_planks", [0.8, 0.72, 0.62], 1.0]},
	"nature-kit/tent_smallClosed.glb": {"default": ["rough_linen", [0.9, 0.82, 0.7], 1.2], "wood": ["weathered_planks", [0.8, 0.72, 0.62], 1.0]},
	"nature-kit/tent_detailedOpen.glb": {"default": ["rough_linen", [0.82, 0.86, 0.78], 1.2], "wood": ["weathered_planks", [0.8, 0.72, 0.62], 1.0]},
	"nature-kit/tent_detailedClosed.glb": {"default": ["rough_linen", [0.82, 0.86, 0.78], 1.2], "wood": ["weathered_planks", [0.8, 0.72, 0.62], 1.0]},
	"fantasy-town-kit/stall.glb": ["weathered_planks", [0.85, 0.78, 0.68], 1.2],
	"fantasy-town-kit/stall-red.glb": ["weathered_planks", [0.95, 0.72, 0.62], 1.2],
	"fantasy-town-kit/stall-green.glb": ["weathered_planks", [0.75, 0.88, 0.7], 1.2],
	"fantasy-town-kit/cart.glb": ["weathered_planks", [0.85, 0.78, 0.68], 1.0],
	"fantasy-town-kit/cart-high.glb": ["weathered_planks", [0.85, 0.78, 0.68], 1.0],
	"fantasy-town-kit/fence.glb": ["weathered_planks", [0.8, 0.74, 0.65], 1.0],
	"fantasy-town-kit/fence-broken.glb": ["weathered_planks", [0.8, 0.74, 0.65], 1.0],
	"fantasy-town-kit/fence-gate.glb": ["weathered_planks", [0.8, 0.74, 0.65], 1.0],
	"fantasy-town-kit/banner-green.glb": ["rough_linen", [0.55, 0.8, 0.55], 0.8],
	"fantasy-town-kit/banner-red.glb": ["rough_linen", [0.9, 0.45, 0.4], 0.8],
	"mini-dungeon/banner.glb": ["rough_linen", [0.85, 0.82, 0.75], 0.8],
	"fantasy-town-kit/lantern.glb": ["metal_plate_02", [0.5, 0.47, 0.45], 0.8],
	"fantasy-town-kit/fountain-round.glb": {"default": ["marble_01", [0.92, 0.9, 0.86], 1.5], "keep": ["Water"]},
	"mini-dungeon/trap.glb": ["metal_plate_02", [0.75, 0.7, 0.66], 0.7],
	"nature-kit/statue_column.glb": ["marble_01", [0.88, 0.86, 0.82], 1.2],
	"fantasy-town-kit/pillar-stone.glb": ["marble_01", [0.85, 0.83, 0.8], 1.2],
}

## 2026-11-06, the CC0 art pack (ArtPack.gd -- Quaternius' Fantasy Props and
## Medieval Village MegaKits, assets/cc0/): more stand-ins, only while the pack
## is on. "pk:" = assets/cc0/props/<name>.gltf, "vk:" = assets/cc0/village/.
## Listed with the photo-scanned ones a level already picks among, so a market
## is a mix of both.
const SWAP_PACK := {
	"fantasy-town-kit/stall.glb": ["pk:Stall_Empty", "pk:Stall_Cart_Empty"],
	"fantasy-town-kit/stall-red.glb": ["pk:Stall_Cart_Empty", "pk:Stall_Empty"],
	"fantasy-town-kit/stall-green.glb": ["pk:Stall_Empty"],
	"fantasy-town-kit/cart.glb": ["vk:Prop_Wagon"],
	"fantasy-town-kit/cart-high.glb": ["vk:Prop_Wagon"],
	"mini-dungeon/barrel.glb": ["wine_barrel_01", "pk:Barrel", "wooden_barrels_01"],
	"mini-dungeon/table.glb": ["WoodenTable_01", "pk:Table_Large", "chinese_tea_table"],
	"mini-dungeon/chair.glb": ["chinese_stool", "pk:Chair_1", "pk:Stool"],
	"mini-dungeon/wood-structure.glb": ["wooden_bookshelf_worn", "pk:Bookcase_2"],
	"nature-kit/pot_small.glb": ["ceramic_vase_01", "pk:Vase_2", "jug_01"],
	"mini-dungeon/pot.glb": ["ceramic_pot", "pk:Bucket_Wooden_1", "wooden_bucket_01"],
	# the Lands' big stones and crags (2026-11-06): photo-scanned rock, not low-poly blocks
	"nature-kit/rock_largeB.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/rock_largeC.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/rock_largeD.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/rock_largeE.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/rock_largeF.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/rock_tallB.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallC.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallD.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallE.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallF.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallG.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallH.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallI.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/rock_tallJ.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_largeA.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_largeB.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_largeC.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_largeD.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_largeE.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_largeF.glb": ["stone_01", "boulder_01", "rock_07", "rock_moss_set_01"],
	"nature-kit/stone_tallD.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallE.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallF.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallG.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallH.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallI.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/stone_tallJ.glb": ["namaqualand_boulder_02", "rock_07", "boulder_01", "rock_09"],
	"nature-kit/cliff_rock.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
	"nature-kit/cliff_stone.glb": ["boulder_01", "namaqualand_boulder_02", "rock_moss_set_01", "rock_moss_set_02"],
}
const PACK_DIRS := {"pk": "res://assets/cc0/props/", "vk": "res://assets/cc0/village/", "rk": "res://assets/cc0/rocks/"}

static var style := "realistic"           # set by Gfx (Low graphics = "kenney")
static var _scenes := {}                  # path -> PackedScene (or null)
static var _boxes := {}                   # path -> AABB of the model as built


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


## round 186: the photo scans ran 10,000-100,000 triangles apiece -- a village's grass alone was 16.6 million
## triangles a frame (670 tufts x 24,730). Each heavy scan now has a low-poly copy beside it (<id>_lo.gltf,
## tools/gen/decimate_gltf.py: 2,000-8,000 triangles, the same photo textures); every preset but Ultra uses it.
static var full_detail := false
static var _lo := {}


static func real_path(id: String) -> String:
	if id.length() > 3 and id[2] == ":" and PACK_DIRS.has(id.substr(0, 2)):
		return PACK_DIRS[id.substr(0, 2)] + id.substr(3) + ".gltf"
	if not full_detail and not id.ends_with("_lo"):
		if not _lo.has(id):
			var lo := REAL + id + "/" + id + "_lo.gltf"
			_lo[id] = lo if ResourceLoader.exists(lo) else ""
		if str(_lo[id]) != "":
			return str(_lo[id])
	return REAL + id + "/" + id + ".gltf"


static func swap_list(rel: String) -> Array:
	## the stand-ins this model may take right now
	if SWAP_PACK.has(rel) and preload("res://scripts/core/ArtPack.gd").on():
		return SWAP_PACK[rel]
	return SWAP.get(rel, [])


static func stand_in(rel: String, pick: int = 0) -> String:
	## The photo-scanned model that would stand in for this Kenney one
	## ("" for none, or when it isn't on disk).
	if style == "kenney":
		return ""
	var opts: Array = swap_list(rel)
	if opts.is_empty():
		return ""
	var e = opts[absi(pick) % opts.size()]
	var id := str(e[0]) if e is Array else str(e)
	return id if scene(real_path(id)) != null else ""


static func make(rel: String, pick: int = 0) -> Node3D:
	## A model for this Kenney path (e.g. "mini-dungeon/barrel.glb"),
	## photo-scanned when one fits. Same size and footing either way.
	var kpath := KENNEY + rel
	var id := stand_in(rel, pick)
	if id == "":
		var ks := scene(kpath)
		if style != "kenney" and is_tree(rel) and preload("res://scripts/world/Tree.gd").available():
			return _tree(rel, kpath, pick)              # round 47: a realistic tree
		var k: Node3D = ks.instantiate() if ks else Node3D.new()
		if style != "kenney" and REMAT.has(rel):
			_remat(k, REMAT[rel])
		return k
	var holder := Node3D.new()
	holder.name = "Art_" + id
	var m: Node3D = scene(real_path(id)).instantiate()
	holder.add_child(m)
	var want := box(kpath)
	var have := box(real_path(id))
	if have.size.length() < 0.0001:
		return holder
	var k := 1.0
	if want.size.length() > 0.0001:
		k = maxf(maxf(want.size.x, want.size.z), want.size.y) / maxf(maxf(have.size.x, have.size.z), have.size.y)
	var opts: Array = swap_list(rel)
	for e in opts:
		if e is Array and str(e[0]) == id and e.size() > 1:
			k *= float(e[1])
	m.scale = Vector3.ONE * k
	# stand on the same ground, centred where the old one was
	var hc := have.get_center() * k
	var wc := want.get_center() if want.size.length() > 0.0001 else Vector3.ZERO
	m.position = Vector3(wc.x - hc.x, want.position.y - have.position.y * k, wc.z - hc.z)
	return holder


static func _remat(k: Node, spec) -> void:
	## photo surfaces over a Kenney shape -- the whole model, or part by part
	## (by each surface's material name)
	var L := preload("res://scripts/world/Look.gd")
	if spec is Array:
		var mat: Material = L.surface(spec)
		for mi in k.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			if m3.mesh == null:
				continue
			for i in m3.mesh.get_surface_count():
				m3.set_surface_override_material(i, mat)
		return
	var d: Dictionary = spec
	var keep: Array = d.get("keep", [])
	for mi in k.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for i in m3.mesh.get_surface_count():
			var sm = m3.mesh.surface_get_material(i)
			var nm := str(sm.resource_name) if sm else ""
			if nm in keep:
				continue
			var sp = d.get(nm, d.get("default", null))
			if sp is Array:
				m3.set_surface_override_material(i, L.surface(sp))


static func is_tree(rel: String) -> bool:
	var f := rel.get_file()
	return rel.ends_with(".glb") and (f.begins_with("tree") or f.begins_with("tree_")) and not f.contains("stump") and not f.contains("log")


static func tree_season(rel: String) -> String:
	if rel.contains("_fall"):
		return "fall"
	if rel.contains("_dark"):
		return "dark"
	return ""


static func _tree(rel: String, kpath: String, pick: int) -> Node3D:
	## the realistic tree, as tall as the Kenney one stood (its own scale is
	## applied by whoever places it, as before) -- a little taller, since
	## the toy trees were squat
	var f := rel.get_file()
	var conifer := f.contains("pine") or f.contains("cone") or f.contains("high") or f.contains("fir") or (f == "tree.glb" and absi(pick) % 3 == 0)
	var want := box(kpath)
	var h := want.size.y if want.size.y > 0.01 else 1.5
	var t: Node3D = preload("res://scripts/world/Tree.gd").make(conifer, h * 1.25, hash(rel) + pick * 7919, tree_season(rel))
	t.name = "Art_tree"
	return t


static func box(path: String) -> AABB:
	if _boxes.has(path):
		return _boxes[path]
	var ab := AABB()
	var sc := scene(path)
	if sc:
		var n: Node = sc.instantiate()
		ab = _merge(n, Transform3D.IDENTITY, AABB(), true)
		n.free()
	_boxes[path] = ab
	return ab


static func _merge(n: Node, xf: Transform3D, acc: AABB, first: bool) -> AABB:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc = b if acc.size.length() < 0.0000001 else acc.merge(b)
	for c in n.get_children():
		acc = _merge(c, t, acc, false)
	return acc


static func person(spec: Dictionary, s: float = 1.0) -> Node3D:
	## A person, dressed by a Dress.spec_for spec: the realistic figure
	## (Human.gd, about 1.8 m) at Medium graphics and up, the Kenney figure
	## (drawn at half size, big head shrunk) at Low or before the import has
	## run. Dress.dress(model, spec) then adds what they wear and hold.
	var H := preload("res://scripts/actors/Human.gd")
	if style != "kenney" and H.available():
		var h: Node3D = H.make(preload("res://scripts/world/Dress.gd").human_spec(spec))
		h.scale = Vector3.ONE * s
		return h
	var ks := scene(KENNEY + "mini-dungeon/character-human.glb")
	var k: Node3D = ks.instantiate() if ks else Node3D.new()
	k.scale = Vector3.ONE * 2.0 * s
	var g = Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	if g:
		g.shrink_head(k)
	return k
