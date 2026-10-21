extends RefCounted
## How a place LOOKS (Robert, 2026-10-02: "can we begin to add more texture
## and detail to the world"). Every floor used to be the same flat tiles and
## the same plain walls -- the Crimson Canopy looked exactly like the Ember
## Forges. Now each region has a look: real stone/earth/moss surfaces (CC0
## photo-scanned textures from Poly Haven, in assets/textures/), its own
## tint, its own clutter along the walls, its own drifting particles, its
## own light colour, and its own kinds of little scenes (Vignette.gd) and
## small creatures (Critter.gd).
##
## A level picks its look by "look" in its file, else by its forged region
## ("forged": {"region": ...}), else by words in its name, else by theme.
## Add a region in data/forge_regions.json? Add a look here with the same
## key and the forge's floors pick it up.

const TEX := "res://assets/textures/"

## surface: [texture folder, tint, uv scale (metres per repeat)]
## clutter: [model path, scale, weight] scattered along walls (looks only)
## motes: "embers" | "spores" | "leaves" | "dust" | "drips" | "sparks" | "snow" | "glints" | "ash" | ""
## critters: kinds for Critter.gd; vignettes: kinds for Vignette.gd
const LOOKS := {
	"warrens": {"floor": ["stony_dirt_path", [0.85, 0.8, 0.72], 3.0], "wall": ["old_stone_wall", [0.8, 0.76, 0.72], 3.0],
		"clutter": [["mini-dungeon/rocks.glb", 1.0, 3], ["mini-dungeon/stones.glb", 1.4, 3], ["mini-dungeon/barrel.glb", 1.4, 1], ["mini-dungeon/pot.glb", 1.6, 1], ["nature-kit/mushroom_tan.glb", 2.0, 1]],
		"motes": "dust", "torch": [1.0, 0.68, 0.35], "critters": ["rat", "rat", "bat"], "vignettes": ["camp", "cache", "fallen", "battle"]},
	"crypt": {"floor": ["castle_brick_01", [0.7, 0.68, 0.66], 2.5], "wall": ["old_stone_wall", [0.62, 0.62, 0.66], 3.0],
		"clutter": [["mini-dungeon/stones.glb", 1.4, 3], ["nature-kit/pot_small.glb", 2.0, 2], ["nature-kit/statue_head.glb", 1.4, 1], ["mini-dungeon/rocks.glb", 1.0, 2]],
		"motes": "dust", "torch": [0.75, 0.85, 1.0], "critters": ["rat", "bat", "bat"], "vignettes": ["fallen", "shrine", "fallen", "cache"]},
	"drowned": {"floor": ["mossy_cobblestone", [0.62, 0.78, 0.82], 2.5], "wall": ["mossy_stone_wall", [0.6, 0.75, 0.8], 3.0],
		"clutter": [["nature-kit/stone_smallA.glb", 2.0, 2], ["nature-kit/lily_small.glb", 2.0, 1], ["nature-kit/stone_smallFlatA.glb", 2.0, 2], ["nature-kit/pot_large.glb", 1.4, 1], ["nature-kit/hanging_moss.glb", 1.6, 2]],
		"motes": "drips", "torch": [0.55, 0.85, 1.0], "critters": ["rat", "moth"], "vignettes": ["fallen", "cache", "shrine", "camp"]},
	"sanctum": {"floor": ["castle_brick_01", [0.6, 0.7, 0.85], 2.0], "wall": ["old_stone_wall", [0.55, 0.65, 0.85], 2.5],
		"clutter": [["nature-kit/statue_obelisk.glb", 1.0, 1], ["nature-kit/statue_columnDamaged.glb", 1.0, 1], ["mini-dungeon/stones.glb", 1.4, 2], ["mini-dungeon/rocks.glb", 1.0, 1]],
		"motes": "glints", "torch": [0.5, 0.8, 1.0], "glow": [0.35, 0.8, 1.0], "critters": ["moth"], "vignettes": ["shrine", "fallen", "battle", "cache"]},
	"grove": {"floor": ["forest_floor", [0.7, 0.85, 0.65], 3.0], "wall": ["mossy_stone_wall", [0.65, 0.8, 0.6], 3.0],
		"clutter": [["nature-kit/plant_bush.glb", 1.6, 3], ["nature-kit/grass_large.glb", 2.0, 3], ["nature-kit/stump_old.glb", 1.6, 1], ["nature-kit/log.glb", 1.4, 1], ["nature-kit/mushroom_redGroup.glb", 2.0, 1], ["nature-kit/hanging_moss.glb", 1.8, 2]],
		"motes": "spores", "torch": [1.0, 0.8, 0.45], "critters": ["moth", "rat"], "vignettes": ["camp", "fallen", "shrine", "cache"]},
	"canopy": {"floor": ["forest_floor", [0.85, 0.68, 0.62], 3.0], "wall": ["mossy_stone_wall", [0.8, 0.55, 0.5], 3.0],
		"clutter": [["nature-kit/plant_bushLarge.glb", 1.4, 2], ["nature-kit/grass_leafsLarge.glb", 2.0, 3], ["nature-kit/stump_roundDetailed.glb", 1.4, 1], ["nature-kit/flower_redA.glb", 2.2, 2], ["nature-kit/hanging_moss.glb", 1.8, 2]],
		"motes": "leaves", "torch": [1.0, 0.6, 0.45], "critters": ["moth", "bat"], "vignettes": ["camp", "fallen", "cache", "battle"]},
	"fungal": {"floor": ["forest_floor", [0.75, 0.8, 0.6], 2.5], "wall": ["mossy_stone_wall", [0.7, 0.72, 0.55], 3.0],
		"clutter": [["nature-kit/mushroom_tanGroup.glb", 2.4, 3], ["nature-kit/mushroom_redTall.glb", 2.4, 2], ["nature-kit/mushroom_tanTall.glb", 2.6, 2], ["nature-kit/stone_smallB.glb", 2.0, 1]],
		"motes": "spores", "torch": [0.8, 1.0, 0.55], "glow": [0.6, 1.0, 0.55], "critters": ["moth", "moth", "rat"], "vignettes": ["fallen", "camp", "cache", "shrine"]},
	"forge": {"floor": ["rock_face", [0.72, 0.56, 0.48], 3.0], "wall": ["rock_face", [0.72, 0.5, 0.42], 3.5],
		"clutter": [["mini-dungeon/rocks.glb", 1.0, 3], ["nature-kit/rock_smallA.glb", 2.0, 2], ["mini-dungeon/barrel.glb", 1.4, 1], ["mini-dungeon/wood-support.glb", 1.4, 1]],
		"motes": "embers", "torch": [1.0, 0.5, 0.2], "glow": [1.0, 0.35, 0.1], "critters": ["rat"], "vignettes": ["battle", "fallen", "cache", "camp"]},
	"barrows": {"floor": ["stony_dirt_path", [0.95, 0.75, 0.55], 3.0], "wall": ["castle_brick_01", [0.85, 0.6, 0.45], 2.5],
		"clutter": [["nature-kit/pot_large.glb", 1.4, 2], ["nature-kit/pot_small.glb", 2.0, 2], ["nature-kit/statue_head.glb", 1.4, 1], ["nature-kit/statue_columnDamaged.glb", 1.0, 1], ["mini-dungeon/stones.glb", 1.4, 2]],
		"motes": "dust", "torch": [1.0, 0.72, 0.4], "critters": ["rat", "bat"], "vignettes": ["shrine", "fallen", "battle", "cache"]},
	"swordgrave": {"floor": ["stony_dirt_path", [0.68, 0.7, 0.75], 3.0], "wall": ["old_stone_wall", [0.6, 0.65, 0.75], 3.0],
		"clutter": [["mini-dungeon/weapon-sword.glb", 1.6, 3], ["mini-dungeon/shield-round.glb", 1.4, 1], ["mini-dungeon/weapon-spear.glb", 1.6, 1], ["mini-dungeon/stones.glb", 1.4, 2]],
		"motes": "glints", "torch": [0.8, 0.85, 1.0], "critters": ["bat"], "vignettes": ["fallen", "battle", "fallen", "shrine"]},
	"cloudruins": {"floor": ["castle_brick_01", [0.92, 0.92, 0.95], 2.5], "wall": ["old_stone_wall", [0.88, 0.88, 0.92], 3.0],
		"clutter": [["nature-kit/statue_columnDamaged.glb", 1.0, 2], ["nature-kit/statue_block.glb", 1.0, 1], ["nature-kit/stone_smallFlatB.glb", 2.0, 2], ["nature-kit/grass.glb", 2.0, 2]],
		"motes": "dust", "torch": [1.0, 0.95, 0.8], "critters": ["moth"], "vignettes": ["shrine", "fallen", "cache", "camp"]},
	"storm": {"floor": ["rock_face", [0.5, 0.52, 0.62], 3.0], "wall": ["old_stone_wall", [0.45, 0.48, 0.62], 3.0],
		"clutter": [["nature-kit/rock_tallA.glb", 1.4, 2], ["mini-dungeon/rocks.glb", 1.0, 2], ["nature-kit/statue_obelisk.glb", 1.0, 1]],
		"motes": "sparks", "torch": [0.7, 0.8, 1.0], "critters": ["bat"], "vignettes": ["battle", "fallen", "shrine", "camp"]},
	"dragonspine": {"floor": ["rock_face", [0.7, 0.5, 0.4], 3.0], "wall": ["rock_face", [0.72, 0.48, 0.38], 3.5],
		"clutter": [["nature-kit/rock_largeA.glb", 1.0, 1], ["nature-kit/rock_smallB.glb", 2.0, 2], ["mini-dungeon/rocks.glb", 1.0, 2], ["nature-kit/stone_tallB.glb", 1.2, 1]],
		"motes": "embers", "torch": [1.0, 0.55, 0.25], "glow": [1.0, 0.45, 0.15], "critters": ["bat"], "vignettes": ["fallen", "battle", "camp", "cache"]},
	"starmine": {"floor": ["stony_dirt_path", [0.65, 0.6, 0.8], 3.0], "wall": ["rock_face", [0.6, 0.55, 0.78], 3.0],
		"clutter": [["mini-dungeon/wood-support.glb", 1.4, 2], ["mini-dungeon/wood-structure.glb", 1.2, 1], ["mini-dungeon/rocks.glb", 1.0, 2], ["fantasy-town-kit/cart.glb", 1.0, 1]],
		"motes": "glints", "torch": [0.85, 0.75, 1.0], "glow": [0.7, 0.55, 1.0], "critters": ["rat", "bat"], "vignettes": ["camp", "cache", "fallen", "battle"]},
	"crystal": {"floor": ["rock_face", [0.55, 0.65, 0.85], 3.0], "wall": ["rock_face", [0.5, 0.62, 0.85], 3.0],
		"clutter": [["nature-kit/stone_tallA.glb", 1.0, 2], ["nature-kit/stone_tallC.glb", 1.0, 2], ["nature-kit/stone_smallTopA.glb", 2.0, 2]],
		"motes": "glints", "torch": [0.55, 0.85, 1.0], "glow": [0.4, 0.85, 1.0], "crystals": true, "critters": ["moth", "bat"], "vignettes": ["fallen", "camp", "shrine", "cache"]},
	"frost": {"floor": ["castle_brick_01", [0.82, 0.9, 1.0], 2.5], "wall": ["old_stone_wall", [0.8, 0.88, 1.0], 3.0],
		"clutter": [["nature-kit/stone_smallA.glb", 2.0, 2], ["mini-dungeon/stones.glb", 1.4, 2], ["nature-kit/statue_block.glb", 1.0, 1]],
		"motes": "snow", "torch": [0.8, 0.9, 1.0], "critters": ["bat"], "vignettes": ["fallen", "shrine", "cache", "camp"]},
	"ash": {"floor": ["stony_dirt_path", [0.62, 0.56, 0.5], 3.0], "wall": ["rock_face", [0.55, 0.48, 0.42], 3.5],
		"clutter": [["nature-kit/rock_smallC.glb", 2.0, 2], ["nature-kit/stump_old.glb", 1.4, 1], ["mini-dungeon/rocks.glb", 1.0, 2]],
		"motes": "ash", "torch": [1.0, 0.6, 0.3], "critters": ["rat"], "vignettes": ["battle", "fallen", "camp", "cache"]},
	"clockwork": {"floor": ["castle_brick_01", [0.75, 0.68, 0.55], 2.0], "wall": ["old_stone_wall", [0.7, 0.62, 0.5], 2.5],
		"clutter": [["mini-dungeon/wood-structure.glb", 1.2, 1], ["mini-dungeon/barrel.glb", 1.4, 2], ["mini-dungeon/stones.glb", 1.4, 1]],
		"motes": "sparks", "torch": [1.0, 0.8, 0.5], "critters": ["rat"], "vignettes": ["cache", "battle", "fallen", "shrine"]},
	"mirror": {"floor": ["castle_brick_01", [0.8, 0.82, 0.9], 2.0], "wall": ["old_stone_wall", [0.78, 0.8, 0.9], 2.5],
		"clutter": [["nature-kit/statue_obelisk.glb", 1.0, 1], ["nature-kit/statue_ring.glb", 1.0, 1], ["mini-dungeon/stones.glb", 1.4, 2]],
		"motes": "glints", "torch": [0.9, 0.9, 1.0], "critters": ["moth"], "vignettes": ["shrine", "fallen", "cache", "camp"]},
	"ghostmarket": {"floor": ["mossy_cobblestone", [0.6, 0.55, 0.7], 2.5], "wall": ["old_stone_wall", [0.55, 0.5, 0.65], 3.0],
		"clutter": [["fantasy-town-kit/stall.glb", 1.0, 1], ["nature-kit/pot_small.glb", 2.0, 2], ["fantasy-town-kit/lantern.glb", 1.2, 1], ["mini-dungeon/barrel.glb", 1.4, 1]],
		"motes": "glints", "torch": [0.6, 1.0, 0.8], "glow": [0.5, 1.0, 0.75], "critters": ["moth", "rat"], "vignettes": ["cache", "shrine", "camp", "fallen"]},
	"silk": {"floor": ["old_wood_floor", [0.8, 0.78, 0.82], 2.5], "wall": ["old_stone_wall", [0.75, 0.72, 0.8], 3.0],
		"clutter": [["nature-kit/hanging_moss.glb", 1.8, 3], ["mini-dungeon/stones.glb", 1.4, 1], ["nature-kit/pot_small.glb", 2.0, 1]],
		"motes": "dust", "torch": [1.0, 0.85, 0.7], "critters": ["moth", "moth"], "vignettes": ["fallen", "cache", "camp", "shrine"]},
	# round 123: the tech frontier -- surfaces drawn in code (TechTex.gd), so these need no picture files
	"scrapfield": {"floor": ["proc_rust", [0.9, 0.82, 0.78], 3.0], "wall": ["proc_plate", [0.78, 0.8, 0.88], 3.0],
		"clutter": [["mini-dungeon/rocks.glb", 1.0, 3], ["mini-dungeon/barrel.glb", 1.4, 2], ["mini-dungeon/stones.glb", 1.4, 2]],
		"motes": "sparks", "torch": [0.6, 0.8, 1.0], "glow": [0.5, 0.8, 1.0], "critters": ["rat", "bat"], "vignettes": ["camp", "fallen", "cache", "battle"]},
	"launchpad": {"floor": ["proc_deck", [0.8, 0.84, 0.9], 2.5], "road": ["proc_deck", [0.7, 0.74, 0.8], 2.5], "wall": ["proc_hull", [0.85, 0.88, 0.95], 3.0],
		"clutter": [["mini-dungeon/barrel.glb", 1.4, 2], ["mini-dungeon/stones.glb", 1.4, 1]],
		"motes": "dust", "torch": [1.0, 0.96, 0.9], "glow": [0.9, 0.95, 1.0], "critters": ["bird", "cat"], "vignettes": ["camp", "cache", "fallen", "battle"]},
	"station": {"floor": ["proc_deck", [0.7, 0.82, 0.92], 2.5], "wall": ["proc_hull", [0.75, 0.85, 0.95], 3.0],
		"clutter": [["mini-dungeon/barrel.glb", 1.2, 1], ["nature-kit/plant_bush.glb", 1.6, 2], ["nature-kit/grass_large.glb", 2.0, 2]],
		"motes": "glints", "torch": [0.8, 0.95, 1.0], "glow": [0.55, 0.95, 1.0], "critters": ["moth"], "vignettes": ["shrine", "cache", "fallen", "camp"]},
	"regolith": {"floor": ["proc_regolith", [0.85, 0.88, 1.0], 3.0], "wall": ["proc_regolith", [0.6, 0.62, 0.7], 4.0],
		"clutter": [["mini-dungeon/rocks.glb", 1.0, 3], ["nature-kit/rock_smallC.glb", 2.0, 2]],
		"motes": "dust", "torch": [0.7, 0.8, 1.0], "glow": [0.6, 0.75, 1.0], "critters": ["bat"], "vignettes": ["fallen", "battle", "cache", "camp"]},
	"glassdune": {"floor": ["proc_glass", [1.0, 0.92, 0.78], 3.0], "wall": ["proc_glass", [0.9, 0.72, 0.55], 3.5],
		"clutter": [["mini-dungeon/rocks.glb", 1.0, 2], ["nature-kit/rock_smallA.glb", 2.0, 2]],
		"motes": "dust", "torch": [1.0, 0.8, 0.5], "glow": [1.0, 0.8, 0.45], "critters": ["bat"], "vignettes": ["fallen", "camp", "cache", "shrine"]},
	"foundry": {"floor": ["proc_slag", [1.0, 0.9, 0.85], 3.0], "wall": ["proc_plate", [0.95, 0.65, 0.5], 3.0],
		"clutter": [["mini-dungeon/barrel.glb", 1.4, 2], ["mini-dungeon/wood-structure.glb", 1.2, 1], ["mini-dungeon/rocks.glb", 1.0, 2]],
		"motes": "embers", "torch": [1.0, 0.5, 0.2], "glow": [1.0, 0.4, 0.15], "critters": ["rat"], "vignettes": ["battle", "fallen", "cache", "camp"]},
	# towns: the ground is a real surface too
	"settlement": {"floor": ["grass_ground", [0.55, 0.72, 0.62], 4.0], "road": ["mossy_cobblestone", [0.8, 0.76, 0.72], 2.5],
		"motes": "glints", "critters": ["cat", "moth"]},
	"village": {"floor": ["grass_ground", [0.85, 0.95, 0.8], 4.0], "road": ["stony_dirt_path", [0.95, 0.9, 0.82], 3.0],
		"motes": "", "critters": ["bird", "bird", "cat"]},
}

