extends Node3D
## Something a side quest sent you to find (round 52) -- a satchel, a mark on
## a wall, a relic on a little plinth, a plant. A gold diamond floats over it
## once you're near enough to matter (it shows through walls, the way a
## mainstream quest marker does). Press E: it's yours, and the quest moves on.
## Also marks a quest's named foe (a diamond over its head).

var level
var cell := Vector2i.ZERO
var qid := ""
var item := ""
var what := "something"
var look := "satchel"
var _marker: Label3D
var _t := 0.0

const MARK_RANGE := 34.0


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	qid = str(args.get("qid", ""))
	item = str(args.get("item", ""))
	what = str(args.get("what", "something"))
	look = str(args.get("look", "satchel"))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("quest_object")
	add_to_group("fog_exempt")
	var Art := preload("res://scripts/core/Art.gd")
	match look:
		"mark":
			var st: Node3D = Art.make("mini-dungeon/stones.glb")
			st.scale = Vector3.ONE * 1.2
			add_child(st)
			_glow_disc(Color(1.0, 0.85, 0.45))
		"relic":
			var col: Node3D = Art.make("mini-dungeon/column.glb")
			col.scale = Vector3(1.0, 0.45, 1.0)
			add_child(col)
			var pt: Node3D = Art.make("mini-dungeon/potion.glb")
			pt.position = Vector3(0, 1.0, 0)
			pt.scale = Vector3.ONE * 1.4
			add_child(pt)
			_glow_disc(Color(0.6, 0.9, 1.0))
		"herb":
			var pl: Node3D = Art.make("nature-kit/plant_bushDetailed.glb")
			pl.scale = Vector3.ONE * 1.1
			add_child(pl)
			_glow_disc(Color(0.7, 1.0, 0.6))
		_:
			var ch: Node3D = Art.make("mini-dungeon/chest.glb")
			ch.scale = Vector3.ONE * 1.1
			ch.rotation.y = randf() * TAU
			add_child(ch)
			_glow_disc(Color(1.0, 0.85, 0.45))
	_marker = marker(self, 2.2)


static func marker(n: Node3D, height: float) -> Label3D:
	## the gold diamond: through walls, bobbing a little, only when you're near
	var m := Label3D.new()
	m.name = "QuestMarker"
	m.text = "◆"
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.pixel_size = 0.012
	m.font_size = 48
	m.outline_size = 10
	m.outline_modulate = Color(0.15, 0.08, 0.0, 0.9)
	m.modulate = Color(1.0, 0.82, 0.3) * 1.4
	m.position = Vector3(0, height, 0)
	m.render_priority = 15
	m.visible = false
	n.add_child(m)
	return m


func _glow_disc(c: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 0.9
	l.omni_range = 3.0
	l.position = Vector3(0, 0.8, 0)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	if _marker == null:
		return
	var p = get_tree().get_first_node_in_group("player")
	_marker.visible = p != null and p.global_position.distance_to(global_position) < MARK_RANGE
	_marker.position.y = 2.2 + sin(_t * 2.4) * 0.12


func prompt() -> String:
	return "E: Take %s" % what


func interact(_player) -> void:
	var Q = Game.sys("quests")
	if Q == null:
		return
	remove_from_group("interactable")
	Game.sfx("pickup", 0.7)
	Q.found(qid, item)
	queue_free()
