extends Node3D
## A landmark of the valley (round 26) -- one of the places Dev wrote
## (data/valley.json "landmarks", from his writing room's drafts): a name,
## a kind, where it is, what you see there, and something hidden.
##
## Built from the art kit by its kind (a ruin of broken walls, a hillside
## shrine, a hamlet's huts, a camp, a ring of dark oaks, a cave mouth, a
## pond, a stack of crags, a fallen bridge, a battlefield of old blades, an
## abandoned workshop, a tomb). E: look around -- Dev's description, and
## insight the first time. Search -- Dev's secret, and what it hid (once).

const KINDS := ["ruin", "shrine", "hamlet", "camp", "grove", "cave", "lake", "peak", "bridge", "battlefield", "workshop", "tomb"]

var level
var cell := Vector2i.ZERO
var idx := 0
var data := {}
var _headless := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	idx = int(args.get("index", 0))
	var lm: Array = Game.valley_data().get("landmarks", [])
	data = lm[idx] if idx < lm.size() else {}


func key() -> String:
	return "landmark:%s" % str(data.get("name", idx))


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	add_to_group("interactable")
	add_to_group("landmark")
	_build(str(data.get("kind", "ruin")))
	var lbl := Label3D.new()
	lbl.text = str(data.get("name", I18n.t("A place")))
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.011
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.modulate = Color(0.95, 0.9, 0.75)
	lbl.position = Vector3(0, 5.6, 0)
	add_child(lbl)


func prompt() -> String:
	return I18n.t("E: Look around %s") % data.get("name", I18n.t("this place"))


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	look(hud)


func look(hud) -> void:
	if not Game.has_flag(key()):
		Game.set_flag(key())
		Game.note_place(str(data.get("name", "")))
		Game.log_event("landmark_seen", {"name": data.get("name", "")})
	var body := "%s\n\n%s" % [data.get("where", ""), data.get("sight", "")]
	var opts := []
	if not Game.has_flag(key() + ":secret"):
		opts.append(["Search the place", func(): search(hud)])
	else:
		body += I18n.t("\n\n(What you found here: %s)") % data.get("secret", "")
	if str(data.get("kind", "")) == "shrine":
		opts.append(["Sit at the shrine", func():
			hud.close_dialog()
			var pl = get_tree().get_first_node_in_group("player")
			if pl:
				pl.start_meditating(false)
				Game.sit_aid = 1.5])
	opts.append(["Leave", hud.close_dialog])
	hud.open_dialog(str(data.get("name", "")), body, opts)


func search(hud = null) -> String:
	## the place's secret, once -- and what it was keeping
	if Game.has_flag(key() + ":secret"):
		return ""
	Game.set_flag(key() + ":secret")
	Game.log_event("landmark_secret", {"name": data.get("name", "")})
	var d := maxi(Game.depth, 1)
	var got := ""
	match str(data.get("kind", "ruin")):
		"shrine":
			Game.light_incense(1.5, 600.0)
			Game.integrate(15.0, "shrine")
			got = "The old shrine still remembers incense; you carry its calm with you (ten minutes of deeper sitting), and your swarm hums."
		"ruin", "tomb", "bridge":
			var rows: Array = Game.glimpse_rows().filter(func(r): return str(r[3]) == "")
			if not rows.is_empty():
				for aid in Game.lattice_data().get("arts", {}):
					if str(Game.technique_defs.get(aid, {}).get("name", "")) == str(rows[0][0]):
						Game.glimpse_art(str(aid), 2.0)
						break
			Game.add_item("gold", 12 * d, false)
			got = "Old marks on the stone show how someone once moved. (+%d gold, and a glimpse)" % (12 * d)
		"camp", "hamlet", "workshop":
			Game.add_item("gold", 10 * d, false)
			for id in ["iron_ore", "spirit_herb", "spirit_resin"]:
				if Game.items.has(id):
					Game.add_item(id, 1 + randi() % 2, false)
			if randf() < 0.35:
				Game.add_item("nanite_shard", 1, false)
			got = "Someone left things here and never came back for them. (+%d gold, supplies)" % (10 * d)
		"grove", "lake":
			var el := "wood" if str(data.get("kind", "")) == "grove" else "water"
			Game.attune(el, 5.0)
			for id in (["spirit_herb", "moonpetal"] if el == "wood" else ["cave_carp", "moonpetal"]):
				if Game.items.has(id):
					Game.add_item(id, 2, false)
			got = "The place gives a little of itself to you. (+%s affinity)" % el
		"cave", "peak":
			Game.add_qi(20.0 * d, data.get("name", "the place"))
			if Game.items.has("rough_jade"):
				Game.add_item("rough_jade", 1, false)
			got = "There's qi gathered here like water in a hollow, and a stone that glitters."
		"battlefield":
			Game.drop_gear(d, 0)
			got = "Under the rust, one blade is still good."
	Game.message.emit(I18n.t("SECRET: %s -- %s") % [data.get("secret", ""), got])
	if hud:
		look(hud)
	return got