## words in a hand-made floor's name -> its look
const NAME_LOOKS := {"goblin": "warrens", "warren": "warrens", "bone": "crypt", "crypt": "crypt", "drowned": "drowned",
	"seam": "drowned", "nanite": "sanctum", "sanctum": "sanctum", "grove": "grove", "canopy": "canopy", "spore": "fungal",
	"ember": "forge", "forge": "forge", "terracotta": "barrows", "barrow": "barrows", "sword": "swordgrave",
	"cloud": "cloudruins", "thunder": "storm", "storm": "storm", "dragon": "dragonspine", "star": "starmine",
	"crystal": "crystal", "frozen": "frost", "frost": "frost", "ash": "ash", "clockwork": "clockwork", "mirror": "mirror",
	"night market": "ghostmarket", "weaver": "silk", "silk": "silk"}
const REGION_LOOKS := {"fungal": "fungal", "canopy": "canopy", "drowned": "drowned", "cloudruins": "cloudruins", "storm": "storm",
	"dragonspine": "dragonspine", "starmine": "starmine", "crystal": "crystal", "frost": "frost", "ash": "ash",
	"clockwork": "clockwork", "mirror": "mirror", "ghostmarket": "ghostmarket", "silk": "silk"}

static var detail := false   # Gfx High+: rough/AO maps on stone and earth too
static var natural := false  # Gfx Medium+: region colour only tints the stone, so the photo texture reads as real stone
static var _tex := {}       # path -> Texture2D (loaded once, shared by every level)
static var _mats := {}      # key -> Material


