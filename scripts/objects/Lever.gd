extends StaticBody3D
## A lever on a stone post (round 32 set-pieces). Three of them stand in a
## room, each a colour; a stone nearby says the order. Pull them in that
## order and the puzzle gate opens; get it wrong and the floor answers --
## everything near wakes up, and the levers reset.

var level
var cell := Vector2i.ZERO
var color_name := "red"
var color := Color(0.8, 0.2, 0.2)
var group_id := ""
var _handle: MeshInstance3D
var _pulled := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	color_name = str(args.get("color", "red"))
	color = args.get("rgb", Color(0.8, 0.2, 0.2))
	group_id = str(args.get("group", ""))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("lever")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.4)
	stone.roughness = 0.95
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.0, 0.5)
	post.mesh = bm
	post.material_override = stone
	post.position = Vector3(0, 0.5, 0)
	add_child(post)
	_handle = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 0.7
	_handle.mesh = cm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = color
	hm.emission_enabled = true
	hm.emission = color
	hm.emission_energy_multiplier = 0.8
	_handle.material_override = hm
	_handle.position = Vector3(0, 1.3, 0)
	_handle.rotation.x = -0.6
	add_child(_handle)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.0, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)
	if level and level.get("astar"):
		level.astar.set_point_solid(cell, true)
	if Game.has_flag("%s:puzzle:%s" % [level.level_id, group_id]):
		_pulled = true
		_handle.rotation.x = 0.6


func reset() -> void:
	_pulled = false
	var tw := create_tween()
	tw.tween_property(_handle, "rotation:x", -0.6, 0.3)


func prompt() -> String:
	if _pulled:
		return "The %s lever is down." % color_name
	return "E: Pull the %s lever" % color_name


func interact(_player) -> void:
	if _pulled:
		return
	_pulled = true
	var tw := create_tween()
	tw.tween_property(_handle, "rotation:x", 0.6, 0.25)
	Game.sfx("creak", 0.9)
	if level and level.has_method("lever_pulled"):
		level.lever_pulled(self)