# ---- how each kind of place is made ---------------------------------------------

const SIZE := 1.4   # the whole composition, so a place reads from across the valley


func _p(rel: String, at: Vector3, s: float = 2.0, yaw: float = 0.0, rot := Vector3.ZERO) -> Node3D:
	if not ResourceLoader.exists("res://assets/kenney/" + rel):
		return null
	var m: Node3D = preload("res://scripts/core/Art.gd").make(rel, int(at.x * 7 + at.z * 3))
	m.position = at * SIZE
	m.scale = Vector3.ONE * s * SIZE
	m.rotation = Vector3(rot.x, yaw, rot.z)
	add_child(m)
	return m


func _glow(c: Color, e: float, at := Vector3(0, 1.5, 0), r := 6.0) -> void:
	if _headless:
		return
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = e
	l.omni_range = r * SIZE
	l.position = at * SIZE
	add_child(l)


func _build(kind: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key())
	match kind:
		"ruin":
			_p("fantasy-town-kit/wall-broken.glb", Vector3(-2, 0, -1), 2.0, 0.3)
			_p("fantasy-town-kit/wall-broken.glb", Vector3(2, 0, -2), 2.0, -0.5)
			_p("fantasy-town-kit/pillar-stone.glb", Vector3(-3, 0, 2), 2.0)
			_p("nature-kit/statue_columnDamaged.glb", Vector3(3, 0, 1.5), 2.0, 1.0)
			_p("mini-dungeon/rocks.glb", Vector3(0, 0, 1), 1.6)
		"shrine":
			_p("fantasy-town-kit/pillar-stone.glb", Vector3(-1.4, 0, 0), 2.0)
			_p("fantasy-town-kit/pillar-stone.glb", Vector3(1.4, 0, 0), 2.0)
			_p("fantasy-town-kit/roof-point.glb", Vector3(0, 2.2, 0), 2.4)
			_p("nature-kit/campfire_stones.glb", Vector3(0, 0, 0.8), 1.4)
			_glow(Color(1.0, 0.75, 0.4), 1.4, Vector3(0, 1.0, 0.8))
		"hamlet":
			for side in [-1, 1]:
				_p("fantasy-town-kit/wall-wood-block.glb", Vector3(side * 3.0, 0, -1), 2.0)
				_p("fantasy-town-kit/roof-gable.glb", Vector3(side * 3.0, 2.0, -1), 2.0)
			_p("fantasy-town-kit/cart.glb", Vector3(0, 0, 2), 2.0, 0.6)
			_p("mini-dungeon/barrel.glb", Vector3(-1.5, 0, 1.5), 2.0)
			for i in 3:
				_p("nature-kit/fence_simple.glb", Vector3(-3 + i * 2.0, 0, 3.6), 2.0)
		"camp":
			_p("nature-kit/tent_detailedOpen.glb", Vector3(0, 0, -2.2), 3.0)
			_p("nature-kit/campfire_logs.glb", Vector3(0, 0, 1), 2.0)
			_p("nature-kit/log.glb", Vector3(-1.8, 0, 1.2), 2.0, 1.2)
			_p("nature-kit/log_stack.glb", Vector3(2.2, 0, 0), 2.0)
			_glow(Color(1.0, 0.6, 0.3), 1.8, Vector3(0, 0.8, 1), 7.0)
		"grove":
			for i in 6:
				var a := TAU * i / 6.0
				_p("nature-kit/tree_oak_dark.glb", Vector3(cos(a) * 4.0, 0, sin(a) * 4.0), 2.8, rng.randf() * TAU)
			_p("nature-kit/statue_ring.glb", Vector3.ZERO, 2.0)
			_glow(Color(0.45, 1.0, 0.7), 1.2)
		"cave":
			_p("nature-kit/cliff_cave_rock.glb", Vector3(0, 0, -1), 2.6)
			_p("nature-kit/rock_largeA.glb", Vector3(-3.4, 0, 0), 2.4)
			_p("nature-kit/rock_largeB.glb", Vector3(3.4, 0, 0.5), 2.4)
			_glow(Color(0.5, 0.6, 1.0), 0.9, Vector3(0, 1.0, -0.5))
		"lake":
			_p("nature-kit/lily_large.glb", Vector3(-1.2, 0.05, -4.0), 2.0)
			_p("nature-kit/lily_small.glb", Vector3(1.0, 0.05, -4.6), 2.0)
			_p("nature-kit/bridge_woodNarrow.glb", Vector3(0, 0, 0.8), 2.0)
			_glow(Color(0.5, 0.8, 1.0), 0.8, Vector3(0, 1.0, -2.0))
		"peak":
			_p("nature-kit/rock_tallA.glb", Vector3(-1.5, 0, 0), 3.0)
			_p("nature-kit/rock_tallC.glb", Vector3(1.5, 0, -0.5), 3.2)
			_p("nature-kit/rock_tallE.glb", Vector3(0, 0, -2), 3.6)
			_p("mini-dungeon/banner.glb", Vector3(0.4, 0, 1.6), 2.0)
		"bridge":
			_p("nature-kit/bridge_side_stone.glb", Vector3(-1.5, 0, 0), 2.0, 0.1, Vector3(0, 0, 0.12))
			_p("nature-kit/bridge_center_stone.glb", Vector3(1.5, 0, 0.3), 2.0, -0.2, Vector3(0.1, 0, -0.2))
			_p("fantasy-town-kit/pillar-stone.glb", Vector3(-3.5, 0, 1), 2.0)
			_p("nature-kit/statue_head.glb", Vector3(3, 0, 2), 2.0, 2.3)
		"battlefield":
			for i in 9:
				var at := Vector3(rng.randf_range(-4.0, 4.0), 0.5, rng.randf_range(-3.5, 3.5))
				_p("mini-dungeon/weapon-sword.glb", at, 2.8, rng.randf() * TAU, Vector3(rng.randf_range(0.5, 1.0), 0, 0))
			for i in 4:
				_p("mini-dungeon/shield-round.glb" if i % 2 == 0 else "mini-dungeon/shield-rectangle.glb",
					Vector3(rng.randf_range(-3.5, 3.5), 0.1, rng.randf_range(-3, 3)), 2.4, rng.randf() * TAU, Vector3(-PI / 2, 0, 0))
			_p("fantasy-town-kit/banner-red.glb", Vector3(2.8, 0, -2.8), 2.0, 0.4, Vector3(0, 0, 0.35))
			_p("fantasy-town-kit/banner-green.glb", Vector3(-3.2, 0, -2.2), 2.0, -0.6, Vector3(0.3, 0, -0.25))
			_p("fantasy-town-kit/cart.glb", Vector3(-1.5, 0, 2.8), 2.0, 2.2, Vector3(0, 0, 0.45))
			_p("fantasy-town-kit/wheel.glb", Vector3(1.2, 0.05, 3.0), 2.0, 0.7, Vector3(PI / 2, 0, 0))
			_p("mini-dungeon/rocks.glb", Vector3(0.5, 0, -0.5), 1.8)
			_glow(Color(1.0, 0.45, 0.35), 0.5, Vector3(0, 1.2, 0))
		"workshop":
			_p("mini-dungeon/table.glb", Vector3(0, 0, 0), 2.0)
			_p("mini-dungeon/wood-structure.glb", Vector3(-2.5, 0, -1.5), 2.0)
			_p("fantasy-town-kit/chimney-base.glb", Vector3(2.5, 0, -1.5), 2.0)
			_p("mini-dungeon/barrel.glb", Vector3(2.2, 0, 1.5), 2.0)
			_p("mini-dungeon/pot.glb", Vector3(-0.3, 1.05, 0), 0.9)
		"tomb":
			_p("nature-kit/statue_obelisk.glb", Vector3(0, 0, -1.5), 2.4)
			_p("nature-kit/statue_columnDamaged.glb", Vector3(-2.5, 0, 0), 2.0)
			_p("nature-kit/statue_head.glb", Vector3(2.5, 0, 0.5), 2.0)
			_p("mini-dungeon/stones.glb", Vector3(0, 0, 1.5), 1.6)
			_glow(Color(0.7, 0.75, 1.0), 0.7)
		_:
			_p("nature-kit/statue_obelisk.glb", Vector3.ZERO, 2.0)
