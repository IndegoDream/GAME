extends StaticBody3D
## A lore stone. Press E to read it. Defined in a level file's "lore":
##   "R": {"title": "The Monk's Stone", "text": "...", "teaches": "iron_skin"}
## A stone can teach a technique (data/techniques.json); one with
## "needs_realm": 1 stays unreadable -- just weathered stone -- until
## your cultivation reaches that realm. Hidden in plain sight.

var level
var cell := Vector2i.ZERO
var title := "Weathered Stone"
var text := ""
var teaches := ""
var needs_realm := 0
var _key := ""
var _glyph: MeshInstance3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	var d: Dictionary = args.get("def", {})
	title = str(d.get("title", "Weathered Stone"))
	text = str(d.get("text", ""))
	teaches = str(d.get("teaches", ""))
	needs_realm = int(d.get("needs_realm", 0))
	_key = Game.flag_key(level.level_id, cell, "lore")


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("discoverable")
	var stone = load("res://assets/kenney/nature-kit/statue_obelisk.glb").instantiate()
	stone.scale = Vector3.ONE * 2.2
	add_child(stone)
	_glyph = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	_glyph.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.9, 1.0, 0.0)
	m.emission_enabled = true
	m.emission = Color(0.4, 0.85, 1.0)
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glyph.material_override = m
	_glyph.position = Vector3(0, 2.6, 0)
	add_child(_glyph)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 2.4, 0.9)
	shape.shape = box
	shape.position = Vector3(0, 1.2, 0)
	add_child(shape)
	level.astar.set_point_solid(cell, true)
	_refresh()


func _refresh() -> void:
	var unread := not Game.lore_read.has(_key)
	var readable := Game.realm >= needs_realm
	var m: StandardMaterial3D = _glyph.material_override
	m.albedo_color.a = 0.85 if (unread and readable and teaches != "") else (0.35 if unread and readable else 0.0)


func prompt() -> String:
	if Game.realm < needs_realm:
		return "E: Examine the weathered stone"
	return "E: Read " + title


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if Game.realm < needs_realm:
		hud.open_dialog(title, "The carving is worn past reading. Something is written here -- you can feel it -- but your cultivation isn't deep enough to see it yet.\n\n(Return when you reach %s.)" % Game.realm_info(needs_realm)["name"], [["Leave it", hud.close_dialog]])
		Game.log_event("lore_locked", {"title": title})
		return
	var body := text
	var first := not Game.lore_read.has(_key)
	if first:
		Game.lore_read[_key] = true
		Game.log_event("lore_read", {"title": title, "teaches": teaches})
		Game.note_place("Read " + title)
		Game.add_qi(8.0, "lore")
	if first and Game.sys("lore"):
		var w: String = Game.sys("lore").framed("stele")          # round 42: something worth knowing, below the carving
		if w != "":
			body += "\n\n" + w
	if teaches != "" and Game.technique_defs.has(teaches):
		if Game.learn(teaches, "lore:" + title):
			body += "\n\n-- You understand. You have learned %s." % Game.technique_defs[teaches].get("name", teaches)
		elif Game.has_tech(teaches):
			body += "\n\n(You already know what this stone teaches.)"
	hud.open_dialog(title, body, [["Close", hud.close_dialog]])
	_refresh()