static func key_for(d: Dictionary) -> String:
	var theme := str(d.get("theme", "dungeon"))
	if LOOKS.has(str(d.get("look", ""))):
		return str(d["look"])
	if theme == "village" or theme == "settlement":
		return theme
	var fg = d.get("forged", {})
	if fg is Dictionary and REGION_LOOKS.has(str(fg.get("region", ""))):
		return REGION_LOOKS[str(fg["region"])]
	var nm := str(d.get("name", "")).to_lower()
	for w in NAME_LOOKS:
		if nm.contains(str(w)):
			return NAME_LOOKS[w]
	return "warrens"


static func get_look(d: Dictionary) -> Dictionary:
	return LOOKS.get(key_for(d), LOOKS["warrens"])


const OWN_TEX := "res://assets/own/textures/"
static var _own: Dictionary = {}
static var _own_loaded := false


static func _own_folder(folder: String) -> String:
	## "" unless Dev's own-texture swap is on and has a texture for this photo folder
	if not _own_loaded:
		_own_loaded = true
		var mp := "res://assets/own/map.json"
		if FileAccess.file_exists(mp):
			var d = JSON.parse_string(FileAccess.get_file_as_string(mp))
			if typeof(d) == TYPE_DICTIONARY and bool(d.get("enabled", false)) and typeof(d.get("textures")) == TYPE_DICTIONARY:
				_own = d["textures"]
	return str(_own.get(folder, ""))


