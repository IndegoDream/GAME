extends SceneTree
## The CC0 art pack (2026-11-06): everything it points at is there, it only
## changes looks (the same solid cells and collision boxes with it on or off),
## and "the previous look" really is the old look.
##   godot --headless --path . --script res://tools/art_pack_check.gd

var _pass := 0
var _fail := 0
var _f := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _process(_d: float) -> bool:
	_f += 1
	if _f < 2:
		return false
	var game = root.get_node("Game")
	game.playlog_path = "user://tool_playlog.jsonl"
	game.save_path = "user://art_pack_check_save.json"
	game.new_game()
	var AP := load("res://scripts/core/ArtPack.gd")
	var Art := load("res://scripts/core/Art.gd")
	var H := load("res://scripts/world/Houses.gd")
	var Look := load("res://scripts/world/Look.gd")
	var C := load("res://scripts/actors/Critter.gd")
	var M := load("res://scripts/fx/Motes.gd")
	var Gfx := load("res://scripts/core/Gfx.gd")
	var keep_style: String = Art.style
	Art.style = "realistic"

	# ---- what the pack points at is all there
	var d: Dictionary = AP.data()
	for k in ["skies", "weather", "dusk", "looks", "land", "surfaces"]:
		check("art_pack.json has " + k, d.has(k))
	for s in d.get("skies", {}):
		check("sky file %s" % s, ResourceLoader.exists(str(d["skies"][s]["file"])), d["skies"][s]["file"])
	var names: Array = d.get("skies", {}).keys()
	for w in d.get("weather", {}):
		for s2 in d["weather"][w]:
			check("weather %s sky %s is known" % [w, s2], str(s2) in names)
	for s3 in d.get("dusk", []) + _flat(d.get("looks", {})):
		check("sky %s is known" % s3, str(s3) in names)
	var folders := []
	for lk in d.get("land", {}):
		folders.append(str(d["land"][lk][0]))
		folders.append(str(d["land"][lk][1]))
	for sk in d.get("surfaces", {}):
		for which in d["surfaces"][sk]:
			folders.append(str(d["surfaces"][sk][which][0]))
	for fo in folders:
		var p: String = AP.tex_path(fo, "albedo")
		check("texture %s" % fo, ResourceLoader.exists(p) or FileAccess.file_exists(p), p)
	AP.force = 1
	for w2 in ["clear", "rain", "storm", "fog", "heat", "snow", "leaves"]:
		check("a sky for %s weather" % w2, AP.sky_pick("village", w2, 0.0, "x") in names)
	check("a sunset sky at dusk", AP.sky_pick("village", "clear", 0.8, "x") in d.get("dusk", []))
	check("the frost Land's own sky", AP.sky_pick("frost", "clear", 0.0, "x") in d["looks"]["frost"])

	# ---- houses: every block of house cells gets a roof the kit has (or the old block)
	check("the village kit is imported", H.available())
	var bad := []
	for w3 in range(1, 8):
		for h3 in range(1, 11):
			var r := Rect2i(0, 0, w3, h3)
			var parts: Array = H.fit(r)
			var cells := 0
			for pr in parts:
				var rr: Rect2i = pr
				cells += rr.size.x * rr.size.y
				if not H.roofable(rr) and mini(rr.size.x, rr.size.y) > 1:
					bad.append("%dx%d->%dx%d" % [w3, h3, rr.size.x, rr.size.y])
			if cells != w3 * h3:
				bad.append("%dx%d lost cells" % [w3, h3])
	check("every house shape splits into roofable houses", bad.is_empty(), bad)
	var hm: Dictionary = H.make(Rect2i(0, 0, 3, 4), Vector2i(0, 1), 5, func(c): return Vector3(c.x * 2.0, 0, c.y * 2.0))
	check("a house is one mesh with a few surfaces", hm["node"] is MeshInstance3D and hm["node"].mesh.get_surface_count() >= 4 and hm["node"].mesh.get_surface_count() <= 10, hm["node"].mesh.get_surface_count())
	hm["node"].free()

	# ---- the same village with the pack on and off: same solid cells, same collision, different looks
	var on: Dictionary = _build("village", 1)
	var off: Dictionary = _build("village", 0)
	check("pack on: the village's houses are built (%d)" % on["houses"], on["houses"] >= 30)
	check("pack off: no built houses", off["houses"] == 0)
	check("pack on: no toy gables left on full houses", on["gables"] < off["gables"] / 4, "%d vs %d" % [on["gables"], off["gables"]])
	check("same collision either way (%d bodies)" % on["bodies"], on["bodies"] == off["bodies"], "%d vs %d" % [on["bodies"], off["bodies"]])
	check("same solid cells either way", on["solid"] == off["solid"], "%d vs %d" % [on["solid"], off["solid"]])
	check("pack on: herds graze the village (%d)" % on["livestock"], on["livestock"] >= 4)
	check("pack off: no herds", off["livestock"] == 0)
	check("pack on: the smith and alchemist have their tools (%d)" % on["workplace"], on["workplace"] >= 2)
	check("pack off: no extra props", off["workplace"] == 0)
	check("ground tufts drawn in batches (%d tufts, %d draws)" % [on["deco"], on["batches"]], on["deco"] > 100 and on["batches"] > 0 and on["batches"] < on["deco"] / 2)
	check("no tuft left as its own model", on["loose_tufts"] == 0, on["loose_tufts"])
	# the Lands' rock edges: photo boulders (batched), same collision as the old blocks
	var lon: Dictionary = _build("frontier:stormcliffs", 1)
	var loff: Dictionary = _build("frontier:stormcliffs", 0)
	check("pack on: the Land's edges are rock (%d crags)" % lon["crags"], lon["crags"] > 500)
	check("pack off: no crags", loff["crags"] == 0)
	check("the Land's collision is the same either way (%d)" % lon["bodies"], lon["bodies"] == loff["bodies"], "%d vs %d" % [lon["bodies"], loff["bodies"]])
	for rk in ["boulder_01_lo", "namaqualand_boulder_02_lo", "rock_moss_set_01_lo", "rock_moss_set_02_lo", "rock_07_lo"]:
		check("low-poly rock %s is there" % rk, ResourceLoader.exists("res://assets/cc0/rocks/%s.gltf" % rk))
	var city: Dictionary = _build("city", 1)
	check("the Common City's houses are built (%d)" % city["houses"], city["houses"] >= 150)

	# ---- props, animals, smoke, surfaces follow the switch
	AP.force = 1
	check("pack on: market stalls take the kit's stall", Art.stand_in("fantasy-town-kit/stall.glb", 0).begins_with("pk:"), Art.stand_in("fantasy-town-kit/stall.glb", 0))
	for rel in Art.SWAP_PACK:
		for id in Art.SWAP_PACK[rel]:
			check("stand-in %s is there" % id, Art.scene(Art.real_path(str(id))) != null, Art.real_path(str(id)))
	for k in C.STOCK:
		check("livestock %s is there" % k, C.livestock_ok(k))
	for mk in M.PACK_FX:
		check("pack on: %s has the drawn particle" % mk, M.pack_texture(mk) != null)
	check("pack on: the frost floor is snow", str(Look.get_look({"look": "frost"})["floor"][0]).begins_with("cc0:"))
	AP.force = 0
	check("pack off: market stalls keep the old look", Art.stand_in("fantasy-town-kit/stall.glb", 0) == "")
	check("pack off: no drawn particles", M.pack_texture("smoke") == null)
	check("pack off: the frost floor is the old stone", str(Look.get_look({"look": "frost"})["floor"][0]) == "castle_brick_01")
	check("pack off: the old look table is untouched", str(Look.LOOKS["frost"]["floor"][0]) == "castle_brick_01")
	AP.force = -1
	Art.style = "kenney"
	check("Low graphics never takes the pack", not AP.on())
	Art.style = keep_style

	# ---- pets wear their barding
	for bid in ["hide_barding", "iron_barding", "jade_barding", "spiritsilk_barding"]:
		var b = load("res://scripts/actors/Beast.gd").build("wolf", Color(0.5, 0.45, 0.4))
		var before: int = b.find_children("*", "MeshInstance3D", true, false).size()
		var ok: bool = b.barding(bid, 2)
		var after: int = b.find_children("*", "MeshInstance3D", true, false).size()
		check("a wolf wears %s (%d more pieces)" % [bid, after - before], ok and after > before + 3)
		b.free()
	# every role grows its own body at fierce and spirit beast
	var roles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menagerie.json")).get("roles", {})
	var kinds := {}
	for role in roles:
		var bb = load("res://scripts/actors/Beast.gd").build("wolf", Color(0.5, 0.45, 0.4))
		var n0: int = bb.find_children("*", "MeshInstance3D", true, false).size()
		var none: String = bb.role_form(str(role), 1, Color(0.4, 0.8, 1.0))
		var k: String = bb.role_form(str(role), 3, Color(0.4, 0.8, 1.0))
		var n1: int = bb.find_children("*", "MeshInstance3D", true, false).size()
		check("role %s: nothing before fierce, its own body after (%s, +%d)" % [role, k, n1 - n0], none == "" and k != "" and n1 > n0 + 1)
		kinds[k] = true
		bb.free()
	check("the roles grow 8 different bodies (%d)" % kinds.size(), kinds.size() >= 8)
	var b2 = load("res://scripts/actors/Beast.gd").build("boar", Color(0.5, 0.45, 0.4))
	check("not armour -> nothing worn", not b2.barding("iron_sword", 1))
	b2.free()

	# ---- the setting
	var was: String = Gfx.art_pack()
	var nx: String = Gfx.next_art_pack()
	check("the setting turns", nx != was and nx in Gfx.ART_PACKS)
	Gfx.next_art_pack()
	check("and turns back", Gfx.art_pack() == was)

	print("ART PACK CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true


func _flat(dd: Dictionary) -> Array:
	var out := []
	for k in dd:
		out.append_array(dd[k])
	return out


func _build(id: String, pack: int) -> Dictionary:
	var AP := load("res://scripts/core/ArtPack.gd")
	AP.force = pack
	var game = root.get_node("Game")
	var l = load("res://scripts/world/Level.gd").new()
	l.build(game.load_level_def(id))
	root.add_child(l)
	var bodies: int = l.find_children("*", "StaticBody3D", true, false).size()
	var gables := 0
	var loose := 0
	for n in l.get_children():
		var sp: String = n.scene_file_path
		if sp.ends_with("roof-gable.glb"):
			gables += 1
		if str(n.name).begins_with("Art_flower") or str(n.name).begins_with("Art_grass_medium"):
			loose += 1
	var livestock := 0
	for n2 in l.get_children():
		if n2.get_script() != null and str(n2.get_script().resource_path).ends_with("Critter.gd") and str(n2.get("kind")) in ["cow", "horse", "sheep", "pig", "llama"]:
			livestock += 1
	var solid := 0
	for y in l.height:
		for x in l.width:
			if not l.is_free(Vector2i(x, y)):
				solid += 1
	var out := {"houses": l.houses_built, "gables": gables, "bodies": bodies, "solid": solid, "livestock": livestock,
		"workplace": l.workplace_props, "crags": l.crag_count, "deco": l.deco_count, "batches": l.deco_batches, "loose_tufts": loose}
	l.queue_free()
	AP.force = -1
	return out
