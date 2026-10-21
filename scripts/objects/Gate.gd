extends StaticBody3D
## A locked gate across a corridor (round 32 set-pieces). Iron bars, a lock:
## it needs the floor's key -- carried by the floor's Keeper (SetPieces.gd),
## or opened by the lever puzzle. Once open it stays open (a flag), and the
## path through it is open to everyone.

var level
var cell := Vector2i.ZERO
var key_id := ""
var puzzle := false              # opened by levers, not a key
var _key := ""
var _bars: Node3D
var _shape: CollisionShape3D
var _open := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	key_id = str(args.get("key", ""))
	puzzle = bool(args.get("puzzle", false))
	_key = Game.flag_key(level.level_id, cell, "gate")


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("gate")
	_bars = Node3D.new()
	add_child(_bars)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.2, 0.2)
	m.metallic = 0.8
	m.roughness = 0.45
	var w: float = level.CELL if level else 2.0
	# which way the corridor runs: bars span the narrow way
	var along_x: bool = level != null and (level.is_free(cell + Vector2i(1, 0)) or level.is_free(cell + Vector2i(-1, 0)))
	for i in 6:
		var bar := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 2.3
		bar.mesh = cm
		bar.material_override = m
		var off := -w * 0.42 + i * (w * 0.84 / 5.0)
		bar.position = Vector3(0, 1.15, off) if along_x else Vector3(off, 1.15, 0)
		_bars.add_child(bar)
	for y in [0.3, 2.1]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.1, w * 0.9) if along_x else Vector3(w * 0.9, 0.1, 0.12)
		rail.mesh = bm
		rail.material_override = m
		rail.position = Vector3(0, y, 0)
		_bars.add_child(rail)
	var lock := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.22, 0.3, 0.22)
	lock.mesh = lm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.85, 0.7, 0.3)
	gm.metallic = 0.9
	gm.roughness = 0.3
	lock.material_override = gm
	lock.position = Vector3(0, 1.1, 0)
	_bars.add_child(lock)
	if DisplayServer.get_name() != "headless":
		var l := OmniLight3D.new()           # a lamp hung on the gate, so it reads from down the corridor
		l.light_color = Color(1.0, 0.75, 0.45)
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.position = Vector3(0, 2.4, 0)
		add_child(l)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 2.4, w) if along_x else Vector3(w, 2.4, 0.3)
	_shape.shape = box
	_shape.position = Vector3(0, 1.2, 0)
	add_child(_shape)
	if Game.has_flag(_key):
		_set_open(true, false)
	else:
		level.astar.set_point_solid(cell, true)


func is_open() -> bool:
	return _open


func _set_open(open: bool, announce: bool) -> void:
	_open = open
	if open:
		level.astar.set_point_solid(cell, false)
		_shape.set_deferred("disabled", true)
		remove_from_group("interactable")
		if announce:
			Game.sfx("door", 1.0)
			var tw := create_tween()
			tw.tween_property(_bars, "position:y", 2.6, 1.2).set_ease(Tween.EASE_IN_OUT)
		else:
			_bars.position.y = 2.6


func open_up(why: String = "") -> void:
	if _open:
		return
	Game.set_flag(_key)
	_set_open(true, true)
	Game.message.emit("The gate grinds up into the rock%s." % ((" -- " + why) if why != "" else ""))
	Game.log_event("gate_open", {"how": why})


func prompt() -> String:
	if _open:
		return ""
	if puzzle:
		return "A gate of iron bars -- no lock. Something else must open it."
	if key_id != "" and Game.count(key_id) > 0:
		return "E: Unlock the gate (%s)" % Game.item_name(key_id)
	return "A locked gate. The floor's Keeper carries the key."


func _process(_d: float) -> void:
	if not _open and Game.tester_unlocked():
		open_up("the test kit's open locks")


func interact(_player) -> void:
	if _open or puzzle:
		return
	if key_id != "" and Game.count(key_id) > 0:
		Game.remove_item(key_id, 1)
		open_up("the key turns")
	else:
		Game.message.emit("Locked. Somewhere on this floor, something holds the key.")
		Game.sfx("ui_no", 0.6)
