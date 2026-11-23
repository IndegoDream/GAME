extends Node3D
## Round 188: the Empty Seat in the valley (Valley.OWN_SEAT) -- an old walled compound waiting for a master. Its board
## at the gate (E) opens menu > Guild > Sect: what founding takes, or your sect. Once you found one (OwnSect.gd) the
## seat flies your colours, its hall is your sect's hall (SectHall.gd, placed by Level like every sect's), and up to
## six of your disciples train in the yard. Renown can dress it further: a lantern row, a founder's statue, tall banners.

var level
var cell := Vector2i.ZERO
var site := {}
var _headless := false
const CELL := 2.0


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	site = args.get("site", {})


class Board extends Node3D:
	## the board is what you walk up to (E)
	var site_node

	func prompt() -> String:
		return site_node.prompt()

	func interact(p) -> void:
		site_node.interact(p)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	add_to_group("own_sect_site")
	var founded := bool(site.get("founded", false))
	var col := _color()
	# the board, just inside the gate
	var board := Board.new()
	board.site_node = self
	board.add_to_group("interactable")
	board.name = "Board"
	board.position = Vector3(5.0, 0, 11.0)
	add_child(board)
	_box(board, Vector3(0.18, 1.8, 0.18), Vector3(-0.7, 0.9, 0), Color(0.4, 0.3, 0.2))
	_box(board, Vector3(0.18, 1.8, 0.18), Vector3(0.7, 0.9, 0), Color(0.4, 0.3, 0.2))
	_box(board, Vector3(1.8, 1.0, 0.08), Vector3(0, 1.45, 0), col.darkened(0.55) if founded else Color(0.45, 0.4, 0.32))
	var lb := Label3D.new()
	lb.name = "Title"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.012
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = col if founded else Color(0.85, 0.82, 0.72)
	lb.position = Vector3(0, 3.0, 0)
	lb.visibility_range_end = 60.0
	if founded:
		lb.text = "%s\n%s" % [str(site.get("name", "")), I18n.t("Master %s") % (Game.char_name if Game.char_name != "" else I18n.t("you"))]
	else:
		lb.text = "%s\n%s" % [I18n.t("THE EMPTY SEAT"), I18n.t("an old sect's compound, waiting for a master")]
	board.add_child(lb)
	if not founded:
		return
	# colours on the gate and before the hall
	for p in [Vector3(-3.0, 0, 13.0), Vector3(3.0, 0, 13.0), Vector3(-7.0, 0, -6.0), Vector3(7.0, 0, -6.0)]:
		_banner(p, col, 4.2)
	var decor: Array = site.get("decor", [])
	if "hall_banners" in decor:
		for p2 in [Vector3(-12.0, 0, 0.0), Vector3(12.0, 0, 0.0), Vector3(-12.0, 0, 8.0), Vector3(12.0, 0, 8.0)]:
			_banner(p2, col, 6.5)
	if "hall_statue" in decor:
		_box(self, Vector3(1.6, 0.8, 1.6), Vector3(0, 0.4, 3.0), Color(0.55, 0.55, 0.58))
		var st: Node3D = Node3D.new()
		if not _headless:
			st = preload("res://scripts/core/Art.gd").person(preload("res://scripts/world/Dress.gd").spec_for(Game.char_name, "sect", {}), 1.5)
		st.position = Vector3(0, 0.8, 3.0)
		_stone(st)
		add_child(st)
		for ap in st.find_children("*", "AnimationPlayer", true, false):      # (a statue stands, it doesn't T-pose)
			var a := ap as AnimationPlayer
			for want in ["idle", "Idle", "meditate", "sit"]:
				if a.has_animation(want):
					a.play(want)
					a.seek(0.4, true)
					a.pause()
					break
	if "hall_lanterns" in decor and not _headless:
		for i in 6:
			var x := -10.0 + 4.0 * i
			_box(self, Vector3(0.12, 2.2, 0.12), Vector3(x, 1.1, 9.5), Color(0.25, 0.2, 0.15))
			var lamp := _box(self, Vector3(0.45, 0.55, 0.45), Vector3(x, 2.4, 9.5), Color(1.0, 0.7, 0.35))
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(1.0, 0.65, 0.3)
			lm.emission_enabled = true
			lm.emission = Color(1.0, 0.6, 0.25)
			lm.emission_energy_multiplier = 2.0
			lamp.material_override = lm
			if i % 2 == 0:
				var ol := OmniLight3D.new()
				ol.light_color = Color(1.0, 0.7, 0.4)
				ol.omni_range = 7.0
				ol.light_energy = 0.9
				ol.distance_fade_enabled = true
				ol.distance_fade_begin = 50.0
				ol.distance_fade_length = 10.0
				ol.position = Vector3(x, 2.6, 9.5)
				add_child(ol)
	_spawn_disciples.call_deferred()        # (the level is still putting its children in)


func _spawn_disciples() -> void:
	## the disciples in the yard (up to six; the rest are inside, or out on errands)
	if level != null and is_inside_tree():
		var ds: Array = site.get("disciples", [])
		for i in ds.size():
			var d: Dictionary = ds[i]
			var at := global_position + Vector3(-7.5 + 3.0 * (i % 6), 0, 2.0 + 2.5 * float(i / 6))
			var npc = level._spawn_script("res://scripts/actors/NPC.gd", at, {"cell": level.world_to_cell(at), "role": "villager", "name": str(d["name"]),
				"line": I18n.t("Master! I've been practising."), "def": {"stays": true, "wander": false, "sect": "own",
				"persona": I18n.t("%s, a young %s disciple of the %s -- the sect the player founded and leads as master. Eager, respectful, a little in awe of the master.") % [str(d["name"]), I18n.t(str(d.get("el", ""))), str(site.get("name", ""))]}})
			if npc != null:
				npc.add_to_group("own_disciple")


func _color() -> Color:
	var c = site.get("color", [0.9, 0.8, 0.5])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _box(parent: Node, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	if not _headless:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		mi.material_override = m
	parent.add_child(mi)
	return mi


func _banner(at: Vector3, c: Color, h: float) -> void:
	_box(self, Vector3(0.14, h, 0.14), at + Vector3(0, h * 0.5, 0), Color(0.3, 0.22, 0.15))
	_box(self, Vector3(0.9, h * 0.45, 0.04), at + Vector3(0.5, h * 0.7, 0), c)


func _stone(n: Node) -> void:
	if _headless:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.62, 0.64)
	m.roughness = 0.95
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m


func prompt() -> String:
	if bool(site.get("founded", false)):
		return I18n.t("E: The board of the %s (your sect)") % str(site.get("name", ""))
	return I18n.t("E: The Empty Seat's board -- found your own sect here")


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or hud._hub == null:
		return
	hud._hub.show_page("Guild")
	if hud._hub.guild_page != null:
		hud._hub.guild_page.open_tab("Sect")