static func texture(folder: String, which: String) -> Texture2D:
	## A texture from assets/textures/<folder>/<which>.jpg. Round 29: these
	## are imported now (with mipmaps), so they go into an exported build --
	## the phone version had bare white ground without them, because a
	## .gdignore'd folder is never packed. A file the import hasn't reached
	## yet is still read straight from disk, as before.
	if folder.begins_with("proc_"):
		return preload("res://scripts/world/TechTex.gd").texture(folder, which)         # round 123: drawn in code, not a picture file
	var p := "%s%s/%s.jpg" % [TEX, folder, which]
	# r115: Dev's own textures (assets/own/, drawn by the art studio). map.json says which photo folder each one
	# stands in for and whether the swap is switched on; a missing own file just falls back to the photo.
	var own := _own_folder(folder)
	if own != "":
		var op := "%s%s/%s.jpg" % [OWN_TEX, own, which]
		if ResourceLoader.exists(op) or FileAccess.file_exists(op):
			p = op
	if _tex.has(p):
		return _tex[p]
	var tex: Texture2D = null
	if ResourceLoader.exists(p):
		tex = load(p) as Texture2D
	if tex == null and FileAccess.file_exists(p):
		var img := Image.new()
		if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_tex[p] = tex
	return tex


static func surface(spec: Array, extra_dark: float = 1.0) -> Material:
	## A triplanar stone/earth material: any mesh, any size, no stretching.
	var key := "%s|%s|%s|%s|%s|%s" % [spec[0], str(spec[1]), str(spec[2]), str(extra_dark), str(detail), str(natural)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var t: Array = spec[1]
	if natural:
		# Morrowind/Skyrim: grey-brown stone that the light colours, not
		# painted stone -- the region's colour is kept, but only as a cast
		t = [lerpf(float(t[0]), 0.8, 0.6), lerpf(float(t[1]), 0.77, 0.6), lerpf(float(t[2]), 0.72, 0.6)]
	# (photo textures are darker than the old flat tiles: lift the tint so a
	# room reads at a glance, and let the texture carry the detail)
	m.albedo_color = Color(minf(float(t[0]) * 1.25, 1.0), minf(float(t[1]) * 1.25, 1.0), minf(float(t[2]) * 1.25, 1.0)) * extra_dark
	m.albedo_color.a = 1.0
	if DisplayServer.get_name() != "headless":
		var a := texture(str(spec[0]), "albedo")
		if a:
			m.albedo_texture = a
		var n := texture(str(spec[0]), "normal")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
			m.normal_scale = 1.2
		var arm := texture(str(spec[0]), "arm") if detail else null
		if arm:
			# packed AO / roughness / metal (Poly Haven's "arm"): cracks stay
			# dark, worn stone catches the light where it's smooth
			m.ao_enabled = true
			m.ao_texture = arm
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.ao_light_affect = 0.6
			m.roughness_texture = arm
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / maxf(float(spec[2]), 0.5)
	m.uv1_scale = Vector3(s, s, s)
	m.roughness = 0.92
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func color3(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback
