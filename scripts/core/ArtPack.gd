extends RefCounted
## The CC0 art packs (2026-11-06). Robert: "Yes, CC0 only" -- download free art
## (Quaternius, Poly Haven, ambientCG, Kenney) and swap it in, keeping the old
## look as the backup.
##
## Everything here is public domain (CC0 1.0): assets/cc0/README.md and
## assets/cc0/manifest.json say where each piece came from.
##
## What it changes, only when on():
##   - houses: a real timber-and-plaster or brick house built over each block of
##     "H" cells (Houses.gd), instead of a toy block and a gable per cell
##   - skies: a photographed sky by day (sky.gdshader's photo), picked by the
##     weather and the land, fading to the drawn sky, stars and moon at night
##   - the Lands' ground: real snow, sand, gravel, mud and leaf litter (ambientCG)
##     instead of a dungeon's stone floor tinted the land's colour
##   - props: stalls, carts, crates, anvils, cauldrons... (Art.SWAP_PACK)
## Off ("Art: the previous look" in Graphics fine-tune, Low graphics, phones):
## exactly the look from before, untouched.

const DATA := "res://data/art_pack.json"
const TEX := "res://assets/cc0/textures/"

static var force := -1          # tests: 1 = on, 0 = off, -1 = follow the setting
static var _d := {}
static var _loaded := false


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(DATA):
			var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
			if d is Dictionary:
				_d = d
	return _d


static func on() -> bool:
	if force >= 0:
		return force == 1
	var ev := OS.get_environment("DCE_ART_PACK")          # tools/screenshots: "on" / "off"
	if ev != "":
		return ev == "on"
	var Gfx := preload("res://scripts/core/Gfx.gd")
	if preload("res://scripts/core/Art.gd").style == "kenney" or Gfx.lite_art() or Gfx.small_device():
		return false
	return Gfx.art_pack() == "new"


# ---- skies --------------------------------------------------------------------------------------

static func sky_pick(look_key: String, weather_id: String, dusk: float, seed_text: String) -> String:
	## which photographed sky: at dusk a sunset; in a Land with its own air its
	## own; otherwise the weather's. "" for none.
	var d := data()
	var pool: Array = []
	if dusk > 0.45:
		pool = d.get("dusk", [])
	elif weather_id in ["storm", "rain", "fog", "snow"]:
		pool = (d.get("weather", {}) as Dictionary).get(weather_id, [])
	if pool.is_empty():
		pool = (d.get("looks", {}) as Dictionary).get(look_key, [])
	if pool.is_empty():
		pool = (d.get("weather", {}) as Dictionary).get(weather_id, (d.get("weather", {}) as Dictionary).get("clear", []))
	if pool.is_empty():
		return ""
	return str(pool[absi(hash(seed_text)) % pool.size()])


static func dress_sky(shm: ShaderMaterial, look_key: String, weather_id: String, dusk: float, seed_text: String) -> String:
	## lays the photo into the sky shader; returns the sky's name ("" = left drawn)
	if shm == null or not on():
		return ""
	var name := sky_pick(look_key, weather_id, dusk, seed_text)
	var s: Dictionary = (data().get("skies", {}) as Dictionary).get(name, {})
	var path := str(s.get("file", ""))
	if path == "" or not ResourceLoader.exists(path):
		return ""
	var tex = load(path)
	if tex == null:
		return ""
	shm.set_shader_parameter("photo", tex)
	shm.set_shader_parameter("photo_on", 1.0)
	shm.set_shader_parameter("photo_energy", float(s.get("energy", 1.0)))
	shm.set_shader_parameter("photo_sun_u", float(s.get("sun_u", 0.6)))
	return name


# ---- ground -------------------------------------------------------------------------------------

static func land(look_key: String) -> Array:
	## [ground folder, rock folder, tint] for a Land's open ground ("cc0:..." folders), [] for none
	if not on():
		return []
	var l = (data().get("land", {}) as Dictionary).get(look_key, [])
	return l if l is Array and l.size() >= 2 else []


static func surface_swap(look_key: String, which: String) -> Array:
	## a better surface for a dungeon look's floor/wall ([] = keep the look's own)
	if not on():
		return []
	var l = ((data().get("surfaces", {}) as Dictionary).get(look_key, {}) as Dictionary).get(which, [])
	return l if l is Array and l.size() >= 3 else []


static func tex_path(folder: String, which: String) -> String:
	## "cc0:acg_snow014" -> res://assets/cc0/textures/acg_snow014/<which>.jpg
	return "%s%s/%s.jpg" % [TEX, folder.trim_prefix("cc0:"), which]
